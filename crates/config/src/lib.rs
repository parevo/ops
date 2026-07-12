//! Application configurations manager.
//!
//! Provides the core definitions, serialization, loading, and saving functionality
//! for the workspace configurations (TOML).

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::fs;

/// Main application-wide configuration struct.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AppConfig {
    /// General app setup.
    pub app: GeneralConfig,
    /// Persistent store paths.
    pub database: DatabaseConfig,
    /// Default SSH configurations.
    pub ssh: SshDefaults,
    /// AI Assistant connection parameters.
    pub ai: AiConfig,
}

/// General environment preferences.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GeneralConfig {
    /// Logging visibility filter (e.g. debug, info, warn, error).
    pub log_level: String,
    /// Toggles local UI dev mode tools.
    pub dev_mode: bool,
}

/// Database storage locations.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DatabaseConfig {
    /// Absolute or relative path to the SQLite local database file.
    pub path: String,
}

/// Default options for remote SSH commands.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SshDefaults {
    /// Default connection port for SSH hosts (usually 22).
    pub default_port: u16,
    /// Default username if none is specified.
    pub default_username: String,
    /// Default directory where SSH private keys are stored.
    pub keys_directory: String,
    /// Connection timeout in seconds.
    pub timeout_seconds: u64,
}

/// AI Assistant credentials and endpoint configuration.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AiConfig {
    /// The API provider (e.g. "openai", "localai", "ollama").
    pub provider: String,
    /// Base URL endpoint for compatible chat completions APIs.
    pub base_url: String,
    /// Secret API Key token.
    pub api_key: String,
    /// Targeted LLM model identifier.
    pub model: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            app: GeneralConfig {
                log_level: "info".to_string(),
                dev_mode: false,
            },
            database: DatabaseConfig {
                path: "parevo-ops.db".to_string(),
            },
            ssh: SshDefaults {
                default_port: 22,
                default_username: "root".to_string(),
                keys_directory: "~/.ssh".to_string(),
                timeout_seconds: 10,
            },
            ai: AiConfig {
                provider: "openai".to_string(),
                base_url: "https://api.openai.com/v1".to_string(),
                api_key: "".to_string(),
                model: "gpt-4o".to_string(),
            },
        }
    }
}

impl AppConfig {
    /// Deserializes a TOML file from disk into the AppConfig struct.
    pub async fn load_from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)
            .await
            .map_err(|e| Error::Config(format!("Failed to read config file: {}", e)))?;
        let config: AppConfig = toml::from_str(&content)
            .map_err(|e| Error::Config(format!("Failed to parse config TOML: {}", e)))?;
        Ok(config)
    }

    /// Serializes the AppConfig struct into TOML and writes it to disk.
    pub async fn save_to_file<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)
            .map_err(|e| Error::Config(format!("Failed to serialize config: {}", e)))?;

        if let Some(parent) = path.as_ref().parent() {
            fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Config(format!("Failed to create config folder: {}", e)))?;
        }

        fs::write(path, content)
            .await
            .map_err(|e| Error::Config(format!("Failed to write config file: {}", e)))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_config_serde() {
        let temp_dir = std::env::temp_dir();
        let path = temp_dir.join("parevo-config-test.toml");

        let mut config = AppConfig::default();
        config.ai.api_key = "secret-key-123".to_string();

        assert!(config.save_to_file(&path).await.is_ok());

        let loaded = AppConfig::load_from_file(&path).await;
        assert!(loaded.is_ok());
        let loaded = loaded.unwrap();
        assert_eq!(loaded.ai.api_key, "secret-key-123");
        assert_eq!(loaded.ssh.default_port, 22);

        let _ = std::fs::remove_file(path);
    }
}
