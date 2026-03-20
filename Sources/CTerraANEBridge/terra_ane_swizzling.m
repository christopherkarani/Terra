#import "include/terra_ane_bridge.h"
#import <Foundation/Foundation.h>

#if !defined(APP_STORE) && !defined(DISABLE_ANE_PRIVATE_APIS)

#import <objc/runtime.h>

// Thread-safe metrics storage
static terra_ane_metrics_t _terra_ane_current_metrics = {0};
static NSLock *_terra_ane_lock = nil;
static BOOL _terra_ane_swizzled = NO;

static void _terra_ane_ensure_lock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _terra_ane_lock = [[NSLock alloc] init];
    });
}

bool terra_ane_is_available(void) {
    Class cls = NSClassFromString(@"_ANEPerformanceStats");
    return cls != nil;
}

bool terra_ane_install_swizzling(void) {
    _terra_ane_ensure_lock();

    if (_terra_ane_swizzled) return true;
    if (!terra_ane_is_available()) return false;

    // Mark as swizzled — actual swizzling of private APIs would go here
    // when reverse-engineering the _ANEPerformanceStats interface.
    // For now, this is a probe point that confirms API availability.
    _terra_ane_swizzled = YES;
    [_terra_ane_lock lock];
    _terra_ane_current_metrics.available = true;
    [_terra_ane_lock unlock];

    return true;
}

terra_ane_metrics_t terra_ane_get_metrics(void) {
    _terra_ane_ensure_lock();
    [_terra_ane_lock lock];
    terra_ane_metrics_t copy = _terra_ane_current_metrics;
    [_terra_ane_lock unlock];
    return copy;
}

void terra_ane_reset_metrics(void) {
    _terra_ane_ensure_lock();
    [_terra_ane_lock lock];
    bool was_available = _terra_ane_current_metrics.available;
    _terra_ane_current_metrics = (terra_ane_metrics_t){0};
    _terra_ane_current_metrics.available = was_available;
    [_terra_ane_lock unlock];
}

#else
// APP_STORE build — all functions are stubs

bool terra_ane_is_available(void) {
    return false;
}

bool terra_ane_install_swizzling(void) {
    return false;
}

terra_ane_metrics_t terra_ane_get_metrics(void) {
    return (terra_ane_metrics_t){0};
}

void terra_ane_reset_metrics(void) {
    // no-op
}

#endif
