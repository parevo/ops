//! Historical log aggregator and streaming parser.
//!
//! Provides structures to log execution records, filters log streams with regex queries,
//! and forwards real-time messages to the global `EventBus`.

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use parevo_events::{Event, EventPayload, SharedEventBus};
use serde::{Deserialize, Serialize};

/// High-level details of a log message line.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LogMessage {
    /// Source container, service, or SSH target.
    pub source: String,
    /// Logging level (e.g. "INFO", "WARN", "ERROR").
    pub level: String,
    /// Message string line.
    pub message: String,
    /// Canonical ISO-8601 timestamp string.
    pub timestamp: String,
}

/// Log collection service.
pub struct LogManager {
    event_bus: Option<SharedEventBus>,
}

impl LogManager {
    /// Instantiates the logs engine.
    pub fn new(event_bus: Option<SharedEventBus>) -> Self {
        Self { event_bus }
    }

    /// Appends/receives a live log line, streaming it immediately to the EventBus.
    pub async fn inject_log(&self, msg: LogMessage) -> Result<()> {
        if let Some(ref bus) = self.event_bus {
            let event = Event::new(EventPayload::LogReceived {
                source: msg.source.clone(),
                content: format!("[{}] {} - {}", msg.level, msg.timestamp, msg.message),
            });
            bus.publish(event)?;
        }
        Ok(())
    }

    /// Filters a list of logs using a substring match query.
    pub fn filter_logs(&self, logs: &[LogMessage], query: &str) -> Vec<LogMessage> {
        if query.is_empty() {
            return logs.to_vec();
        }
        logs.iter()
            .filter(|log| log.message.contains(query) || log.source.contains(query))
            .cloned()
            .collect()
    }

    /// Fetches historical mock logs.
    pub async fn fetch_logs(&self, source: &str, limit: usize) -> Result<Vec<LogMessage>> {
        if source.is_empty() {
            return Err(Error::FileSystem("Log source cannot be empty".to_string()));
        }

        let mut list = Vec::new();
        for i in 0..limit {
            list.push(LogMessage {
                source: source.to_string(),
                level: if i % 5 == 0 {
                    "ERROR".to_string()
                } else if i % 3 == 0 {
                    "WARN".to_string()
                } else {
                    "INFO".to_string()
                },
                message: format!("Log line entry message index: {}", i),
                timestamp: chrono::Utc::now().to_rfc3339(),
            });
        }
        Ok(list)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[tokio::test]
    async fn test_log_manager_pub_sub() {
        let bus = Arc::new(parevo_events::EventBus::new());
        let mut rx = bus.subscribe();

        let manager = LogManager::new(Some(bus.clone()));

        let msg = LogMessage {
            source: "nginx-proxy".to_string(),
            level: "INFO".to_string(),
            message: "HTTP 200 OK".to_string(),
            timestamp: "2026-07-12T19:31:00Z".to_string(),
        };

        assert!(manager.inject_log(msg).await.is_ok());

        let event = rx.recv().await.unwrap();
        if let EventPayload::LogReceived { source, content } = event.payload {
            assert_eq!(source, "nginx-proxy");
            assert!(content.contains("HTTP 200 OK"));
        } else {
            panic!("Expected LogReceived payload");
        }
    }

    #[test]
    fn test_log_filtering() {
        let manager = LogManager::new(None);
        let logs = vec![
            LogMessage {
                source: "app".to_string(),
                level: "INFO".to_string(),
                message: "started server".to_string(),
                timestamp: "2026".to_string(),
            },
            LogMessage {
                source: "db".to_string(),
                level: "INFO".to_string(),
                message: "connected to sqlite".to_string(),
                timestamp: "2026".to_string(),
            },
        ];

        let filtered = manager.filter_logs(&logs, "sqlite");
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].source, "db");
    }
}
