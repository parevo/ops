//! In-memory thread-safe event bus and standard telemetry payload definitions.
//!
//! Allows modules to publish messages asynchronously and other domains (like the
//! logs engine or Tauri notifications panel) to subscribe to them.

#![deny(missing_docs)]

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::broadcast;
use uuid::Uuid;

/// Unique identifier for messages/events.
pub type EventId = Uuid;

/// Structured payloads representing different system events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventPayload {
    /// Remote host SSH status change.
    ServerStatusChanged {
        /// Unique server identifier.
        server_id: String,
        /// Hostname or IP.
        host: String,
        /// Connection status ("connected", "disconnected", "error").
        status: String,
    },
    /// Telemetry metrics collected from a server.
    SystemTelemetry {
        /// Hostname or IP.
        host: String,
        /// CPU usage percentage.
        cpu_usage: f32,
        /// Memory usage percentage.
        memory_usage: f32,
        /// Disk space usage percentage.
        disk_usage: f32,
    },
    /// Log message emitted by a service or container.
    LogReceived {
        /// Source identifier (container name, systemd unit name, ssh stream).
        source: String,
        /// Raw message line.
        content: String,
    },
    /// Alert triggers (low disk, high CPU, container restart loop, certificate expiration).
    SystemAlert {
        /// Severity tier ("info", "warning", "critical").
        severity: String,
        /// Brief summary of what triggered the alert.
        message: String,
        /// Detailed logs or contextual information.
        details: String,
    },
    /// Audit log of a user action.
    AuditLogged {
        /// Executing actor (e.g. "user", "ai-assistant").
        actor: String,
        /// Action descriptor (e.g. "container_stop").
        action: String,
        /// Targeted resource (e.g. server ID, container ID).
        target: String,
    },
}

/// System-wide event packet with context metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Unique event identifier.
    pub id: EventId,
    /// Generation date/time in UTC.
    pub timestamp: DateTime<Utc>,
    /// Underlying event data.
    pub payload: EventPayload,
}

impl Event {
    /// Instantiates a packet with the current timestamp and a random UUID.
    pub fn new(payload: EventPayload) -> Self {
        Self {
            id: Uuid::new_v4(),
            timestamp: Utc::now(),
            payload,
        }
    }
}

/// System-wide central Event Bus.
/// Supports a single publisher broadcast channel routing packets to multiple receivers.
pub struct EventBus {
    sender: broadcast::Sender<Event>,
}

impl Default for EventBus {
    fn default() -> Self {
        let (sender, _) = broadcast::channel(2048);
        Self { sender }
    }
}

impl EventBus {
    /// Allocates a new channel bus.
    pub fn new() -> Self {
        Self::default()
    }

    /// Dispatches an event onto the channel.
    /// Returns the count of active subscribers reading the channel.
    pub fn publish(&self, event: Event) -> Result<usize, parevo_common::Error> {
        self.sender.send(event).map_err(|e| {
            parevo_common::Error::Internal(format!("Failed to broadcast event: {}", e))
        })
    }

    /// Subscribes to the bus, returning a receiver interface.
    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.sender.subscribe()
    }
}

/// Shared reference thread-safe event bus type.
pub type SharedEventBus = Arc<EventBus>;

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_broadcast_event_bus() {
        let bus = EventBus::new();
        let mut receiver1 = bus.subscribe();
        let mut receiver2 = bus.subscribe();

        let event = Event::new(EventPayload::SystemAlert {
            severity: "critical".to_string(),
            message: "CPU usage at 99%".to_string(),
            details: "nginx process utilizing 100% core".to_string(),
        });

        let publish_count = bus.publish(event.clone()).unwrap();
        assert_eq!(publish_count, 2);

        let rx1 = receiver1.recv().await.unwrap();
        let rx2 = receiver2.recv().await.unwrap();

        assert_eq!(rx1.id, event.id);
        assert_eq!(rx2.id, event.id);

        if let EventPayload::SystemAlert {
            severity, message, ..
        } = rx1.payload
        {
            assert_eq!(severity, "critical");
            assert_eq!(message, "CPU usage at 99%");
        } else {
            panic!("Unexpected payload variant");
        }
    }
}
