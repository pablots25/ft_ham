//! C ABI over the RR73 WSPR codec (`rr73-wspr`) and decoder (`rr73-decode::wspr`).
//!
//! Built as a static library and linked into FT Ham. The header that matches this file is
//! `include/wspr_ffi.h`; keep both in sync.
//!
//! Conventions
//! - Decoding takes one 2-minute slot of mono float audio with sample 0 at the start of an
//!   even UTC minute. Audio at any rate from 8 to 192 kHz is accepted and resampled to 12 kHz.
//! - Frequencies are the signal centre in Hz of audio; DT is seconds from the nominal start
//!   (1 s into the slot); SNR is in a 2500 Hz reference bandwidth.
//! - Every entry point catches panics and returns `WSPR_ERR_INTERNAL` instead of unwinding
//!   into C.
//! - A `WsprDecoder` keeps the callsign hash table used for type 3 messages. It is not
//!   thread-safe: use one per thread (or serialise calls).

#![allow(unsafe_code)]

use std::ffi::{CStr, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

use rr73_decode::wspr::{WsprConfig, WsprContext, decode_wspr};
use rr73_dsp::resample::Resampler;

/// Success.
pub const WSPR_OK: i32 = 0;
/// A required pointer was null.
pub const WSPR_ERR_NULL: i32 = -1;
/// The text is not valid UTF-8 or does not pack into a WSPR message.
pub const WSPR_ERR_INVALID_MESSAGE: i32 = -2;
/// Signal centre outside 1400..=1600 Hz.
pub const WSPR_ERR_INVALID_FREQUENCY: i32 = -3;
/// Sample rate outside 8000..=192000 Hz.
pub const WSPR_ERR_INVALID_SAMPLE_RATE: i32 = -4;
/// The output buffer is too small; the required size was written to the size out-parameter.
pub const WSPR_ERR_BUFFER_TOO_SMALL: i32 = -5;
/// A panic was caught inside the library.
pub const WSPR_ERR_INTERNAL: i32 = -99;

/// Internal sample rate of the WSPR protocol.
const PROTOCOL_RATE_HZ: u32 = rr73_wspr::SAMPLE_RATE_HZ;
/// Lowest and highest signal centre accepted for transmission (the 200 Hz WSPR window).
const TX_RANGE_HZ: (f32, f32) = (1400.0, 1600.0);
/// Size of the text field in `WsprSpot`, including the terminating NUL.
pub const WSPR_TEXT_CAPACITY: usize = 48;

/// One decoded WSPR spot.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct WsprSpot {
    /// NUL-terminated message text as WSJT-X shows it (`K1ABC FN42 37`, `PJ4/K1ABC 33`,
    /// `<K1ABC> FN42AB 37`).
    pub text: [c_char; WSPR_TEXT_CAPACITY],
    /// Message type: 1, 2 or 3.
    pub message_type: u8,
    /// Reported power, in dBm.
    pub power_dbm: u8,
    /// Signal centre, in Hz of audio.
    pub freq_hz: f32,
    /// Start time offset from the nominal start (1 s into the slot), in seconds.
    pub dt_s: f32,
    /// Frequency drift, in Hz per second.
    pub drift_hz_per_s: f32,
    /// SNR in 2500 Hz, in dB.
    pub snr_db: f32,
    /// Sync score, in standard deviations above noise.
    pub score: f32,
    /// Decoding pass that found it, from 1.
    pub pass: u32,
}

/// Opaque decoder handle.
pub struct WsprDecoder {
    ctx: WsprContext,
}

fn guard<F: FnOnce() -> i32>(f: F) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(WSPR_ERR_INTERNAL)
}

fn valid_rate(rate: u32) -> bool {
    (8_000..=192_000).contains(&rate)
}

/// Reads a C string as UTF-8.
///
/// # Safety
/// `text` must be null or point to a NUL-terminated string.
unsafe fn read_text<'a>(text: *const c_char) -> Result<&'a str, i32> {
    if text.is_null() {
        return Err(WSPR_ERR_NULL);
    }
    // SAFETY: non-null and NUL-terminated per the contract.
    unsafe { CStr::from_ptr(text) }
        .to_str()
        .map_err(|_| WSPR_ERR_INVALID_MESSAGE)
}

/// Copies `s` into a fixed C buffer, truncating on a UTF-8 boundary and NUL-terminating.
fn write_c_text(dst: &mut [c_char], s: &str) {
    let max = dst.len().saturating_sub(1);
    let mut end = s.len().min(max);
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    for (d, b) in dst.iter_mut().zip(s.as_bytes()[..end].iter()) {
        *d = *b as c_char;
    }
    if let Some(slot) = dst.get_mut(end) {
        *slot = 0;
    }
}

fn parse_message(text: &str) -> Result<rr73_wspr::Message, i32> {
    rr73_wspr::Message::parse(text.trim()).map_err(|_| WSPR_ERR_INVALID_MESSAGE)
}

// MARK: - Version

/// Library version (NUL-terminated, static).
#[unsafe(no_mangle)]
pub extern "C" fn wspr_ffi_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

// MARK: - Decoder lifetime

/// Creates a decoder with an empty callsign hash table. Returns null on failure.
/// Free with `wspr_decoder_free`.
#[unsafe(no_mangle)]
pub extern "C" fn wspr_decoder_new() -> *mut WsprDecoder {
    catch_unwind(|| {
        Box::into_raw(Box::new(WsprDecoder {
            ctx: WsprContext::new(),
        }))
    })
    .unwrap_or(ptr::null_mut())
}

/// Frees a decoder. Null is ignored.
///
/// # Safety
/// `decoder` must be null or a pointer returned by `wspr_decoder_new` that was not freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wspr_decoder_free(decoder: *mut WsprDecoder) {
    if decoder.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: pointer came from Box::into_raw in wspr_decoder_new.
        drop(unsafe { Box::from_raw(decoder) });
    }));
}

/// Number of callsigns the decoder has learned (for type 3 messages).
///
/// # Safety
/// `decoder` must be null or a live decoder.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wspr_decoder_known_callsigns(decoder: *const WsprDecoder) -> usize {
    if decoder.is_null() {
        return 0;
    }
    // SAFETY: live decoder per the contract.
    unsafe { &*decoder }.ctx.hashes.len()
}

// MARK: - Decoding

/// Decodes one WSPR slot.
///
/// `samples`/`len`: mono audio of one 2-minute slot, sample 0 at the even UTC minute.
/// `sample_rate`: 8000..=192000 Hz; resampled to 12 kHz internally.
/// `deep`: non-zero uses the slower `wspr-deep` preset (more candidates and Fano steps).
/// `out`/`capacity`: caller buffer for spots (may be null when `capacity` is 0).
/// `count`: receives the number of spots decoded. When it exceeds `capacity`, the first
/// `capacity` spots are written and `WSPR_ERR_BUFFER_TOO_SMALL` is returned.
///
/// # Safety
/// `decoder` must be a live decoder; `samples` must point to `len` floats; `out` must point
/// to `capacity` writable `WsprSpot`s; `count` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wspr_decode(
    decoder: *mut WsprDecoder,
    samples: *const f32,
    len: usize,
    sample_rate: u32,
    deep: i32,
    out: *mut WsprSpot,
    capacity: usize,
    count: *mut usize,
) -> i32 {
    guard(|| {
        if decoder.is_null() || count.is_null() || (samples.is_null() && len > 0) {
            return WSPR_ERR_NULL;
        }
        if out.is_null() && capacity > 0 {
            return WSPR_ERR_NULL;
        }
        if !valid_rate(sample_rate) {
            return WSPR_ERR_INVALID_SAMPLE_RATE;
        }
        // SAFETY: pointers checked above; sizes per the contract.
        let decoder = unsafe { &mut *decoder };
        let input: &[f32] = if len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(samples, len) }
        };

        let resampled;
        let audio: &[f32] = if sample_rate == PROTOCOL_RATE_HZ {
            input
        } else {
            let Ok(rs) = Resampler::new(sample_rate, PROTOCOL_RATE_HZ) else {
                return WSPR_ERR_INVALID_SAMPLE_RATE;
            };
            let mut buf = Vec::new();
            rs.process(input, &mut buf);
            resampled = buf;
            &resampled
        };

        let config = if deep != 0 {
            WsprConfig::wspr_deep()
        } else {
            WsprConfig::wspr()
        };
        let report = decode_wspr(audio, &config, &mut decoder.ctx);

        // SAFETY: count is non-null.
        unsafe { *count = report.decodes.len() };
        for (i, d) in report.decodes.iter().take(capacity).enumerate() {
            let mut spot = WsprSpot {
                text: [0; WSPR_TEXT_CAPACITY],
                message_type: d.message.message_type(),
                power_dbm: d.message.power_dbm(),
                freq_hz: d.freq_hz,
                dt_s: d.dt_s,
                drift_hz_per_s: d.drift_hz_per_s,
                snr_db: d.snr_db,
                score: d.score,
                pass: d.pass,
            };
            write_c_text(&mut spot.text, &d.text);
            // SAFETY: i < capacity and out points to capacity spots.
            unsafe { out.add(i).write(spot) };
        }
        if report.decodes.len() > capacity {
            WSPR_ERR_BUFFER_TOO_SMALL
        } else {
            WSPR_OK
        }
    })
}

// MARK: - Encoding

/// Checks whether `text` packs into a WSPR message (`K1ABC FN42 37`, `PJ4/K1ABC 33`,
/// `K1ABC/P 33`, `<K1ABC> FN42AB 37`). Returns the message type (1, 2 or 3) or a negative
/// error code.
///
/// # Safety
/// `text` must be null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wspr_message_type(text: *const c_char) -> i32 {
    guard(|| {
        // SAFETY: per the contract.
        let text = match unsafe { read_text(text) } {
            Ok(t) => t,
            Err(e) => return e,
        };
        match parse_message(text) {
            Ok(msg) => i32::from(msg.message_type()),
            Err(e) => e,
        }
    })
}

/// Number of samples one transmission (162 symbols, 110.6 s) takes at `sample_rate`,
/// or 0 for a rate outside 8000..=192000 Hz.
#[unsafe(no_mangle)]
pub extern "C" fn wspr_transmission_samples(sample_rate: u32) -> usize {
    if !valid_rate(sample_rate) {
        return 0;
    }
    let num = rr73_wspr::TRANSMISSION_SAMPLES as u64 * u64::from(sample_rate);
    let den = u64::from(PROTOCOL_RATE_HZ);
    ((num + den / 2) / den) as usize
}

/// Renders `text` as one WSPR transmission: phase-continuous 4-FSK, peak amplitude 1, with
/// 20 ms ramps, signal centre `freq_hz` (1400..=1600 Hz) at `sample_rate`. The audio starts
/// with the first symbol: play it 1 s after an even UTC minute.
///
/// `out`/`capacity`: caller buffer, at least `wspr_transmission_samples(sample_rate)` floats.
/// `written`: receives the number of samples (or the required size on
/// `WSPR_ERR_BUFFER_TOO_SMALL`).
///
/// # Safety
/// `text` must be a NUL-terminated string; `out` must point to `capacity` writable floats;
/// `written` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wspr_synthesize(
    text: *const c_char,
    freq_hz: f32,
    sample_rate: u32,
    out: *mut f32,
    capacity: usize,
    written: *mut usize,
) -> i32 {
    guard(|| {
        if written.is_null() || (out.is_null() && capacity > 0) {
            return WSPR_ERR_NULL;
        }
        // SAFETY: per the contract.
        let text = match unsafe { read_text(text) } {
            Ok(t) => t,
            Err(e) => return e,
        };
        if !(freq_hz.is_finite() && (TX_RANGE_HZ.0..=TX_RANGE_HZ.1).contains(&freq_hz)) {
            return WSPR_ERR_INVALID_FREQUENCY;
        }
        if !valid_rate(sample_rate) {
            return WSPR_ERR_INVALID_SAMPLE_RATE;
        }
        let msg = match parse_message(text) {
            Ok(m) => m,
            Err(e) => return e,
        };
        let Ok(symbols) = rr73_wspr::channel_symbols(&msg) else {
            return WSPR_ERR_INVALID_MESSAGE;
        };
        let audio = rr73_wspr::synth::fsk(&symbols, f64::from(freq_hz), 0.0, sample_rate, 1.0);
        // SAFETY: written is non-null.
        unsafe { *written = audio.len() };
        if audio.len() > capacity {
            return WSPR_ERR_BUFFER_TOO_SMALL;
        }
        // SAFETY: out points to at least capacity >= audio.len() floats.
        unsafe { ptr::copy_nonoverlapping(audio.as_ptr(), out, audio.len()) };
        WSPR_OK
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode(samples: &[f32], rate: u32) -> Vec<WsprSpot> {
        let dec = wspr_decoder_new();
        let mut out = vec![
            WsprSpot {
                text: [0; WSPR_TEXT_CAPACITY],
                message_type: 0,
                power_dbm: 0,
                freq_hz: 0.0,
                dt_s: 0.0,
                drift_hz_per_s: 0.0,
                snr_db: 0.0,
                score: 0.0,
                pass: 0,
            };
            16
        ];
        let mut n = 0usize;
        let rc = unsafe {
            wspr_decode(dec, samples.as_ptr(), samples.len(), rate, 0, out.as_mut_ptr(), out.len(), &mut n)
        };
        unsafe { wspr_decoder_free(dec) };
        assert_eq!(rc, WSPR_OK);
        out.truncate(n);
        out
    }

    fn text(spot: &WsprSpot) -> String {
        unsafe { CStr::from_ptr(spot.text.as_ptr()) }.to_string_lossy().into_owned()
    }

    fn slot_with(text: &str, freq: f32, rate: u32) -> Vec<f32> {
        let c = std::ffi::CString::new(text).unwrap();
        let n = wspr_transmission_samples(rate);
        let mut tx = vec![0f32; n];
        let mut written = 0;
        let rc = unsafe { wspr_synthesize(c.as_ptr(), freq, rate, tx.as_mut_ptr(), n, &mut written) };
        assert_eq!(rc, WSPR_OK);
        let mut slot = vec![0f32; 120 * rate as usize];
        let start = rate as usize; // 1 s into the slot
        for (i, s) in tx.iter().enumerate() {
            slot[start + i] = 0.1 * s;
        }
        slot
    }

    #[test]
    fn round_trip_at_12k() {
        let slot = slot_with("EA4IQL IN80 37", 1500.0, 12_000);
        let spots = decode(&slot, 12_000);
        assert_eq!(spots.len(), 1);
        assert_eq!(text(&spots[0]), "EA4IQL IN80 37");
        assert_eq!(spots[0].message_type, 1);
        assert_eq!(spots[0].power_dbm, 37);
        assert!((spots[0].freq_hz - 1500.0).abs() < 0.5);
    }

    #[test]
    fn round_trip_at_44k1_with_resampling() {
        let slot = slot_with("K1ABC FN42 23", 1450.0, 44_100);
        let spots = decode(&slot, 44_100);
        assert_eq!(spots.len(), 1);
        assert_eq!(text(&spots[0]), "K1ABC FN42 23");
    }

    #[test]
    fn message_types() {
        let t = |s: &str| unsafe { wspr_message_type(std::ffi::CString::new(s).unwrap().as_ptr()) };
        assert_eq!(t("K1ABC FN42 37"), 1);
        assert_eq!(t("PJ4/K1ABC 33"), 2);
        assert_eq!(t("<K1ABC> FN42AB 37"), 3);
        assert_eq!(t("NOT A MESSAGE"), WSPR_ERR_INVALID_MESSAGE);
        assert_eq!(unsafe { wspr_message_type(ptr::null()) }, WSPR_ERR_NULL);
    }

    #[test]
    fn synthesize_rejects_bad_input() {
        let c = std::ffi::CString::new("K1ABC FN42 37").unwrap();
        let mut w = 0;
        let mut small = [0f32; 10];
        assert_eq!(
            unsafe { wspr_synthesize(c.as_ptr(), 1700.0, 12_000, small.as_mut_ptr(), 10, &mut w) },
            WSPR_ERR_INVALID_FREQUENCY
        );
        assert_eq!(
            unsafe { wspr_synthesize(c.as_ptr(), 1500.0, 12_000, small.as_mut_ptr(), 10, &mut w) },
            WSPR_ERR_BUFFER_TOO_SMALL
        );
        assert_eq!(w, wspr_transmission_samples(12_000));
        assert_eq!(w, 1_327_104);
    }

    #[test]
    fn noise_only_slot_gives_no_spots() {
        // Deterministic LCG noise.
        let mut x: u32 = 12345;
        let slot: Vec<f32> = (0..1_440_000)
            .map(|_| {
                x = x.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                (x >> 8) as f32 / (1u32 << 24) as f32 - 0.5
            })
            .collect();
        assert!(decode(&slot, 12_000).is_empty());
    }

    /// Mirrors the app's capture: 44.1 kHz mic audio whose buffer starts 0.2 s after the
    /// slot boundary and is padded with 0.2 s of silence, signal at -24 dB SNR (2500 Hz).
    #[test]
    fn decodes_padded_noisy_capture_like_the_app() {
        let rate = 44_100u32;
        let fs = rate as f32;
        let c = std::ffi::CString::new("EA4IQL IN80 37").unwrap();
        let n = wspr_transmission_samples(rate);
        let mut tx = vec![0f32; n];
        let mut w = 0;
        assert_eq!(unsafe { wspr_synthesize(c.as_ptr(), 1490.0, rate, tx.as_mut_ptr(), n, &mut w) }, WSPR_OK);

        // Air: 120 s slot, transmission at +1.0 s, amplitude a, Gaussian noise for -24 dB.
        let a = 0.1f32;
        let snr_db = -24.0f32;
        let ps = a * a / 2.0;
        let pn_2500 = ps / 10f32.powf(snr_db / 10.0);
        let sigma = (pn_2500 * (fs / 2.0) / 2500.0).sqrt();
        let mut x: u64 = 0x9E37_79B9_7F4A_7C15;
        let mut uni = || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            ((x >> 11) as f64 / (1u64 << 53) as f64).max(1e-12) as f32
        };
        let total = 120 * rate as usize;
        let mut air = vec![0f32; total];
        for i in (0..total).step_by(2) {
            let (u1, u2) = (uni(), uni());
            let r = (-2.0 * u1.ln()).sqrt() * sigma;
            air[i] = r * (std::f32::consts::TAU * u2).cos();
            if i + 1 < total {
                air[i + 1] = r * (std::f32::consts::TAU * u2).sin();
            }
        }
        for (i, s) in tx.iter().enumerate() {
            air[rate as usize + i] += a * s;
        }

        // App: buffer reset at +0.2 s, then padded back to slot alignment.
        let lost = (0.2 * fs) as usize;
        let mut captured = vec![0f32; lost];
        captured.extend_from_slice(&air[lost..]);

        let spots = decode(&captured, rate);
        assert_eq!(spots.len(), 1, "no decode at {snr_db} dB");
        assert_eq!(text(&spots[0]), "EA4IQL IN80 37");
        assert!(spots[0].dt_s.abs() < 0.1, "dt {}", spots[0].dt_s);
        assert!((spots[0].snr_db - snr_db).abs() < 2.0, "snr {}", spots[0].snr_db);
    }

    #[test]
    fn decode_reports_buffer_too_small() {
        let slot = slot_with("EA4IQL IN80 37", 1500.0, 12_000);
        let dec = wspr_decoder_new();
        let mut n = 0;
        let rc = unsafe { wspr_decode(dec, slot.as_ptr(), slot.len(), 12_000, 0, ptr::null_mut(), 0, &mut n) };
        unsafe { wspr_decoder_free(dec) };
        assert_eq!(rc, WSPR_ERR_BUFFER_TOO_SMALL);
        assert_eq!(n, 1);
    }
}
