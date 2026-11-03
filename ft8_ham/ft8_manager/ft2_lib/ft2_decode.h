// Copied from ft8_lib (https://github.com/kgoba/ft8_lib, MIT license) for FT2.
// ft8_lib stays unmodified. Keep this copy in sync with it when ft8_lib is updated.

#ifndef _INCLUDE_FT2_DECODE_H_
#define _INCLUDE_FT2_DECODE_H_

#include <ft8/decode.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// ftx_find_candidates for FT2: FT4 sync score over a time window sized for 24 ms symbols.
int ft2_find_candidates(const ftx_waterfall_t* wf, int num_candidates, ftx_candidate_t heap[], int min_score);

#ifdef __cplusplus
}
#endif

#endif // _INCLUDE_FT2_DECODE_H_
