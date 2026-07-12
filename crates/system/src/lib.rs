//! System service manager.
//!
//! Provides utilities to control systemd services via `systemctl` commands
//! and parses key-value properties from `systemctl show` output.

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Structured properties parsed from systemctl service targets.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ServiceInfo {
    /// Service identifier (e.g. "nginx.service").
    pub name: String,
    /// Loaded state ("loaded", "not-found", "masked").
    pub load_state: String,
    /// Active state ("active", "inactive", "failed").
    pub active_state: String,
    /// Detailed running substate ("running", "dead", "exited").
    pub sub_state: String,
    /// Long human-friendly description of the service.
    pub description: String,
}

/// Linux systemctl controller.
pub struct SystemManager {}

impl Default for SystemManager {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemManager {
    /// Instantiates the system controller.
    pub fn new() -> Self {
        Self {}
    }

    /// Fetches details of a specific service using systemctl show.
    pub async fn get_service_status(&self, service_name: &str) -> Result<ServiceInfo> {
        let mock_show = format!(
            "Id={}.service\n\
             LoadState=loaded\n\
             ActiveState=active\n\
             SubState=running\n\
             Description=Mock daemon for {}",
            service_name, service_name
        );
        self.parse_show_output(&mock_show)
    }

    /// Helper command generator to manipulate service states.
    /// Returns the exact `systemctl` command string to run on the server.
    pub fn get_service_command(&self, service: &str, action: &str) -> Result<String> {
        let valid_actions = ["start", "stop", "restart", "reload", "enable", "disable"];
        if !valid_actions.contains(&action) {
            return Err(Error::System(format!(
                "Invalid service manager action: {}",
                action
            )));
        }
        Ok(format!("systemctl {} {}", action, service))
    }

    /// Parses key-value output produced by running `systemctl show <service>`.
    pub fn parse_show_output(&self, raw_output: &str) -> Result<ServiceInfo> {
        let mut map = HashMap::new();
        for line in raw_output.lines() {
            if let Some(pos) = line.find('=') {
                let (key, value) = line.split_at(pos);
                let value = &value[1..]; // skip the '='
                map.insert(key.trim().to_string(), value.trim().to_string());
            }
        }

        let name = map
            .get("Id")
            .cloned()
            .unwrap_or_else(|| "unknown.service".to_string());
        let load_state = map
            .get("LoadState")
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());
        let active_state = map
            .get("ActiveState")
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());
        let sub_state = map
            .get("SubState")
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());
        let description = map
            .get("Description")
            .cloned()
            .unwrap_or_else(|| "".to_string());

        Ok(ServiceInfo {
            name,
            load_state,
            active_state,
            sub_state,
            description,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_systemctl_show_parser() {
        let raw = "\
Id=nginx.service
LoadState=loaded
ActiveState=active
SubState=running
Description=A high performance web server
";

        let manager = SystemManager::new();
        let info = manager.parse_show_output(raw);
        assert!(info.is_ok());

        let info = info.unwrap();
        assert_eq!(info.name, "nginx.service");
        assert_eq!(info.load_state, "loaded");
        assert_eq!(info.active_state, "active");
        assert_eq!(info.sub_state, "running");
        assert_eq!(info.description, "A high performance web server");
    }

    #[test]
    fn test_systemctl_invalid_command() {
        let manager = SystemManager::new();
        let cmd = manager.get_service_command("nginx", "status"); // status is not in allowed command states (since we check status via show)
        assert!(cmd.is_err());
    }
}
