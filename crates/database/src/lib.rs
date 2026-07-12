//! Persistent storage engine for Parevo Ops.
//!
//! Manages connection pools, migrations, and CRUD transactions for servers and audit trails
//! in a local SQLite file.

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use sqlx::{sqlite::SqlitePoolOptions, FromRow, SqlitePool};
use std::path::Path;

/// Server profile model stored in the database.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, FromRow, PartialEq, Eq)]
pub struct Server {
    /// Unique UUID string.
    pub id: String,
    /// Friendly display name.
    pub name: String,
    /// Destination IP or Hostname.
    pub host: String,
    /// Destination SSH Port.
    pub port: i32,
    /// SSH username to log in with.
    pub username: String,
    /// Optional absolute path to SSH private key file.
    pub private_key_path: Option<String>,
    /// Last known connection status ("online", "offline", "unknown").
    pub status: String,
    /// Server group classification (e.g. "production", "staging").
    pub group_name: String,
    /// Comma-separated or JSON list of labels/tags.
    pub tags: String,
}

/// Audit log entry tracking user and AI actions.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, FromRow, PartialEq, Eq)]
pub struct AuditLogEntry {
    /// Unique event identifier.
    pub id: String,
    /// Date-time log string.
    pub timestamp: String,
    /// The initiator actor (e.g. "user", "ai").
    pub actor: String,
    /// The operation name (e.g. "restart_container").
    pub action: String,
    /// The target resource identifier.
    pub target: String,
    /// Detailed telemetry or command context.
    pub details: String,
}

/// SQLite Database Client.
pub struct DbClient {
    pool: SqlitePool,
}

impl DbClient {
    /// Establishes connection pool and verifies SQLite connection.
    pub async fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let db_url = format!(
            "sqlite://{}",
            path.as_ref()
                .to_str()
                .ok_or_else(|| Error::Database("Invalid database path".to_string()))?
        );

        let pool = SqlitePoolOptions::new()
            .max_connections(10)
            .connect(&db_url)
            .await
            .map_err(|e| Error::Database(format!("Failed to connect to SQLite: {}", e)))?;

        Ok(Self { pool })
    }

    /// Triggers table creation schema migrations programmatically.
    pub async fn run_migrations(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS servers (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                username TEXT NOT NULL,
                private_key_path TEXT,
                status TEXT NOT NULL,
                group_name TEXT NOT NULL,
                tags TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
            );",
        )
        .execute(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Migration failed for 'servers': {}", e)))?;

        sqlx::query(
            "CREATE TABLE IF NOT EXISTS audit_logs (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                actor TEXT NOT NULL,
                action TEXT NOT NULL,
                target TEXT NOT NULL,
                details TEXT NOT NULL
            );",
        )
        .execute(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Migration failed for 'audit_logs': {}", e)))?;

        tracing::info!("SQLite migrations executed successfully.");
        Ok(())
    }

    /// Inserts a new Server profile.
    pub async fn create_server(&self, server: &Server) -> Result<()> {
        sqlx::query(
            "INSERT INTO servers (id, name, host, port, username, private_key_path, status, group_name, tags)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        )
        .bind(&server.id)
        .bind(&server.name)
        .bind(&server.host)
        .bind(server.port)
        .bind(&server.username)
        .bind(&server.private_key_path)
        .bind(&server.status)
        .bind(&server.group_name)
        .bind(&server.tags)
        .execute(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to insert server: {}", e)))?;

        Ok(())
    }

    /// Fetches a specific Server profile.
    pub async fn get_server(&self, id: &str) -> Result<Option<Server>> {
        let server = sqlx::query_as::<_, Server>(
            "SELECT id, name, host, port, username, private_key_path, status, group_name, tags
             FROM servers WHERE id = ?;",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to fetch server: {}", e)))?;

        Ok(server)
    }

    /// Lists all Server profiles.
    pub async fn list_servers(&self) -> Result<Vec<Server>> {
        let servers = sqlx::query_as::<_, Server>(
            "SELECT id, name, host, port, username, private_key_path, status, group_name, tags
             FROM servers ORDER BY name ASC;",
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to list servers: {}", e)))?;

        Ok(servers)
    }

    /// Updates properties of an existing Server profile.
    pub async fn update_server(&self, server: &Server) -> Result<()> {
        sqlx::query(
            "UPDATE servers
             SET name = ?, host = ?, port = ?, username = ?, private_key_path = ?, status = ?, group_name = ?, tags = ?
             WHERE id = ?;"
        )
        .bind(&server.name)
        .bind(&server.host)
        .bind(server.port)
        .bind(&server.username)
        .bind(&server.private_key_path)
        .bind(&server.status)
        .bind(&server.group_name)
        .bind(&server.tags)
        .bind(&server.id)
        .execute(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to update server: {}", e)))?;

        Ok(())
    }

    /// Deletes a Server profile.
    pub async fn delete_server(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM servers WHERE id = ?;")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(|e| Error::Database(format!("Failed to delete server: {}", e)))?;

        Ok(())
    }

    /// Writes a new Audit log entry.
    pub async fn create_audit_log(&self, entry: &AuditLogEntry) -> Result<()> {
        sqlx::query(
            "INSERT INTO audit_logs (id, timestamp, actor, action, target, details)
             VALUES (?, ?, ?, ?, ?, ?);",
        )
        .bind(&entry.id)
        .bind(&entry.timestamp)
        .bind(&entry.actor)
        .bind(&entry.action)
        .bind(&entry.target)
        .bind(&entry.details)
        .execute(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to log audit: {}", e)))?;

        Ok(())
    }

    /// Fetches audit logs, ordered by timestamp descending, limited to a max count.
    pub async fn list_audit_logs(&self, limit: u32) -> Result<Vec<AuditLogEntry>> {
        let logs = sqlx::query_as::<_, AuditLogEntry>(
            "SELECT id, strftime('%Y-%m-%dT%H:%M:%fZ', timestamp) as timestamp, actor, action, target, details
             FROM audit_logs ORDER BY timestamp DESC LIMIT ?;"
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| Error::Database(format!("Failed to query audit logs: {}", e)))?;

        Ok(logs)
    }

    /// Returns a reference to the active sqlite pool.
    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn setup_test_db() -> (DbClient, std::path::PathBuf) {
        let temp_dir = std::env::temp_dir();
        let db_path = temp_dir.join(format!("parevo-test-{}.db", uuid::Uuid::new_v4()));
        let _ = std::fs::File::create(&db_path);

        let client = DbClient::new(&db_path).await.unwrap();
        client.run_migrations().await.unwrap();
        (client, db_path)
    }

    #[tokio::test]
    async fn test_server_repository_crud() {
        let (client, db_path) = setup_test_db().await;

        let server_id = uuid::Uuid::new_v4().to_string();
        let server = Server {
            id: server_id.clone(),
            name: "Prod App".to_string(),
            host: "10.0.0.1".to_string(),
            port: 2222,
            username: "ubuntu".to_string(),
            private_key_path: Some("/home/ubuntu/.ssh/id_rsa".to_string()),
            status: "unknown".to_string(),
            group_name: "production".to_string(),
            tags: "api,primary".to_string(),
        };

        // Create
        assert!(client.create_server(&server).await.is_ok());

        // Read
        let fetched = client.get_server(&server_id).await.unwrap();
        assert!(fetched.is_some());
        let fetched = fetched.unwrap();
        assert_eq!(fetched, server);

        // List
        let list = client.list_servers().await.unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "Prod App");

        // Update
        let mut updated_server = server.clone();
        updated_server.name = "Prod App - Modified".to_string();
        updated_server.status = "online".to_string();
        assert!(client.update_server(&updated_server).await.is_ok());

        let fetched_updated = client.get_server(&server_id).await.unwrap().unwrap();
        assert_eq!(fetched_updated.name, "Prod App - Modified");
        assert_eq!(fetched_updated.status, "online");

        // Delete
        assert!(client.delete_server(&server_id).await.is_ok());
        let fetched_deleted = client.get_server(&server_id).await.unwrap();
        assert!(fetched_deleted.is_none());

        let _ = std::fs::remove_file(db_path);
    }

    #[tokio::test]
    async fn test_audit_logs_repository() {
        let (client, db_path) = setup_test_db().await;

        let log = AuditLogEntry {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: "2026-07-12T19:00:00Z".to_string(),
            actor: "ai-assistant".to_string(),
            action: "stop_container".to_string(),
            target: "docker-container-123".to_string(),
            details: "low disk alert trigger shutdown".to_string(),
        };

        assert!(client.create_audit_log(&log).await.is_ok());

        let logs = client.list_audit_logs(10).await.unwrap();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].actor, "ai-assistant");
        assert_eq!(logs[0].action, "stop_container");

        let _ = std::fs::remove_file(db_path);
    }
}
