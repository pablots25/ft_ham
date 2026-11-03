//
//  ft8_EngineProtocol.h
//  ft_ham
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
#include <common/monitor.h>
#include "ft2_lib/ft2_constants.h"
#include "ft2_lib/ft2_decode.h"
#include "ft2_lib/ft2_monitor.h"
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_BEGIN

/// Digital protocol handled by the engine. Mirrors `DigitalMode` in Swift.
typedef NS_ENUM(NSInteger, FTXEngineProtocol) {
  FTXEngineProtocolFT8 NS_SWIFT_NAME(ft8) = 0,
  FTXEngineProtocolFT4 NS_SWIFT_NAME(ft4) = 1,
  FTXEngineProtocolFT2 NS_SWIFT_NAME(ft2) = 2,
};

/// ft8_lib protocol for an engine protocol. FT2 uses the FT4 frame layout, so
/// ft8_lib sees its waterfall as FT4. FT2 timing comes from ft2_lib.
static inline ftx_protocol_t ftx_protocol_for_mode(FTXEngineProtocol mode) {
  switch (mode) {
  case FTXEngineProtocolFT4:
  case FTXEngineProtocolFT2:
    return FTX_PROTOCOL_FT4;
  case FTXEngineProtocolFT8:
  default:
    return FTX_PROTOCOL_FT8;
  }
}

/// monitor_init for the mode: ft2_lib for FT2, ft8_lib otherwise.
/// Release with ft8_lib's monitor_free in every mode.
static inline void ftx_monitor_init_for_mode(monitor_t *mon, const monitor_config_t *cfg,
                                             FTXEngineProtocol mode) {
  if (mode == FTXEngineProtocolFT2) {
    ft2_monitor_init(mon, cfg);
  } else {
    monitor_init(mon, cfg);
  }
}

/// Candidate search for the mode: ft2_lib for FT2, ft8_lib otherwise.
static inline int ftx_find_candidates_for_mode(const ftx_waterfall_t *wf, int num_candidates,
                                               ftx_candidate_t heap[], int min_score,
                                               FTXEngineProtocol mode) {
  if (mode == FTXEngineProtocolFT2) {
    return ft2_find_candidates(wf, num_candidates, heap, min_score);
  }
  return ftx_find_candidates(wf, num_candidates, heap, min_score);
}

NS_ASSUME_NONNULL_END
