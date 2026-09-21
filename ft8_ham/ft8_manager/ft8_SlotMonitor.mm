//
//  ft8_SlotMonitor.mm
//  ft_ham
//
//  Created by Pablo Turrion on 17/9/26.
//

#import "ft8_SlotMonitor.h"

#include <mach/mach_time.h>
#include <mutex>
#include <vector>

// Same analysis window as the batch decoder: the decoder looks for signals
// between these two frequencies, so this is also what the waterfall shows.
static const float kMonitorMinFrequency = 200.0f;
static const float kMonitorMaxFrequency = 3000.0f;
static const int kMonitorTimeOSR = 2;
static const int kMonitorFreqOSR = 2;
// ft8_lib analyses a whole symbol at once and produces both of its sub-rows
// together. Emitting them together makes the display jump two rows every
// 160 ms; instead the second sub-row is held back and released on the first
// audio callback at least this long after the first, so rows reach the
// display at a steady ~80 ms cadence. The audio tap runs every ~46 ms.
static const double kStaggerSeconds = 0.070;

static double monotonicSeconds(void) {
  static mach_timebase_info_data_t timebase;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    mach_timebase_info(&timebase);
  });
  return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}

// -----------------------------------------------------------------------------
// MARK: - FT8WaterfallSnapshot
// -----------------------------------------------------------------------------

@implementation FT8WaterfallSnapshot {
  ftx_waterfall_t _wf;
}

- (instancetype)initWithMonitor:(const monitor_t *)mon slotSequence:(NSUInteger)slotSequence {
  self = [super init];
  if (self) {
    _slotSequence = slotSequence;
    _wf = mon->wf;
    // Only the blocks written so far are copied; `max_blocks` shrinks to
    // match so nothing reads past the copy.
    size_t elems = (size_t)mon->wf.num_blocks * mon->wf.block_stride;
    _wf.mag = (WF_ELEM_T *)malloc(elems > 0 ? elems * sizeof(WF_ELEM_T) : 1);
    if (elems > 0) {
      memcpy(_wf.mag, mon->wf.mag, elems * sizeof(WF_ELEM_T));
    }
    _wf.max_blocks = mon->wf.num_blocks;
    _minBin = mon->min_bin;
    _symbolPeriod = mon->symbol_period;
    _duration = (double)mon->wf.num_blocks * mon->symbol_period;
  }
  return self;
}

- (void)dealloc {
  free(_wf.mag);
}

- (const ftx_waterfall_t *)waterfall {
  return &_wf;
}

@end

// -----------------------------------------------------------------------------
// MARK: - FT8SlotMonitor
// -----------------------------------------------------------------------------

@implementation FT8SlotMonitor {
  std::mutex _lock;
  monitor_t _mon;
  BOOL _monInitialised;
  // Audio waiting for a whole symbol block.
  std::vector<float> _pending;
  // One display row, bins interleaved into increasing-frequency order.
  std::vector<uint8_t> _row;
  // Second sub-row of the last block, waiting for its turn (see kStaggerSeconds).
  std::vector<uint8_t> _heldRow;
  BOOL _hasHeldRow;
  double _heldRowTime;
  float _heldRowFirstBinHz;
  float _heldRowBinHz;
  NSUInteger _heldRowSlotSequence;
  int _heldRowSlotRow;
}

- (instancetype)initWithSampleRate:(int)sampleRate isFT4:(BOOL)isFT4 {
  self = [super init];
  if (self) {
    _sampleRate = sampleRate;
    _isFT4 = isFT4;
    [self setUpMonitorLocked];
  }
  return self;
}

- (void)dealloc {
  if (_monInitialised) {
    monitor_free(&_mon);
  }
}

/// Caller holds `_lock` (or is the initialiser).
- (void)setUpMonitorLocked {
  if (_monInitialised) {
    monitor_free(&_mon);
    _monInitialised = NO;
  }
  monitor_config_t cfg = {.f_min = kMonitorMinFrequency,
                          .f_max = kMonitorMaxFrequency,
                          .sample_rate = _sampleRate,
                          .time_osr = kMonitorTimeOSR,
                          .freq_osr = kMonitorFreqOSR,
                          .protocol = _isFT4 ? FTX_PROTOCOL_FT4 : FTX_PROTOCOL_FT8};
  monitor_init(&_mon, &cfg);
  _monInitialised = YES;

  // ft8_lib sizes the store to exactly one slot (93 blocks = 14.88 s for
  // FT8), so the block that completes just after the 15 s boundary would
  // not fit. The sequencer snapshots at that boundary, but from the main
  // actor, which can run late; give the store a whole extra slot so a late
  // snapshot still finds the slot intact instead of a reset one.
  int headroomBlocks = _mon.wf.max_blocks * 2;
  size_t bytes = (size_t)headroomBlocks * _mon.wf.block_stride * sizeof(WF_ELEM_T);
  WF_ELEM_T *bigger = (WF_ELEM_T *)realloc(_mon.wf.mag, bytes);
  if (bigger != NULL) {
    _mon.wf.mag = bigger;
    _mon.wf.max_blocks = headroomBlocks;
  }

  _pending.clear();
  _pending.reserve((size_t)_mon.block_size);
  _row.assign((size_t)_mon.wf.num_bins * _mon.wf.freq_osr, 0);
  _heldRow.assign(_row.size(), 0);
  _hasHeldRow = NO;
}

- (float)rowPeriod {
  return _mon.symbol_period / (float)kMonitorTimeOSR;
}

- (float)minFrequency {
  return (float)_mon.min_bin / _mon.symbol_period;
}

- (float)maxFrequency {
  // Last column is bin (max_bin - 1) at the top frequency subdivision.
  float binHz = 1.0f / (_mon.symbol_period * (float)kMonitorFreqOSR);
  return self.minFrequency + (float)(_row.size() - 1) * binHz;
}

- (void)feedSamples:(const float *)samples count:(NSUInteger)count {
  if (samples == NULL || count == 0) {
    return;
  }
  std::lock_guard<std::mutex> guard(_lock);

  const double now = monotonicSeconds();
  if (_hasHeldRow && now - _heldRowTime >= kStaggerSeconds) {
    [self emitHeldRowLocked];
  }

  const size_t blockSize = (size_t)_mon.block_size;
  size_t pos = 0;
  while (pos < count) {
    size_t take = std::min(blockSize - _pending.size(), (size_t)count - pos);
    _pending.insert(_pending.end(), samples + pos, samples + pos + take);
    pos += take;
    if (_pending.size() < blockSize) {
      break;
    }

    // The sequencer normally resets us every slot, and the store holds two.
    // If no reset came for that long (app suspended, timer stalled) keep the
    // display alive by starting over rather than silently dropping every
    // block from here on.
    if (_mon.wf.num_blocks >= _mon.wf.max_blocks) {
      monitor_reset(&_mon);
      _slotSequence += 1;
    }

    int block = _mon.wf.num_blocks;
    monitor_process(&_mon, _pending.data());
    _pending.clear();
    [self emitRowsForBlockLocked:block atTime:now];
  }
}

/// Copies time subdivision `timeSub` of `block` into `row`, bins in
/// increasing-frequency order. Caller holds `_lock`.
- (void)copyRowOfBlock:(int)block timeSub:(int)timeSub into:(std::vector<uint8_t> &)row {
  const ftx_waterfall_t *wf = &_mon.wf;
  const int numBins = wf->num_bins;
  const int freqOSR = wf->freq_osr;
  // Storage is [block][time_sub][freq_sub][bin]; the display wants
  // frequency monotonic, i.e. bin-major with the subdivisions interleaved.
  const WF_ELEM_T *base = wf->mag + (size_t)block * wf->block_stride +
                          (size_t)timeSub * freqOSR * numBins;
  for (int bin = 0; bin < numBins; ++bin) {
    for (int sub = 0; sub < freqOSR; ++sub) {
      row[(size_t)bin * freqOSR + sub] = base[(size_t)sub * numBins + bin];
    }
  }
}

/// Emits the first sub-row of `block` now and holds the last one back
/// (see kStaggerSeconds). Any row still held from the previous block goes
/// out first so rows never reorder. Caller holds `_lock`.
- (void)emitRowsForBlockLocked:(int)block atTime:(double)now {
  if (self.rowHandler == nil) {
    _hasHeldRow = NO;
    return;
  }
  if (_hasHeldRow) {
    [self emitHeldRowLocked];
  }
  const ftx_waterfall_t *wf = &_mon.wf;
  const float binHz = 1.0f / (_mon.symbol_period * (float)wf->freq_osr);
  const float firstBinHz = (float)_mon.min_bin / _mon.symbol_period;

  for (int timeSub = 0; timeSub < wf->time_osr - 1; ++timeSub) {
    [self copyRowOfBlock:block timeSub:timeSub into:_row];
    self.rowHandler(_row.data(), (int)_row.size(), firstBinHz, binHz,
                    _slotSequence, block * wf->time_osr + timeSub);
  }
  [self copyRowOfBlock:block timeSub:wf->time_osr - 1 into:_heldRow];
  _heldRowFirstBinHz = firstBinHz;
  _heldRowBinHz = binHz;
  _heldRowSlotSequence = _slotSequence;
  _heldRowSlotRow = block * wf->time_osr + wf->time_osr - 1;
  _heldRowTime = now;
  _hasHeldRow = YES;
}

/// Caller holds `_lock`.
- (void)emitHeldRowLocked {
  _hasHeldRow = NO;
  FT8SlotMonitorRowHandler handler = self.rowHandler;
  if (handler != nil) {
    handler(_heldRow.data(), (int)_heldRow.size(), _heldRowFirstBinHz, _heldRowBinHz,
            _heldRowSlotSequence, _heldRowSlotRow);
  }
}

- (void)reconfigureIsFT4:(BOOL)isFT4 {
  std::lock_guard<std::mutex> guard(_lock);
  if (_isFT4 == isFT4) {
    return;
  }
  _isFT4 = isFT4;
  [self setUpMonitorLocked];   // also drops any held row: its geometry is gone
}

- (void)resetSlot {
  std::lock_guard<std::mutex> guard(_lock);
  [self resetSlotLocked];
}

/// Caller holds `_lock`.
- (void)resetSlotLocked {
  // The held row belongs to the slot that just ended; let it out first.
  if (_hasHeldRow) {
    [self emitHeldRowLocked];
  }
  monitor_reset(&_mon);
  _slotSequence += 1;
  // Drop the partial block so block 0 starts at the reset instant. Up to one
  // symbol of audio is skipped, which is exactly the audio that straddles
  // the slot boundary and belongs to neither slot.
  _pending.clear();
}

- (FT8WaterfallSnapshot *)snapshotAndReset {
  std::lock_guard<std::mutex> guard(_lock);
  FT8WaterfallSnapshot *snapshot =
      [[FT8WaterfallSnapshot alloc] initWithMonitor:&_mon slotSequence:_slotSequence];
  [self resetSlotLocked];
  return snapshot;
}

@end
