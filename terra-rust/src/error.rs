//! Error types for the Terra Rust bindings.

use crate::ffi;
use std::fmt;

/// All possible errors returned by Terra operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TerraError {
    /// A Terra instance is already initialized.
    AlreadyInitialized,
    /// No Terra instance is currently running.
    NotInitialized,
    /// The configuration provided was invalid.
    InvalidConfig,
    /// Memory allocation failed inside the Zig core.
    OutOfMemory,
    /// The transport layer failed to send telemetry data.
    TransportFailed,
    /// The instance is currently shutting down.
    ShuttingDown,
    /// An unknown error code was returned.
    Unknown(i32),
}

impl TerraError {
    /// Convert a raw C error code into a `TerraError`.
    /// Returns `None` for `TERRA_OK`.
    pub(crate) fn from_code(code: i32) -> Option<Self> {
        match code {
            ffi::TERRA_OK => None,
            ffi::TERRA_ERR_ALREADY_INITIALIZED => Some(Self::AlreadyInitialized),
            ffi::TERRA_ERR_NOT_INITIALIZED => Some(Self::NotInitialized),
            ffi::TERRA_ERR_INVALID_CONFIG => Some(Self::InvalidConfig),
            ffi::TERRA_ERR_OUT_OF_MEMORY => Some(Self::OutOfMemory),
            ffi::TERRA_ERR_TRANSPORT_FAILED => Some(Self::TransportFailed),
            ffi::TERRA_ERR_SHUTTING_DOWN => Some(Self::ShuttingDown),
            other => Some(Self::Unknown(other)),
        }
    }
}

impl fmt::Display for TerraError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AlreadyInitialized => write!(f, "Terra is already initialized"),
            Self::NotInitialized => write!(f, "Terra is not initialized"),
            Self::InvalidConfig => write!(f, "invalid Terra configuration"),
            Self::OutOfMemory => write!(f, "out of memory"),
            Self::TransportFailed => write!(f, "transport layer failed"),
            Self::ShuttingDown => write!(f, "Terra is shutting down"),
            Self::Unknown(code) => write!(f, "unknown Terra error (code {})", code),
        }
    }
}

impl std::error::Error for TerraError {}

/// Lifecycle state of a Terra instance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LifecycleState {
    Stopped,
    Starting,
    Running,
    ShuttingDown,
}

impl LifecycleState {
    pub(crate) fn from_raw(raw: u8) -> Self {
        match raw {
            ffi::TERRA_STATE_STOPPED => Self::Stopped,
            ffi::TERRA_STATE_STARTING => Self::Starting,
            ffi::TERRA_STATE_RUNNING => Self::Running,
            ffi::TERRA_STATE_SHUTTING_DOWN => Self::ShuttingDown,
            _ => Self::Stopped,
        }
    }
}

impl fmt::Display for LifecycleState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Stopped => write!(f, "stopped"),
            Self::Starting => write!(f, "starting"),
            Self::Running => write!(f, "running"),
            Self::ShuttingDown => write!(f, "shutting down"),
        }
    }
}

/// Content capture policy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ContentPolicy {
    /// Never capture prompt/response content.
    Never,
    /// Capture only when explicitly opted in per-span.
    OptIn,
    /// Always capture content.
    Always,
}

impl ContentPolicy {
    pub(crate) fn to_raw(self) -> i32 {
        match self {
            Self::Never => ffi::TERRA_CONTENT_NEVER,
            Self::OptIn => ffi::TERRA_CONTENT_OPT_IN,
            Self::Always => ffi::TERRA_CONTENT_ALWAYS,
        }
    }
}

/// Redaction strategy for captured content.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RedactionStrategy {
    /// Drop content entirely.
    Drop,
    /// Record only the length of the content.
    LengthOnly,
    /// Hash content with HMAC-SHA256.
    HmacSha256,
}

impl RedactionStrategy {
    pub(crate) fn to_raw(self) -> i32 {
        match self {
            Self::Drop => ffi::TERRA_REDACT_DROP,
            Self::LengthOnly => ffi::TERRA_REDACT_LENGTH_ONLY,
            Self::HmacSha256 => ffi::TERRA_REDACT_HMAC_SHA256,
        }
    }
}

/// Span status code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StatusCode {
    Unset,
    Ok,
    Error,
}

impl StatusCode {
    pub(crate) fn to_raw(self) -> u8 {
        match self {
            Self::Unset => ffi::TERRA_STATUS_UNSET,
            Self::Ok => ffi::TERRA_STATUS_OK,
            Self::Error => ffi::TERRA_STATUS_ERROR,
        }
    }
}
