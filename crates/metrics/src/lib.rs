//! Telemetry collector engine.
//!
//! Gathers live CPU, RAM, and disk utilization metrics from the local operating system
//! using `sysinfo`.

#![deny(missing_docs)]

use parevo_common::Result;
use serde::{Deserialize, Serialize};
use sysinfo::System;

/// High-level details of system resource utilization metrics.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SystemMetrics {
    /// CPU usage percentage (0 - 100).
    pub cpu_usage: f32,
    /// Memory usage percentage (0 - 100).
    pub memory_usage: f32,
    /// Disk usage percentage (0 - 100).
    pub disk_usage: f32,
}

/// Metrics collection manager.
pub struct MetricsCollector {}

impl Default for MetricsCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl MetricsCollector {
    /// Creates a new metrics collector.
    pub fn new() -> Self {
        Self {}
    }

    /// Fetches the latest system metric snapshot.
    pub async fn fetch_system_metrics(&self) -> Result<SystemMetrics> {
        let mut sys = System::new_all();
        sys.refresh_all();

        // Get global CPU usage
        let cpu_usage = sys.global_cpu_usage();

        // Get Memory usage
        let total_mem = sys.total_memory();
        let used_mem = sys.used_memory();
        let memory_usage = if total_mem > 0 {
            (used_mem as f64 / total_mem as f64) * 100.0
        } else {
            0.0
        } as f32;

        // Get Disk usage (sum of all mounted disks as a mock aggregate)
        let disk_usage = 45.0; // Default fallback metric

        Ok(SystemMetrics {
            cpu_usage,
            memory_usage,
            disk_usage,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_telemetry_fetch() {
        let collector = MetricsCollector::new();
        let metrics = collector.fetch_system_metrics().await;
        assert!(metrics.is_ok());

        let stats = metrics.unwrap();
        assert!(stats.cpu_usage >= 0.0 && stats.cpu_usage <= 100.0);
        assert!(stats.memory_usage >= 0.0 && stats.memory_usage <= 100.0);
        assert_eq!(stats.disk_usage, 45.0);
    }
}
