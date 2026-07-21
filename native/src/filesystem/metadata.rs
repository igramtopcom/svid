/// File metadata extraction
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileMetadata {
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
    pub modified: Option<u64>, // Unix timestamp
}

pub fn get_metadata(path: &str) -> anyhow::Result<FileMetadata> {
    let path = Path::new(path);
    let metadata = std::fs::metadata(path)?;

    let modified = metadata.modified()
        .ok()
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|d| d.as_secs());

    Ok(FileMetadata {
        name: path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string(),
        size: metadata.len(),
        is_dir: metadata.is_dir(),
        modified,
    })
}
