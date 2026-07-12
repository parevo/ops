//! SSH remote connection manager and session runner.
//!
//! Provides the engine to open secure SSH connections using the native `openssh` binary,
//! managing authentication keys, known hosts, agent sockets, and parallel command executions.

#![deny(missing_docs)]

use openssh::SessionBuilder;
use parevo_common::{Error, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Configuration details required to authenticate and open an SSH connection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SshCredentials {
    /// Server IP or domain.
    pub host: String,
    /// Destination SSH Port.
    pub port: u16,
    /// SSH username to log in with.
    pub username: String,
    /// Optional absolute path to SSH private key file.
    pub private_key_path: Option<String>,
    /// Flags if this connection should run as a local mock for unit-testing.
    pub mock: bool,
}

/// Managed SSH sessions provider.
pub struct SshManager {
    timeout: Duration,
}

impl Default for SshManager {
    fn default() -> Self {
        Self::new(Duration::from_secs(10))
    }
}

impl SshManager {
    /// Creates a new SSH connection manager with a given timeout.
    pub fn new(timeout: Duration) -> Self {
        Self { timeout }
    }

    /// Connects to a remote host and executes a shell command.
    pub async fn execute_command(&self, creds: &SshCredentials, cmd: &str) -> Result<String> {
        if creds.mock {
            tracing::info!("Mocking SSH command execution on {}: {}", creds.host, cmd);
            return Ok(format!("Mock output of '{}' on {}", cmd, creds.host));
        }

        tracing::info!("Opening SSH session to {}@{}", creds.username, creds.host);

        let mut builder = SessionBuilder::default();
        builder.port(creds.port);
        builder.connect_timeout(self.timeout);
        builder.known_hosts_check(openssh::KnownHosts::Accept);

        if let Some(ref key) = creds.private_key_path {
            let path = std::path::Path::new(key);
            if !path.exists() {
                return Err(Error::Ssh {
                    host: creds.host.clone(),
                    message: format!(
                        "Private key file not found at path: '{}'. Please use the 'Browse File' button to select it.",
                        key
                    ),
                });
            }

            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if let Ok(metadata) = std::fs::metadata(key) {
                    let mut perms = metadata.permissions();
                    if perms.mode() & 0o077 != 0 {
                        perms.set_mode(0o600);
                        if let Err(e) = std::fs::set_permissions(key, perms) {
                            tracing::warn!("Failed to auto-set permissions on SSH key file: {}", e);
                        } else {
                            tracing::info!("Automatically set secure permissions (0600) on private key: {}", key);
                        }
                    }
                }
            }
            builder.keyfile(key);
        }

        // Connect to target host
        let session = builder
            .connect(format!("{}@{}", creds.username, creds.host))
            .await
            .map_err(|e| Error::Ssh {
                host: creds.host.clone(),
                message: format!("Connection failed: {}", e),
            })?;

        tracing::debug!("Executing SSH command: {}", cmd);

        let output = session
            .command("sh")
            .arg("-c")
            .arg(cmd)
            .output()
            .await
            .map_err(|e| Error::Ssh {
                host: creds.host.clone(),
                message: format!("Command execution failed: {}", e),
            })?;

        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

        if output.status.success() {
            Ok(stdout)
        } else {
            Err(Error::Ssh {
                host: creds.host.clone(),
                message: if stderr.is_empty() {
                    format!(
                        "Command exited with status code: {:?}",
                        output.status.code()
                    )
                } else {
                    stderr
                },
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_ssh_execute_mock() {
        let manager = SshManager::default();
        let creds = SshCredentials {
            host: "10.0.0.5".to_string(),
            port: 22,
            username: "root".to_string(),
            private_key_path: None,
            mock: true,
        };

        let result = manager.execute_command(&creds, "uptime").await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "Mock output of 'uptime' on 10.0.0.5");
    }
}
