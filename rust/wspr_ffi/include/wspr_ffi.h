//
//  wspr_ffi.h
//  FT Ham — WSPR codec/decoder (static library built from rust/wspr_ffi)
//
//  C ABI over RR73's WSPR implementation (https://github.com/nnamon/RR73, MIT).
//  Must match rust/wspr_ffi/src/lib.rs.
//
//  Conventions:
//   - Decoding takes one 2-minute slot of mono float audio, sample 0 at the start of an
//     even UTC minute, at any rate in 8000..192000 Hz (resampled to 12 kHz internally).
//   - Frequencies are the signal centre in Hz of audio; DT is seconds from the nominal
//     start (1 s into the slot); SNR is in 2500 Hz.
//   - A WsprDecoder is not thread-safe: use one per thread or serialise calls.
//

#ifndef WSPR_FFI_H
#define WSPR_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Return codes
#define WSPR_OK                       0
#define WSPR_ERR_NULL                (-1)
#define WSPR_ERR_INVALID_MESSAGE     (-2)
#define WSPR_ERR_INVALID_FREQUENCY   (-3)
#define WSPR_ERR_INVALID_SAMPLE_RATE (-4)
#define WSPR_ERR_BUFFER_TOO_SMALL    (-5)
#define WSPR_ERR_INTERNAL            (-99)

#define WSPR_TEXT_CAPACITY 48

/// One decoded WSPR spot.
typedef struct WsprSpot {
  char text[WSPR_TEXT_CAPACITY]; ///< NUL-terminated, e.g. "K1ABC FN42 37"
  uint8_t message_type;          ///< 1, 2 or 3
  uint8_t power_dbm;             ///< Reported power (dBm)
  float freq_hz;                 ///< Signal centre (Hz of audio)
  float dt_s;                    ///< Time offset from nominal start (s)
  float drift_hz_per_s;          ///< Drift (Hz/s)
  float snr_db;                  ///< SNR in 2500 Hz (dB)
  float score;                   ///< Sync score (std devs above noise)
  uint32_t pass;                 ///< Decoding pass, from 1
} WsprSpot;

/// Opaque decoder (keeps the callsign hash table for type 3 messages).
typedef struct WsprDecoder WsprDecoder;

/// Library version string (static).
const char *wspr_ffi_version(void);

/// Creates a decoder; NULL on failure. Free with wspr_decoder_free.
WsprDecoder *wspr_decoder_new(void);

/// Frees a decoder (NULL is ignored).
void wspr_decoder_free(WsprDecoder *decoder);

/// Number of callsigns learned so far (for type 3 messages).
size_t wspr_decoder_known_callsigns(const WsprDecoder *decoder);

/// Decodes one 2-minute slot.
/// @param deep  Non-zero selects the slower, more sensitive preset.
/// @param out   Buffer of `capacity` spots (may be NULL if capacity is 0).
/// @param count Receives the number of spots decoded. If larger than capacity, the first
///              `capacity` are written and WSPR_ERR_BUFFER_TOO_SMALL is returned.
int32_t wspr_decode(WsprDecoder *decoder, const float *samples, size_t len,
                    uint32_t sample_rate, int32_t deep, WsprSpot *out,
                    size_t capacity, size_t *count);

/// Message type (1, 2 or 3) if `text` packs into a WSPR message, or a negative error.
int32_t wspr_message_type(const char *text);

/// Samples in one transmission (110.6 s) at `sample_rate`; 0 for an invalid rate.
size_t wspr_transmission_samples(uint32_t sample_rate);

/// Renders one transmission (peak amplitude 1). Play it 1 s after an even UTC minute.
/// @param freq_hz Signal centre, 1400..1600 Hz.
/// @param out     Buffer of `capacity` floats (>= wspr_transmission_samples(sample_rate)).
/// @param written Receives the number of samples (or the required size on
///                WSPR_ERR_BUFFER_TOO_SMALL).
int32_t wspr_synthesize(const char *text, float freq_hz, uint32_t sample_rate,
                        float *out, size_t capacity, size_t *written);

#ifdef __cplusplus
}
#endif

#endif // WSPR_FFI_H
