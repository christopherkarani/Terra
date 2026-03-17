# Android.mk — NDK build file for Terra JNI bridge
#
# NOTE: In production, Zig cross-compilation replaces NDK. This file is
# provided for teams that prefer the traditional NDK toolchain.
#
# Usage:
#   ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=jni/Android.mk

LOCAL_PATH := $(call my-dir)

# ── Prebuilt libtera (from Zig cross-compilation) ────────────────────────
include $(CLEAR_VARS)
LOCAL_MODULE := terra_prebuilt
LOCAL_SRC_FILES := $(TARGET_ARCH_ABI)/libtera.a
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/../../zig-core/include
include $(PREBUILT_STATIC_LIBRARY)

# ── JNI bridge shared library ────────────────────────────────────────────
include $(CLEAR_VARS)
LOCAL_MODULE := terra
LOCAL_SRC_FILES := terra_jni.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/../../zig-core/include
LOCAL_STATIC_LIBRARIES := terra_prebuilt
LOCAL_LDLIBS := -llog
include $(BUILD_SHARED_LIBRARY)
