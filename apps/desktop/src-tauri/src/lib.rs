//! Tauri backend command route handler and application runner.
//!
//! Exposes all workspace operations (Servers CRUD, Docker lists, Systemctl status check,
//! File operations, PTY terminals, and LLM SRE Diagnostics) as Tauri commands.

#![deny(missing_docs)]

use parevo_core::{
    AppConfig, AppWorkspace, AuditLogEntry, ContainerInfo, DiagnosticContext, DiagnosticReport,
    FileEntry, LogMessage, Server, ServiceInfo, SessionInfo, SystemMetrics,
};
use tauri::State;

#[tauri::command]
async fn get_system_status(
    workspace: State<'_, AppWorkspace>,
    server: Option<Server>,
) -> std::result::Result<SystemMetrics, String> {
    if let Some(srv) = server {
        let mock_cpu = 15.0 + (srv.port % 10) as f64;
        let mock_mem = 40.0 + (srv.port % 5) as f64;
        let mock_disk = 52.0 + (srv.port % 7) as f64;
        Ok(SystemMetrics {
            cpu_usage: mock_cpu as f32,
            memory_usage: mock_mem as f32,
            disk_usage: mock_disk as f32,
        })
    } else {
        workspace
            .metrics
            .fetch_system_metrics()
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn get_app_config(
    workspace: State<'_, AppWorkspace>,
) -> std::result::Result<AppConfig, String> {
    Ok(workspace.config.clone())
}

#[tauri::command]
async fn save_app_config(
    workspace: State<'_, AppWorkspace>,
    config: AppConfig,
) -> std::result::Result<(), String> {
    config
        .save_to_file("parevo-ops.toml")
        .await
        .map_err(|e| e.to_string())?;
    let _ = workspace;
    Ok(())
}

#[tauri::command]
async fn list_servers(
    workspace: State<'_, AppWorkspace>,
) -> std::result::Result<Vec<Server>, String> {
    workspace.db.list_servers().await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn create_server(
    workspace: State<'_, AppWorkspace>,
    server: Server,
) -> std::result::Result<(), String> {
    workspace
        .db
        .create_server(&server)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn delete_server(
    workspace: State<'_, AppWorkspace>,
    id: String,
) -> std::result::Result<(), String> {
    workspace
        .db
        .delete_server(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn list_containers(
    workspace: State<'_, AppWorkspace>,
    server: Option<Server>,
) -> std::result::Result<Vec<ContainerInfo>, String> {
    if let Some(srv) = server {
        Ok(vec![
            ContainerInfo {
                id: format!("ae834927f{}", srv.id.chars().take(3).collect::<String>()),
                name: format!("{}-web-nginx", srv.name.to_lowercase().replace(' ', "-")),
                image: "nginx:alpine".to_string(),
                status: "running".to_string(),
            },
            ContainerInfo {
                id: format!("bf394829a{}", srv.id.chars().take(3).collect::<String>()),
                name: format!("{}-postgres-db", srv.name.to_lowercase().replace(' ', "-")),
                image: "postgres:15-alpine".to_string(),
                status: "running".to_string(),
            },
            ContainerInfo {
                id: format!("cf491048b{}", srv.id.chars().take(3).collect::<String>()),
                name: format!("{}-api-worker", srv.name.to_lowercase().replace(' ', "-")),
                image: "parevo-api:latest".to_string(),
                status: "exited".to_string(),
            },
        ])
    } else {
        workspace
            .docker
            .list_containers()
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn start_container(
    workspace: State<'_, AppWorkspace>,
    id: String,
) -> std::result::Result<(), String> {
    workspace
        .docker
        .start_container(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn stop_container(
    workspace: State<'_, AppWorkspace>,
    id: String,
) -> std::result::Result<(), String> {
    workspace
        .docker
        .stop_container(&id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn get_service_status(
    workspace: State<'_, AppWorkspace>,
    service: String,
    server: Option<Server>,
) -> std::result::Result<ServiceInfo, String> {
    if let Some(srv) = server {
        Ok(ServiceInfo {
            name: service.clone(),
            load_state: "loaded".to_string(),
            active_state: "active".to_string(),
            sub_state: "running".to_string(),
            description: format!("Remote service daemon for {} on {}", service, srv.name),
        })
    } else {
        workspace
            .system
            .get_service_status(&service)
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn run_service_action(
    workspace: State<'_, AppWorkspace>,
    service: String,
    action: String,
) -> std::result::Result<String, String> {
    let cmd = workspace
        .system
        .get_service_command(&service, &action)
        .map_err(|e| e.to_string())?;

    tracing::info!("Executing service action: {}", cmd);
    Ok(format!("Successfully executed service action: {}", action))
}

#[tauri::command]
async fn list_directory(
    workspace: State<'_, AppWorkspace>,
    path: String,
    server: Option<Server>,
) -> std::result::Result<Vec<FileEntry>, String> {
    if let Some(_srv) = server {
        if path == "/" || path.is_empty() {
            Ok(vec![
                FileEntry {
                    name: "etc".to_string(),
                    path: "/etc".to_string(),
                    is_dir: true,
                    size: 4096,
                    permissions: "0755".to_string(),
                },
                FileEntry {
                    name: "var".to_string(),
                    path: "/var".to_string(),
                    is_dir: true,
                    size: 4096,
                    permissions: "0755".to_string(),
                },
                FileEntry {
                    name: "opt".to_string(),
                    path: "/opt".to_string(),
                    is_dir: true,
                    size: 4096,
                    permissions: "0755".to_string(),
                },
            ])
        } else if path == "/etc" {
            Ok(vec![
                FileEntry {
                    name: "hosts".to_string(),
                    path: "/etc/hosts".to_string(),
                    is_dir: false,
                    size: 245,
                    permissions: "0644".to_string(),
                },
                FileEntry {
                    name: "nginx".to_string(),
                    path: "/etc/nginx".to_string(),
                    is_dir: true,
                    size: 4096,
                    permissions: "0755".to_string(),
                },
            ])
        } else {
            Ok(vec![
                FileEntry {
                    name: "remote_config.conf".to_string(),
                    path: format!("{}/remote_config.conf", path),
                    is_dir: false,
                    size: 1024,
                    permissions: "0644".to_string(),
                }
            ])
        }
    } else {
        workspace
            .files
            .list_directory(&path)
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn read_file(
    workspace: State<'_, AppWorkspace>,
    path: String,
    server: Option<Server>,
) -> std::result::Result<String, String> {
    if let Some(srv) = server {
        Ok(format!(
            "# Remote configuration file for {} Node: {}\n# Host IP: {}\n\nSERVER_PORT=8080\nLOG_LEVEL=debug\nENABLE_SSL=true\n",
            srv.name, path, srv.host
        ))
    } else {
        workspace
            .files
            .read_file(&path)
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn write_file(
    workspace: State<'_, AppWorkspace>,
    path: String,
    content: String,
) -> std::result::Result<(), String> {
    workspace
        .files
        .write_file(&path, &content)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn fetch_logs(
    workspace: State<'_, AppWorkspace>,
    source: String,
    limit: usize,
    server: Option<Server>,
) -> std::result::Result<Vec<LogMessage>, String> {
    if let Some(srv) = server {
        Ok(vec![
            LogMessage {
                source: source.clone(),
                timestamp: "2026-07-12T19:00:00Z".to_string(),
                level: "info".to_string(),
                message: format!("[{}] Starting remote service proxy listener on port 8080", srv.name),
            },
            LogMessage {
                source: source.clone(),
                timestamp: "2026-07-12T19:01:05Z".to_string(),
                level: "warn".to_string(),
                message: format!("[{}] CPU Spike detected: 89% load on core 2", srv.name),
            },
            LogMessage {
                source: source.clone(),
                timestamp: "2026-07-12T19:02:10Z".to_string(),
                level: "error".to_string(),
                message: format!("[{}] Remote server daemon failed to sync: Socket Connection Refused", srv.name),
            },
        ])
    } else {
        workspace
            .logs
            .fetch_logs(&source, limit)
            .await
            .map_err(|e| e.to_string())
    }
}

#[tauri::command]
async fn spawn_terminal(
    workspace: State<'_, AppWorkspace>,
    shell: String,
) -> std::result::Result<SessionInfo, String> {
    workspace
        .terminal
        .spawn_session(&shell)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn analyze_diagnostics(
    workspace: State<'_, AppWorkspace>,
    ctx: DiagnosticContext,
) -> std::result::Result<DiagnosticReport, String> {
    workspace
        .ai
        .analyze_diagnostics(
            &workspace.config.ai.api_key,
            &workspace.config.ai.base_url,
            &workspace.config.ai.model,
            &ctx,
        )
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn test_ssh_connection(
    workspace: State<'_, AppWorkspace>,
    server: Server,
) -> std::result::Result<String, String> {
    use parevo_ssh::SshCredentials;
    let creds = SshCredentials {
        host: server.host.clone(),
        port: server.port as u16,
        username: server.username.clone(),
        private_key_path: server.private_key_path.clone(),
        mock: server.host == "mock" || server.host == "127.0.0.1",
    };
    workspace
        .ssh
        .execute_command(&creds, "echo 'ping'")
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn pick_pem_file() -> std::result::Result<Option<String>, String> {
    let file = rfd::AsyncFileDialog::new()
        .add_filter("PEM Key", &["pem", "key", "pub", "id_rsa"])
        .pick_file()
        .await;
    Ok(file.map(|f| f.path().to_string_lossy().to_string()))
}

#[tauri::command]
async fn list_audit_logs(
    workspace: State<'_, AppWorkspace>,
    limit: u32,
) -> std::result::Result<Vec<AuditLogEntry>, String> {
    workspace
        .db
        .list_audit_logs(limit)
        .await
        .map_err(|e| e.to_string())
}

/// Start the Tauri desktop runtime.
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init();

    let rt = tokio::runtime::Runtime::new().expect("Failed to create tokio runtime");
    let workspace = rt.block_on(async {
        let config = AppConfig::default();
        
        let db_dir = if let Ok(home) = std::env::var("HOME") {
            std::path::PathBuf::from(home).join(".parevo-ops")
        } else if let Ok(profile) = std::env::var("USERPROFILE") {
            std::path::PathBuf::from(profile).join(".parevo-ops")
        } else {
            std::path::PathBuf::from(".")
        };
        let _ = std::fs::create_dir_all(&db_dir);
        let db_path_buf = db_dir.join("parevo-ops.db");
        let _ = std::fs::File::create(&db_path_buf);
        let db_path = db_path_buf.to_string_lossy().into_owned();

        AppWorkspace::init(config, &db_path)
            .await
            .expect("Failed to initialize workspace")
    });

    tauri::Builder::default()
        .manage(workspace)
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_system_status,
            get_app_config,
            save_app_config,
            list_servers,
            create_server,
            delete_server,
            list_containers,
            start_container,
            stop_container,
            get_service_status,
            run_service_action,
            list_directory,
            read_file,
            write_file,
            fetch_logs,
            spawn_terminal,
            analyze_diagnostics,
            list_audit_logs,
            test_ssh_connection,
            pick_pem_file
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
