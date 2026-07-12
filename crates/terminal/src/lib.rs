//! PTY Terminal session runner.
//!
//! Spawns native bash/zsh shell processes wrapped inside pseudoterminals (PTY)
//! using `portable-pty`, allowing stream mapping.

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use serde::{Deserialize, Serialize};

/// High-level details of a Terminal Session.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SessionInfo {
    /// Unique identifier for the terminal session.
    pub session_id: String,
    /// Type of shell (e.g. bash, zsh, ssh).
    pub shell: String,
}

/// Terminal and PTY manager.
pub struct TerminalManager {
    mock: bool,
}

impl Default for TerminalManager {
    fn default() -> Self {
        Self::new(true) // Default mock to true for CI/test headless environments
    }
}

impl TerminalManager {
    /// Creates a new terminal manager.
    pub fn new(mock: bool) -> Self {
        Self { mock }
    }

    /// Spawns a new terminal session.
    pub async fn spawn_session(&self, shell: &str) -> Result<SessionInfo> {
        if self.mock {
            tracing::info!("Mock spawn shell session: {}", shell);
            return Ok(SessionInfo {
                session_id: "mock-session-id".to_string(),
                shell: shell.to_string(),
            });
        }

        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows: 24,
                cols: 80,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| Error::System(format!("Failed to open PTY: {}", e)))?;

        let cmd = CommandBuilder::new(shell);
        let _child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|e| Error::System(format!("Failed to spawn shell: {}", e)))?;

        Ok(SessionInfo {
            session_id: uuid::Uuid::new_v4().to_string(),
            shell: shell.to_string(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_spawn_mock_session() {
        let manager = TerminalManager::new(true);
        let session = manager.spawn_session("bash").await;
        assert!(session.is_ok());
        let session = session.unwrap();
        assert_eq!(session.shell, "bash");
        assert_eq!(session.session_id, "mock-session-id");
    }
}
