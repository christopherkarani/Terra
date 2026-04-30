#import "include/terra_ane_bridge.h"
#import <Foundation/Foundation.h>

// P0-7: Safe-by-default gating.
//
// The private-API code path is compiled ONLY when `ENABLE_ANE_PRIVATE_APIS`
// is explicitly defined by the build system. Package.swift defines this for
// the Debug configuration only, so App Store and Developer ID release builds
// MUST NOT reference `_ANEPerformanceStats`, and the symbol never lands in
// the shipped binary.
//
// To enable on a Developer ID notarized release build, pass:
//   `-Xcc -DENABLE_ANE_PRIVATE_APIS`
// or edit Package.swift's CTerraANEBridge cSettings stanza.
#if defined(ENABLE_ANE_PRIVATE_APIS)

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
    static BOOL _cached = NO;
    static BOOL _result = NO;
    if (!_cached) {
        _result = NSClassFromString(@"_ANEPerformanceStats") != nil;
        _cached = YES;
    }
    return _result;
}

bool terra_ane_install_swizzling(void) {
    _terra_ane_ensure_lock();

    if (_terra_ane_swizzled) return false;
    if (!terra_ane_is_available()) return false;

    // The private API surface is probe-only until concrete performance-stat
    // methods are mapped. Report availability separately from collection so
    // callers do not treat zero metrics as real ANE execution evidence.
    [_terra_ane_lock lock];
    _terra_ane_current_metrics.available = true;
    [_terra_ane_lock unlock];

    return false;
}

bool terra_ane_is_collecting(void) {
    return _terra_ane_swizzled;
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
// App Store / Developer ID release default — all functions are stubs and
// no private symbol references reach the linker.

bool terra_ane_is_available(void) {
    return false;
}

bool terra_ane_is_collecting(void) {
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
