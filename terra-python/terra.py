"""
terra.py — Python ctypes wrapper for Terra Zig Core (libtera).

Auto-loadable binding generated from terra.h. Provides:
  - Terra: Main SDK handle (init/shutdown lifecycle)
  - TerraSpan: Span wrapper with attribute setters
  - TerraConfig: Configuration dataclass
  - SpanContext: Trace context propagation

Usage:
    from terra import Terra

    terra = Terra.init(service_name="my-service")

    with terra.span("inference", model="gpt-4") as span:
        span.set_string("gen_ai.request.max_tokens", "1024")
        # ... do inference ...

    terra.shutdown()
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import platform
import sys
from contextlib import contextmanager
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Generator, Optional, Union


# ── Error codes ──────────────────────────────────────────────────────────

class TerraError(IntEnum):
    OK = 0
    ALREADY_INITIALIZED = 1
    NOT_INITIALIZED = 2
    INVALID_CONFIG = 3
    OUT_OF_MEMORY = 4
    TRANSPORT_FAILED = 5
    SHUTTING_DOWN = 6


class TerraState(IntEnum):
    STOPPED = 0
    STARTING = 1
    RUNNING = 2
    SHUTTING_DOWN = 3


class ContentPolicy(IntEnum):
    NEVER = 0
    OPT_IN = 1
    ALWAYS = 2


class RedactionStrategy(IntEnum):
    DROP = 0
    LENGTH_ONLY = 1
    HMAC_SHA256 = 2


class StatusCode(IntEnum):
    UNSET = 0
    OK = 1
    ERROR = 2


# ── C structs ────────────────────────────────────────────────────────────

class CSpanContext(ctypes.Structure):
    """Matches terra_span_context_t in terra.h."""
    _fields_ = [
        ("trace_id_hi", ctypes.c_uint64),
        ("trace_id_lo", ctypes.c_uint64),
        ("span_id", ctypes.c_uint64),
    ]


class CVersion(ctypes.Structure):
    """Matches terra_version_t in terra.h."""
    _fields_ = [
        ("major", ctypes.c_uint32),
        ("minor", ctypes.c_uint32),
        ("patch", ctypes.c_uint32),
    ]


class CTransportVTable(ctypes.Structure):
    """Matches terra_transport_vtable_t in terra.h."""
    SEND_FN = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_uint8), ctypes.c_uint32, ctypes.c_void_p)
    FLUSH_FN = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
    SHUTDOWN_FN = ctypes.CFUNCTYPE(None, ctypes.c_void_p)

    _fields_ = [
        ("send_fn", SEND_FN),
        ("flush_fn", FLUSH_FN),
        ("shutdown_fn", SHUTDOWN_FN),
        ("context", ctypes.c_void_p),
    ]


class CSchedulerVTable(ctypes.Structure):
    """Matches terra_scheduler_vtable_t in terra.h."""
    _fields_ = [
        ("schedule_fn", ctypes.c_void_p),
        ("cancel_fn", ctypes.c_void_p),
        ("context", ctypes.c_void_p),
    ]


class CStorageVTable(ctypes.Structure):
    """Matches terra_storage_vtable_t in terra.h."""
    _fields_ = [
        ("write_fn", ctypes.c_void_p),
        ("read_fn", ctypes.c_void_p),
        ("discard_oldest_fn", ctypes.c_void_p),
        ("available_bytes_fn", ctypes.c_void_p),
        ("context", ctypes.c_void_p),
    ]


class CConfig(ctypes.Structure):
    """Matches terra_config_t in terra.h."""
    _fields_ = [
        ("max_spans", ctypes.c_uint32),
        ("max_attributes_per_span", ctypes.c_uint16),
        ("max_events_per_span", ctypes.c_uint16),
        ("max_event_attrs", ctypes.c_uint16),
        ("batch_size", ctypes.c_uint32),
        ("flush_interval_ms", ctypes.c_uint64),
        ("content_policy", ctypes.c_int),
        ("redaction_strategy", ctypes.c_int),
        ("hmac_key", ctypes.c_char_p),
        ("emit_legacy_sha256", ctypes.c_bool),
        ("service_name", ctypes.c_char_p),
        ("service_version", ctypes.c_char_p),
        ("otlp_endpoint", ctypes.c_char_p),
        ("clock_fn", ctypes.c_void_p),
        ("clock_ctx", ctypes.c_void_p),
        ("transport_vtable", CTransportVTable),
        ("scheduler_vtable", CSchedulerVTable),
        ("storage_vtable", CStorageVTable),
    ]


# ── Library loader ───────────────────────────────────────────────────────

def _find_libtera() -> str:
    """Locate libtera shared library using standard search paths."""
    # Check environment variable first
    env_path = os.environ.get("TERRA_LIB_PATH")
    if env_path and os.path.isfile(env_path):
        return env_path

    # Check common relative paths from this file
    this_dir = Path(__file__).parent
    candidates = [
        this_dir / ".." / "zig-core" / "zig-out" / "lib" / "libterra_shared.dylib",
        this_dir / ".." / "zig-core" / "zig-out" / "lib" / "libterra_shared.so",
        this_dir / ".." / "zig-core" / "zig-out" / "lib" / "terra_shared.dll",
        Path("/usr/local/lib/libterra_shared.so"),
        Path("/usr/local/lib/libterra_shared.dylib"),
    ]

    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_file():
            return str(resolved)

    # Try system library search
    found = ctypes.util.find_library("terra_shared")
    if found:
        return found

    raise FileNotFoundError(
        "Cannot find libterra_shared. Set TERRA_LIB_PATH environment variable, "
        "or build with: cd zig-core && zig build"
    )


def _load_lib(path: Optional[str] = None) -> ctypes.CDLL:
    """Load and configure the Terra C library."""
    lib_path = path or _find_libtera()
    lib = ctypes.CDLL(lib_path)

    # ── Lifecycle ─────────────────────────────────────────────────────
    lib.terra_init.argtypes = [ctypes.POINTER(CConfig)]
    lib.terra_init.restype = ctypes.c_void_p

    lib.terra_shutdown.argtypes = [ctypes.c_void_p]
    lib.terra_shutdown.restype = ctypes.c_int

    lib.terra_get_state.argtypes = [ctypes.c_void_p]
    lib.terra_get_state.restype = ctypes.c_uint8

    lib.terra_is_running.argtypes = [ctypes.c_void_p]
    lib.terra_is_running.restype = ctypes.c_bool

    # ── Configuration ─────────────────────────────────────────────────
    lib.terra_set_session_id.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.terra_set_session_id.restype = ctypes.c_int

    lib.terra_set_service_info.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.terra_set_service_info.restype = ctypes.c_int

    # ── Span creation ─────────────────────────────────────────────────
    for fn_name in [
        "terra_begin_inference_span_ctx",
        "terra_begin_embedding_span_ctx",
        "terra_begin_agent_span_ctx",
        "terra_begin_tool_span_ctx",
        "terra_begin_safety_span_ctx",
        "terra_begin_streaming_span_ctx",
    ]:
        fn = getattr(lib, fn_name)
        fn.argtypes = [ctypes.c_void_p, ctypes.POINTER(CSpanContext), ctypes.c_char_p, ctypes.c_bool]
        fn.restype = ctypes.c_void_p

    # ── Span mutation ─────────────────────────────────────────────────
    lib.terra_span_set_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.terra_span_set_string.restype = None

    lib.terra_span_set_int.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64]
    lib.terra_span_set_int.restype = None

    lib.terra_span_set_double.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_double]
    lib.terra_span_set_double.restype = None

    lib.terra_span_set_bool.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_bool]
    lib.terra_span_set_bool.restype = None

    lib.terra_span_set_status.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_char_p]
    lib.terra_span_set_status.restype = None

    lib.terra_span_end.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.terra_span_end.restype = None

    # ── Events ────────────────────────────────────────────────────────
    lib.terra_span_add_event.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.terra_span_add_event.restype = None

    lib.terra_span_add_event_ts.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint64]
    lib.terra_span_add_event_ts.restype = None

    # ── Error recording ───────────────────────────────────────────────
    lib.terra_span_record_error.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_bool]
    lib.terra_span_record_error.restype = None

    # ── Streaming ─────────────────────────────────────────────────────
    lib.terra_streaming_record_token.argtypes = [ctypes.c_void_p]
    lib.terra_streaming_record_token.restype = None

    lib.terra_streaming_record_first_token.argtypes = [ctypes.c_void_p]
    lib.terra_streaming_record_first_token.restype = None

    lib.terra_streaming_end.argtypes = [ctypes.c_void_p]
    lib.terra_streaming_end.restype = None

    # ── Context extraction ────────────────────────────────────────────
    lib.terra_span_context.argtypes = [ctypes.c_void_p]
    lib.terra_span_context.restype = CSpanContext

    # ── Diagnostics ───────────────────────────────────────────────────
    lib.terra_last_error.argtypes = []
    lib.terra_last_error.restype = ctypes.c_int

    lib.terra_last_error_message.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
    lib.terra_last_error_message.restype = ctypes.c_uint32

    lib.terra_spans_dropped.argtypes = [ctypes.c_void_p]
    lib.terra_spans_dropped.restype = ctypes.c_uint64

    lib.terra_transport_degraded.argtypes = [ctypes.c_void_p]
    lib.terra_transport_degraded.restype = ctypes.c_bool

    # ── Version ───────────────────────────────────────────────────────
    lib.terra_get_version.argtypes = []
    lib.terra_get_version.restype = CVersion

    # ── Metrics ───────────────────────────────────────────────────────
    lib.terra_record_inference_duration.argtypes = [ctypes.c_void_p, ctypes.c_double]
    lib.terra_record_inference_duration.restype = None

    lib.terra_record_token_count.argtypes = [ctypes.c_void_p, ctypes.c_int64, ctypes.c_int64]
    lib.terra_record_token_count.restype = None

    return lib


# ── Public API ───────────────────────────────────────────────────────────

@dataclass
class SpanContext:
    """Trace context for parent-child span propagation."""
    trace_id_hi: int = 0
    trace_id_lo: int = 0
    span_id: int = 0

    def _to_c(self) -> CSpanContext:
        ctx = CSpanContext()
        ctx.trace_id_hi = self.trace_id_hi
        ctx.trace_id_lo = self.trace_id_lo
        ctx.span_id = self.span_id
        return ctx

    @classmethod
    def _from_c(cls, c_ctx: CSpanContext) -> SpanContext:
        return cls(
            trace_id_hi=c_ctx.trace_id_hi,
            trace_id_lo=c_ctx.trace_id_lo,
            span_id=c_ctx.span_id,
        )

    @property
    def is_valid(self) -> bool:
        return not (self.trace_id_hi == 0 and self.trace_id_lo == 0 and self.span_id == 0)

    @property
    def trace_id_hex(self) -> str:
        return f"{self.trace_id_hi:016x}{self.trace_id_lo:016x}"

    @property
    def span_id_hex(self) -> str:
        return f"{self.span_id:016x}"


@dataclass
class TerraConfig:
    """Configuration for Terra SDK initialization."""
    service_name: str = "unknown"
    service_version: str = "0.0.0"
    otlp_endpoint: str = "http://localhost:4318"
    max_spans: int = 1024
    max_attributes_per_span: int = 64
    max_events_per_span: int = 8
    max_event_attrs: int = 4
    batch_size: int = 256
    flush_interval_ms: int = 5000
    content_policy: ContentPolicy = ContentPolicy.NEVER
    redaction_strategy: RedactionStrategy = RedactionStrategy.HMAC_SHA256
    hmac_key: Optional[str] = None
    emit_legacy_sha256: bool = False


class TerraSpan:
    """Wrapper around a Terra span handle. Use as a context manager or call end() manually."""

    def __init__(self, lib: ctypes.CDLL, inst_handle: ctypes.c_void_p, span_handle: ctypes.c_void_p) -> None:
        self._lib = lib
        self._inst = inst_handle
        self._handle = span_handle
        self._ended = False

    @property
    def handle(self) -> ctypes.c_void_p:
        return self._handle

    @property
    def is_valid(self) -> bool:
        return self._handle is not None and self._handle != 0

    @property
    def context(self) -> SpanContext:
        """Extract span context for propagation to child spans."""
        if not self.is_valid:
            return SpanContext()
        c_ctx = self._lib.terra_span_context(self._handle)
        return SpanContext._from_c(c_ctx)

    def set_string(self, key: str, value: str) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_set_string(self._handle, key.encode(), value.encode())

    def set_int(self, key: str, value: int) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_set_int(self._handle, key.encode(), value)

    def set_double(self, key: str, value: float) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_set_double(self._handle, key.encode(), value)

    def set_bool(self, key: str, value: bool) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_set_bool(self._handle, key.encode(), value)

    def set_status(self, code: StatusCode, description: str = "") -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_set_status(self._handle, code.value, description.encode())

    def add_event(self, name: str) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_add_event(self._handle, name.encode())

    def record_error(self, error_type: str, error_message: str, set_status: bool = True) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_span_record_error(
            self._handle, error_type.encode(), error_message.encode(), set_status
        )

    def end(self) -> None:
        if not self.is_valid or self._ended:
            return
        self._ended = True
        self._lib.terra_span_end(self._inst, self._handle)

    def __enter__(self) -> TerraSpan:
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        if exc_type is not None and not self._ended:
            self.record_error(
                exc_type.__name__ if exc_type else "Unknown",
                str(exc_val) if exc_val else "Unknown error",
                set_status=True,
            )
        self.end()

    def __del__(self) -> None:
        self.end()


class TerraStreamingSpan(TerraSpan):
    """Span wrapper with streaming-specific methods."""

    def record_first_token(self) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_streaming_record_first_token(self._handle)

    def record_token(self) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_streaming_record_token(self._handle)

    def finish_stream(self) -> None:
        if not self.is_valid or self._ended:
            return
        self._lib.terra_streaming_end(self._handle)
        self._ended = True


class Terra:
    """Main Terra SDK handle. Call init() to create, shutdown() to destroy."""

    def __init__(self, handle: ctypes.c_void_p, lib: ctypes.CDLL) -> None:
        self._handle = handle
        self._lib = lib

    @classmethod
    def init(
        cls,
        service_name: str = "unknown",
        service_version: str = "0.0.0",
        otlp_endpoint: str = "http://localhost:4318",
        config: Optional[TerraConfig] = None,
        lib_path: Optional[str] = None,
    ) -> Terra:
        """Initialize Terra SDK. Pass config for full control, or use keyword args for common settings."""
        lib = _load_lib(lib_path)

        cfg = config or TerraConfig(
            service_name=service_name,
            service_version=service_version,
            otlp_endpoint=otlp_endpoint,
        )

        # NOTE: terra_init() accepts NULL for defaults. Post-init configuration
        # is limited to service_name/service_version via terra_set_service_info().
        # Other TerraConfig fields (otlp_endpoint, content_policy, max_spans, etc.)
        # are documented for future C API expansion but currently use Zig defaults.
        # See terra.h for the complete C configuration struct.
        handle = lib.terra_init(None)
        if not handle:
            err = lib.terra_last_error()
            buf = ctypes.create_string_buffer(256)
            lib.terra_last_error_message(buf, 256)
            raise RuntimeError(f"terra_init failed (error={err}): {buf.value.decode()}")

        inst = cls(handle, lib)

        # Apply service info — the only config fields supported post-init via C API
        inst.set_service_info(cfg.service_name, cfg.service_version)

        return inst

    @property
    def is_running(self) -> bool:
        if not self._handle:
            return False
        return bool(self._lib.terra_is_running(self._handle))

    @property
    def state(self) -> TerraState:
        if not self._handle:
            return TerraState.STOPPED
        return TerraState(self._lib.terra_get_state(self._handle))

    @property
    def spans_dropped(self) -> int:
        if not self._handle:
            return 0
        return self._lib.terra_spans_dropped(self._handle)

    @property
    def transport_degraded(self) -> bool:
        if not self._handle:
            return False
        return bool(self._lib.terra_transport_degraded(self._handle))

    @staticmethod
    def version(lib_path: Optional[str] = None) -> str:
        """Get Terra library version string."""
        lib = _load_lib(lib_path)
        v = lib.terra_get_version()
        return f"{v.major}.{v.minor}.{v.patch}"

    def set_session_id(self, session_id: str) -> None:
        self._lib.terra_set_session_id(self._handle, session_id.encode())

    def set_service_info(self, name: str, version: str) -> None:
        self._lib.terra_set_service_info(self._handle, name.encode(), version.encode())

    def record_inference_duration(self, duration_ms: float) -> None:
        self._lib.terra_record_inference_duration(self._handle, duration_ms)

    def record_token_count(self, input_tokens: int, output_tokens: int) -> None:
        self._lib.terra_record_token_count(self._handle, input_tokens, output_tokens)

    # ── Span creation ────────────────────────────────────────────────

    def begin_inference_span(
        self,
        model: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_inference_span_ctx(
            self._handle, parent_c, model.encode(), include_content
        )
        return TerraSpan(self._lib, self._handle, h)

    def begin_embedding_span(
        self,
        model: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_embedding_span_ctx(
            self._handle, parent_c, model.encode(), include_content
        )
        return TerraSpan(self._lib, self._handle, h)

    def begin_agent_span(
        self,
        agent_name: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_agent_span_ctx(
            self._handle, parent_c, agent_name.encode(), include_content
        )
        return TerraSpan(self._lib, self._handle, h)

    def begin_tool_span(
        self,
        tool_name: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_tool_span_ctx(
            self._handle, parent_c, tool_name.encode(), include_content
        )
        return TerraSpan(self._lib, self._handle, h)

    def begin_safety_span(
        self,
        check_name: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_safety_span_ctx(
            self._handle, parent_c, check_name.encode(), include_content
        )
        return TerraSpan(self._lib, self._handle, h)

    def begin_streaming_span(
        self,
        model: str,
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> TerraStreamingSpan:
        parent_c = ctypes.byref(parent._to_c()) if parent else None
        h = self._lib.terra_begin_streaming_span_ctx(
            self._handle, parent_c, model.encode(), include_content
        )
        return TerraStreamingSpan(self._lib, self._handle, h)

    # ── Convenience context manager ──────────────────────────────────

    @contextmanager
    def span(
        self,
        span_type: str = "inference",
        model: str = "",
        name: str = "",
        parent: Optional[SpanContext] = None,
        include_content: bool = False,
    ) -> Generator[Union[TerraSpan, TerraStreamingSpan], None, None]:
        """Context manager for creating spans.

        Args:
            span_type: One of "inference", "embedding", "agent", "tool", "safety", "streaming".
            model: Model name (for inference/embedding/streaming).
            name: Name (for agent/tool/safety).
            parent: Optional parent span context.
            include_content: Whether to include content in telemetry.
        """
        creators = {
            "inference": lambda: self.begin_inference_span(model, parent, include_content),
            "embedding": lambda: self.begin_embedding_span(model, parent, include_content),
            "agent": lambda: self.begin_agent_span(name, parent, include_content),
            "tool": lambda: self.begin_tool_span(name, parent, include_content),
            "safety": lambda: self.begin_safety_span(name, parent, include_content),
            "streaming": lambda: self.begin_streaming_span(model, parent, include_content),
        }

        creator = creators.get(span_type)
        if creator is None:
            raise ValueError(f"Unknown span type: {span_type}. Must be one of {list(creators.keys())}")

        s = creator()
        try:
            yield s
        except Exception:
            if not s._ended:
                import traceback
                s.record_error(
                    sys.exc_info()[0].__name__ if sys.exc_info()[0] else "Unknown",
                    str(sys.exc_info()[1]) if sys.exc_info()[1] else "Unknown error",
                    set_status=True,
                )
            raise
        finally:
            s.end()

    # ── Shutdown ─────────────────────────────────────────────────────

    def shutdown(self) -> None:
        """Shut down the Terra instance and release all resources."""
        if self._handle:
            self._lib.terra_shutdown(self._handle)
            self._handle = None

    def __del__(self) -> None:
        self.shutdown()

    def __enter__(self) -> Terra:
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.shutdown()
