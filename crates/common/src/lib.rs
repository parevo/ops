//! Common utility functions, error types, and definitions used across Parevo Ops crates.
//!
//! This crate contains general-purpose utilities, shared data models, and the system-wide
//! error types ensuring that the codebase returns proper `Result`s instead of using `unwrap()`.

#![deny(missing_docs)]

use std::fmt;

/// The primary error type for Parevo Ops.
/// Defines all error variants that can be produced across the system's modules.
#[derive(thiserror::Error, Debug)]
pub enum Error {
    /// Database errors, typically wrapping SQLx errors.
    #[error("Database error: {0}")]
    Database(String),

    /// SSH and remote host errors.
    #[error("SSH execution error on host {host}: {message}")]
    Ssh {
        /// The hostname/IP that failed.
        host: String,
        /// The descriptive error message.
        message: String,
    },

    /// Docker Engine API errors.
    #[error("Docker API error: {0}")]
    Docker(String),

    /// File operations errors.
    #[error("File system error: {0}")]
    FileSystem(String),

    /// OS level system execution errors (systemctl, commands, etc.).
    #[error("System command error: {0}")]
    System(String),

    /// Configuration errors (loading, validation, writing).
    #[error("Configuration error: {0}")]
    Config(String),

    /// Internal system or logic errors.
    #[error("Internal system error: {0}")]
    Internal(String),

    /// Network related issues.
    #[error("Network error: {0}")]
    Network(String),

    /// AI Assistant and prompt engine errors.
    #[error("AI engine error: {0}")]
    Ai(String),

    /// Plugin lifecycle or loading errors.
    #[error("Plugin error: {0}")]
    Plugin(String),

    /// Serialization/Deserialization issues.
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

/// A specialized Result type for Parevo Ops operations.
pub type Result<T> = std::result::Result<T, Error>;

/// Extension trait for `Option` to provide a clean way to convert `None` into
/// a proper system error instead of using `unwrap()`.
pub trait OptionExt<T> {
    /// Unwraps the option or returns a custom `Error::Internal` with the given message.
    fn or_internal_err<S: fmt::Display>(self, msg: S) -> Result<T>;
}

impl<T> OptionExt<T> for Option<T> {
    fn or_internal_err<S: fmt::Display>(self, msg: S) -> Result<T> {
        self.ok_or_else(|| Error::Internal(msg.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_option_extension() {
        let some_val = Some(42);
        assert_eq!(some_val.or_internal_err("should not fail").unwrap(), 42);

        let none_val: Option<i32> = None;
        let res = none_val.or_internal_err("expected value");
        assert!(res.is_err());
        if let Err(Error::Internal(msg)) = res {
            assert_eq!(msg, "expected value");
        } else {
            panic!("Expected internal error variant");
        }
    }
}
