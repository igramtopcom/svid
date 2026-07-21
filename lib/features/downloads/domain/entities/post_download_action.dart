/// Action to take automatically after a download completes.
enum PostDownloadAction {
  /// Do nothing (default).
  none,

  /// Open the downloaded file with the system default app.
  openFile,

  /// Open the containing folder in Finder/Explorer.
  openFolder,

  /// Move the file to a custom folder after download.
  moveToFolder,

  /// Move the file to a custom folder, then delete the original.
  /// (Same as moveToFolder but makes intent explicit in UI labels.)
  deleteAfterMove,
}
