/// Recursive directory scanner
use anyhow::Result;
use std::fs;
use std::path::Path;

/// Scan directory recursively and return total size in bytes
pub fn scan_directory(path: &str) -> Result<u64> {
    let path = Path::new(path);

    if !path.exists() {
        anyhow::bail!("Path does not exist: {}", path.display());
    }

    let mut total_size = 0u64;

    if path.is_file() {
        return Ok(fs::metadata(path)?.len());
    }

    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let metadata = entry.metadata()?;

            if metadata.is_file() {
                total_size += metadata.len();
            } else if metadata.is_dir() {
                total_size += scan_directory(&entry.path().to_string_lossy())?;
            }
        }
    }

    Ok(total_size)
}
