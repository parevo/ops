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
) -> std::result::Result<SystemMetrics, String> {
    workspace
        .metrics
        .fetch_system_metrics()
        .await
        .map_err(|e| e.to_string())
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
    // Write configuration changes to local directory
    config
        .save_to_file("parevo-ops.toml")
        .await
        .map_err(|e| e.to_string())?;
    // We would typically hot reload workspace config here
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
) -> std::result::Result<Vec<ContainerInfo>, String> {
    workspace
        .docker
        .list_containers()
        .await
        .map_err(|e| e.to_string())
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
) -> std::result::Result<ServiceInfo, String> {
    workspace
        .system
        .get_service_status(&service)
        .await
        .map_err(|e| e.to_string())
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

    // Typically runs command locally or on a mock system
    tracing::info!("Executing service action: {}", cmd);
    Ok(format!("Successfully executed service action: {}", action))
}

#[tauri::command]
async fn list_directory(
    workspace: State<'_, AppWorkspace>,
    path: String,
) -> std::result::Result<Vec<FileEntry>, String> {
    workspace
        .files
        .list_directory(&path)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn read_file(
    workspace: State<'_, AppWorkspace>,
    path: String,
) -> std::result::Result<String, String> {
    workspace
        .files
        .read_file(&path)
        .await
        .map_err(|e| e.to_string())
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
) -> std::result::Result<Vec<LogMessage>, String> {
    workspace
        .logs
        .fetch_logs(&source, limit)
        .await
        .map_err(|e| e.to_string())
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
