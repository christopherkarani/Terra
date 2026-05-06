#ifndef TERRA_ANE_BRIDGE_H
#define TERRA_ANE_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t hardware_execution_time_ns;
    double host_overhead_us;
    int32_t segment_count;
    bool fully_ane;
    bool available;
} terra_ane_metrics_t;

/// Install ObjC method swizzling to capture ANE performance stats.
/// Returns true only if real runtime collection hooks were installed.
bool terra_ane_install_swizzling(void);

/// Check if the ANE private APIs are available on this device/OS.
bool terra_ane_is_available(void);

/// Returns true only when runtime metric collection hooks are active.
bool terra_ane_is_collecting(void);

/// Get the latest captured metrics. Returns zeroed struct if not available.
terra_ane_metrics_t terra_ane_get_metrics(void);

/// Reset captured metrics counters.
void terra_ane_reset_metrics(void);

#ifdef __cplusplus
}
#endif

#endif /* TERRA_ANE_BRIDGE_H */
