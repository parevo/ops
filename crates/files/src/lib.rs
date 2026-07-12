//! Local and remote filesystem manager.
//!
//! Provides APIs to explore folders, preview files, write modifications,
//! delete files, and edit permissions.

#![deny(missing_docs)]

use parevo_common::{Error, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

/// File detail descriptor.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FileEntry {
    /// Item filename.
    pub name: String,
    /// Absolute canonical path.
    pub path: String,
    /// Size of the file in bytes.
    pub size: u64,
    /// True if directory, false if file.
    pub is_dir: bool,
    /// Unix octal permissions represented as string (e.g. "0755").
    pub permissions: String,
}

/// Filesystem inspector.
pub struct FileExplorer {}

impl Default for FileExplorer {
    fn default() -> Self {
        Self::new()
    }
}

impl FileExplorer {
    /// Instantiates file operator.
    pub fn new() -> Self {
        Self {}
    }

    /// Iterates elements inside the target path.
    pub async fn list_directory(&self, dir_path: &str) -> Result<Vec<FileEntry>> {
        let path = Path::new(dir_path);
        if !path.exists() {
            return Err(Error::FileSystem(format!(
                "Path does not exist: {}",
                dir_path
            )));
        }
        if !path.is_dir() {
            return Err(Error::FileSystem(format!(
                "Path is not a directory: {}",
                dir_path
            )));
        }

        let entries = fs::read_dir(path)
            .map_err(|e| Error::FileSystem(format!("Failed to read directory: {}", e)))?;

        let mut list = Vec::new();
        for entry in entries {
            let entry =
                entry.map_err(|e| Error::FileSystem(format!("Failed to parse entry: {}", e)))?;
            let metadata = entry
                .metadata()
                .map_err(|e| Error::FileSystem(format!("Failed to read metadata: {}", e)))?;

            let name = entry.file_name().to_string_lossy().into_owned();
            let canonical_path = entry.path().to_string_lossy().into_owned();
            let size = metadata.len();
            let is_dir = metadata.is_dir();

            let permissions = {
                #[cfg(unix)]
                {
                    format!("{:o}", metadata.permissions().mode() & 0o777)
                }
                #[cfg(not(unix))]
                {
                    "0644".to_string()
                }
            };

            list.push(FileEntry {
                name,
                path: canonical_path,
                size,
                is_dir,
                permissions,
            });
        }

        Ok(list)
    }

    /// Reads text file content.
    pub async fn read_file(&self, file_path: &str) -> Result<String> {
        let content = fs::read_to_string(file_path)
            .map_err(|e| Error::FileSystem(format!("Failed to read file: {}", e)))?;
        Ok(content)
    }

    /// Overwrites or creates a text file.
    pub async fn write_file(&self, file_path: &str, content: &str) -> Result<()> {
        fs::write(file_path, content)
            .map_err(|e| Error::FileSystem(format!("Failed to write file: {}", e)))?;
        Ok(())
    }

    /// Deletes a file.
    pub async fn delete_file(&self, file_path: &str) -> Result<()> {
        fs::remove_file(file_path)
            .map_err(|e| Error::FileSystem(format!("Failed to remove file: {}", e)))?;
        Ok(())
    }

    /// Edits file permissions (Unix only).
    pub async fn chmod(&self, file_path: &str, mode: u32) -> Result<()> {
        let path = Path::new(file_path);
        let metadata = fs::metadata(path)
            .map_err(|e| Error::FileSystem(format!("Failed to read metadata: {}", e)))?;

        let mut permissions = metadata.permissions();
        #[cfg(unix)]
        {
            permissions.set_mode(mode);
            fs::set_permissions(path, permissions)
                .map_err(|e| Error::FileSystem(format!("Failed to set permissions: {}", e)))?;
        }
        #[cfg(not(unix))]
        {
            let _ = permissions;
            let _ = mode;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_filesystem_crud() {
        let temp_dir = std::env::temp_dir();
        let file_path = temp_dir.join("test_filesystem_ops.txt");
        let explorer = FileExplorer::new();

        // Write
        let write_res = explorer
            .write_file(file_path.to_str().unwrap(), "hello world")
            .await;
        assert!(write_res.is_ok());

        // Read
        let content = explorer.read_file(file_path.to_str().unwrap()).await;
        assert!(content.is_ok());
        assert_eq!(content.unwrap(), "hello world");

        // List dir
        let list = explorer
            .list_directory(temp_dir.to_str().unwrap())
            .await
            .unwrap();
        let test_file_entry = list
            .iter()
            .find(|e| e.name == "test_filesystem_ops.txt")
            .unwrap();
        assert_eq!(test_file_entry.size, 11);
        assert!(!test_file_entry.is_dir);

        // Chmod (Unix)
        #[cfg(unix)]
        {
            let chmod_res = explorer.chmod(file_path.to_str().unwrap(), 0o755).await;
            assert!(chmod_res.is_ok());
            let list = explorer
                .list_directory(temp_dir.to_str().unwrap())
                .await
                .unwrap();
            let entry = list
                .iter()
                .find(|e| e.name == "test_filesystem_ops.txt")
                .unwrap();
            assert_eq!(entry.permissions, "755");
        }

        // Delete
        assert!(explorer
            .delete_file(file_path.to_str().unwrap())
            .await
            .is_ok());
    }
}
