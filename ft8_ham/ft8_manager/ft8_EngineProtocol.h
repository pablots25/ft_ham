//
//  ft8_EngineProtocol.h
//  ft_ham
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
#include <common/monitor.h>
#include <ft8/decode.h>
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_BEGIN

/// Digital protocol handled by the engine. Mirrors `DigitalMode` in Swift.
typedef NS_ENUM(NSInteger, FTXEngineProtocol) {
  FTXEngineProtocolFT8 NS_SWIFT_NAME(ft8) = 0,
  FTXEngineProtocolFT4 NS_SWIFT_NAME(ft4) = 1,
};

/// ft8_lib protocol for an engine protocol.
static inline ftx_protocol_t ftx_protocol_for_mode(FTXEngineProtocol mode) {
  switch (mode) {
  case FTXEngineProtocolFT4:
    return FTX_PROTOCOL_FT4;
  case FTXEngineProtocolFT8:
  default:
    return FTX_PROTOCOL_FT8;
  }
}

/// monitor_init for the mode. Release with ft8_lib's monitor_free.
static inline void ftx_monitor_init_for_mode(monitor_t *mon, const monitor_config_t *cfg,
                                             FTXEngineProtocol mode) {
  monitor_init(mon, cfg);
}

/// Candidate search for the mode.
static inline int ftx_find_candidates_for_mode(const ftx_waterfall_t *wf, int num_candidates,
                                               ftx_candidate_t heap[], int min_score,
                                               FTXEngineProtocol mode) {
  return ftx_find_candidates(wf, num_candidates, heap, min_score);
}

NS_ASSUME_NONNULL_END
