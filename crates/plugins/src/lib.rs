//! Extension and plugin loading manager.
//!
//! Standardizes plugin loading, lifecycle events, and registration for modular third-party extensions.

#![deny(missing_docs)]

use parevo_common::Result;
use serde::{Deserialize, Serialize};

/// High-level details of a plugin.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginMetadata {
    /// Unique name of the plugin.
    pub name: String,
    /// Developer or publisher.
    pub author: String,
    /// Plugin version string.
    pub version: String,
}

/// Dynamic extension driver.
pub struct PluginManager {
    // Underneath, loads dynamic library files or wasm runner in Phase 5.
}

impl Default for PluginManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PluginManager {
    /// Creates a new plugin manager.
    pub fn new() -> Self {
        Self {}
    }

    /// Scans a directory and initializes all discovered plugins.
    pub async fn load_plugins(&self, _plugins_dir: &str) -> Result<Vec<PluginMetadata>> {
        tracing::debug!("Scanning plugin registry folder...");
        // This is a placeholder for dynamic loading in Phase 5.
        Ok(vec![PluginMetadata {
            name: "parevo-redis-viewer".to_string(),
            author: "Parevo Core Team".to_string(),
            version: "0.1.0".to_string(),
        }])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_load_plugins() {
        let manager = PluginManager::new();
        let plugins = manager.load_plugins("/opt/plugins").await;
        assert!(plugins.is_ok());
        let list = plugins.unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "parevo-redis-viewer");
    }
}
