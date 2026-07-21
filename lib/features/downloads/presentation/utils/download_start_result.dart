class DownloadStartResult {
  final bool started;
  final String? warning;

  const DownloadStartResult({required this.started, this.warning});

  const DownloadStartResult.notStarted() : started = false, warning = null;

  const DownloadStartResult.started([this.warning]) : started = true;
}
