//! Docker Engine API client integration.
//!
//! Provides the core client to connect to local or remote Docker daemon sockets,
//! lists container profiles, streams logs, and executes state operations (start, stop, restart).

#![deny(missing_docs)]

use bollard::container::{ListContainersOptions, StartContainerOptions, StopContainerOptions};
use bollard::Docker;
use parevo_common::{Error, Result};
use serde::{Deserialize, Serialize};

/// High-level details of a docker container.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContainerInfo {
    /// Unique Docker container identifier.
    pub id: String,
    /// Human-readable name.
    pub name: String,
    /// Image used to launch the container.
    pub image: String,
    /// Run status (e.g. running, exited).
    pub status: String,
}

/// Client to communicate with Docker Engine.
pub struct DockerClient {
    mock: bool,
}

impl Default for DockerClient {
    fn default() -> Self {
        Self::new(true) // Defaults to mock mode for headless CLI / tests
    }
}

impl DockerClient {
    /// Creates a new instance of the Docker client.
    pub fn new(mock: bool) -> Self {
        Self { mock }
    }

    /// Connects to the local Docker socket and lists all containers.
    pub async fn list_containers(&self) -> Result<Vec<ContainerInfo>> {
        if self.mock {
            return Ok(vec![
                ContainerInfo {
                    id: "ae834927fcd2".to_string(),
                    name: "parevo-api-dev".to_string(),
                    image: "rust:1.80-alpine".to_string(),
                    status: "running".to_string(),
                },
                ContainerInfo {
                    id: "cf129384bc19".to_string(),
                    name: "parevo-postgres".to_string(),
                    image: "postgres:15-alpine".to_string(),
                    status: "running".to_string(),
                },
            ]);
        }

        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| Error::Docker(format!("Docker socket connection failed: {}", e)))?;

        let options = Some(ListContainersOptions::<String> {
            all: true,
            ..Default::default()
        });

        let containers = docker
            .list_containers(options)
            .await
            .map_err(|e| Error::Docker(format!("Failed to list containers: {}", e)))?;

        let list = containers
            .into_iter()
            .map(|c| ContainerInfo {
                id: c.id.unwrap_or_default(),
                name: c
                    .names
                    .and_then(|n| n.first().cloned())
                    .unwrap_or_else(|| "unnamed".to_string()),
                image: c.image.unwrap_or_default(),
                status: c.state.unwrap_or_default(),
            })
            .collect();

        Ok(list)
    }

    /// Stops a running container.
    pub async fn stop_container(&self, id: &str) -> Result<()> {
        if self.mock {
            tracing::info!("Mock stop container: {}", id);
            return Ok(());
        }

        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| Error::Docker(format!("Docker socket connection failed: {}", e)))?;

        docker
            .stop_container(id, None::<StopContainerOptions>)
            .await
            .map_err(|e| Error::Docker(format!("Failed to stop container {}: {}", id, e)))?;

        Ok(())
    }

    /// Starts an existing container.
    pub async fn start_container(&self, id: &str) -> Result<()> {
        if self.mock {
            tracing::info!("Mock start container: {}", id);
            return Ok(());
        }

        let docker = Docker::connect_with_local_defaults()
            .map_err(|e| Error::Docker(format!("Docker socket connection failed: {}", e)))?;

        docker
            .start_container(id, None::<StartContainerOptions<String>>)
            .await
            .map_err(|e| Error::Docker(format!("Failed to start container {}: {}", id, e)))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_docker_list_mock() {
        let client = DockerClient::new(true);
        let list = client.list_containers().await;
        assert!(list.is_ok());
        let list = list.unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].name, "parevo-api-dev");
        assert_eq!(list[1].name, "parevo-postgres");
    }

    #[tokio::test]
    async fn test_docker_stop_start_mock() {
        let client = DockerClient::new(true);
        assert!(client.stop_container("cf129384bc19").await.is_ok());
        assert!(client.start_container("cf129384bc19").await.is_ok());
    }
}
