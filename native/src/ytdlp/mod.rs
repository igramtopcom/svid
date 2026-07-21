/// yt-dlp integration module
/// Provides subprocess execution and output parsing for yt-dlp binary

pub mod executor;
pub mod parser;

pub use executor::*;
pub use parser::*;
