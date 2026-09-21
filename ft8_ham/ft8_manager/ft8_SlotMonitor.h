//
//  ft8_SlotMonitor.h
//  ft_ham
//
//  Created by Pablo Turrion on 17/9/26.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
#include <common/monitor.h>
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_BEGIN

/// An immutable copy of one slot's spectrogram, taken from `FT8SlotMonitor`
/// so the decoder can work on it while the monitor keeps filling the next slot.
@interface FT8WaterfallSnapshot : NSObject

/// The copied waterfall. Valid for the lifetime of the snapshot.
@property(nonatomic, readonly) const ftx_waterfall_t *waterfall;
/// First FFT bin (in tone-spacing units) of the analysed band.
@property(nonatomic, readonly) int minBin;
/// FT8/FT4 symbol period in seconds.
@property(nonatomic, readonly) float symbolPeriod;
/// Seconds of audio the snapshot covers (blocks × symbol period).
@property(nonatomic, readonly) double duration;
/// Which slot this is (see `FT8SlotMonitor.slotSequence`).
@property(nonatomic, readonly) NSUInteger slotSequence;

@end

/// One spectrogram row for the waterfall display: `count` magnitudes in
/// increasing frequency order, starting at `firstBinHz` and `binHz` apart.
/// Values are 0–255 in 0.5 dB steps, 0 = −120 dB. `slotSequence` and
/// `slotRow` say which slot the row belongs to and how many rows into it
/// it is, so the display can place a decode at the row its signal began.
/// The pointer is only valid during the call, and the call happens on the
/// audio thread.
typedef void (^FT8SlotMonitorRowHandler)(const uint8_t *row, int count,
                                         float firstBinHz, float binHz,
                                         NSUInteger slotSequence, int slotRow);

/// Streaming FT8/FT4 spectrogram shared by the waterfall and the decoder.
///
/// Wraps one persistent ft8_lib `monitor_t`: audio is accumulated into
/// symbol-length blocks and analysed as it arrives, every analysed sub-block
/// is handed to `rowHandler`, and at the end of a slot `snapshotAndReset`
/// yields the same data the decoder needs — so audio goes through one FFT
/// pass, and what the waterfall shows is exactly what the decoder sees.
///
/// Thread-safe: `feedSamples:count:` runs on the audio thread, the other
/// methods on whichever thread drives the slot sequencer.
@interface FT8SlotMonitor : NSObject

- (instancetype)initWithSampleRate:(int)sampleRate isFT4:(BOOL)isFT4;

@property(nonatomic, readonly) int sampleRate;
@property(nonatomic, readonly) BOOL isFT4;
/// Seconds between two emitted rows (symbol period / time oversampling).
@property(nonatomic, readonly) float rowPeriod;
/// Counts slots: incremented by every reset. Rows and snapshots carry it,
/// which ties a decoded message back to the rows its signal occupies.
@property(nonatomic, readonly) NSUInteger slotSequence;
/// Lowest / highest frequency analysed, in Hz.
@property(nonatomic, readonly) float minFrequency;
@property(nonatomic, readonly) float maxFrequency;
@property(nonatomic, copy, nullable) FT8SlotMonitorRowHandler rowHandler;

/// Appends audio at `sampleRate`. Any count is fine; whole symbol blocks are
/// analysed as soon as they complete.
- (void)feedSamples:(const float *)samples count:(NSUInteger)count;

/// Switches protocol. Discards the slot in progress.
- (void)reconfigureIsFT4:(BOOL)isFT4;

/// Starts a new slot: forgets the audio analysed so far (and any partial
/// block) so the next block is the slot's first. Call at the slot boundary.
- (void)resetSlot;

/// Copies the slot analysed so far and then does what `resetSlot` does, as
/// one atomic step so no block is lost or counted twice.
- (FT8WaterfallSnapshot *)snapshotAndReset;

@end

NS_ASSUME_NONNULL_END
