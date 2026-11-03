// Copied from ft8_lib (https://github.com/kgoba/ft8_lib, MIT license) for FT2.
// ft8_lib stays unmodified. Keep this copy in sync with it when ft8_lib is updated.

#ifndef _INCLUDE_FT2_MONITOR_H_
#define _INCLUDE_FT2_MONITOR_H_

#include <common/monitor.h>

#ifdef __cplusplus
extern "C"
{
#endif

/// monitor_init for FT2: FT2 symbol period and slot time. cfg->protocol is ignored.
/// Release with ft8_lib's monitor_free.
void ft2_monitor_init(monitor_t* me, const monitor_config_t* cfg);

#ifdef __cplusplus
}
#endif

#endif // _INCLUDE_FT2_MONITOR_H_
