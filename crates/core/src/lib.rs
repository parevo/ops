//! The core orchestration and service lifecycle layer of Parevo Ops.
//!
//! Tying together all decoupled domain modules (SSH, Docker, Database, Events, etc.)
//! and providing a single unified workspace context interface.

#![deny(missing_docs)]

use std::sync::Arc;

use parevo_ai::AiClient;
pub use parevo_ai::{DiagnosticContext, DiagnosticReport};
use parevo_common::Result;
pub use parevo_config::AppConfig;
use parevo_database::DbClient;
pub use parevo_database::{AuditLogEntry, Server};
pub use parevo_docker::ContainerInfo;
use parevo_docker::DockerClient;
use parevo_events::EventBus;
pub use parevo_files::FileEntry;
use parevo_files::FileExplorer;
use parevo_logs::LogManager;
pub use parevo_logs::LogMessage;
use parevo_metrics::MetricsCollector;
pub use parevo_metrics::SystemMetrics;
use parevo_plugins::PluginManager;
use parevo_ssh::SshManager;
pub use parevo_system::ServiceInfo;
use parevo_system::SystemManager;
pub use parevo_terminal::SessionInfo;
use parevo_terminal::TerminalManager;

/// The central workspace context that orchestrates and manages all core services.
pub struct AppWorkspace {
    /// System configuration.
    pub config: AppConfig,
    /// Persistence layer client.
    pub db: DbClient,
    /// Pub-Sub channel router.
    pub event_bus: Arc<EventBus>,
    /// Secure SSH executor and pool.
    pub ssh: SshManager,
    /// Docker Engine interface.
    pub docker: DockerClient,
    /// OS management and systemctl controller.
    pub system: SystemManager,
    /// File browsing and transfer manager.
    pub files: FileExplorer,
    /// Log collector and parser.
    pub logs: LogManager,
    /// PTY shell sessions.
    pub terminal: TerminalManager,
    /// System metrics aggregator.
    pub metrics: MetricsCollector,
    /// Diagnostic helper and AI coordinator.
    pub ai: AiClient,
    /// Dynamic extensions.
    pub plugins: PluginManager,
}

impl AppWorkspace {
    /// Initializes all sub-services and constructs the application workspace context.
    pub async fn init(config: AppConfig, db_path: &str) -> Result<Self> {
        tracing::info!("Initializing Parevo Ops Workspace Core...");

        // Setup SQLite pool
        let db = DbClient::new(db_path).await?;
        db.run_migrations().await?;

        // Shared Event Bus
        let event_bus = Arc::new(EventBus::new());

        // Sub-services
        let ssh = SshManager::default();
        let docker = DockerClient::default();
        let system = SystemManager::new();
        let files = FileExplorer::new();
        let logs = LogManager::new(Some(event_bus.clone()));
        let terminal = TerminalManager::default();
        let metrics = MetricsCollector::new();
        let ai = AiClient::new();
        let plugins = PluginManager::new();

        Ok(Self {
            config,
            db,
            event_bus,
            ssh,
            docker,
            system,
            files,
            logs,
            terminal,
            metrics,
            ai,
            plugins,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_workspace_init() {
        let config = AppConfig::default();
        let temp_dir = std::env::temp_dir();
        let db_path = temp_dir.join("test_workspace.db");

        // Touch database file
        let _ = std::fs::File::create(&db_path);

        let ws = AppWorkspace::init(config, db_path.to_str().unwrap()).await;
        assert!(ws.is_ok());

        let _ = std::fs::remove_file(db_path);
    }
}
