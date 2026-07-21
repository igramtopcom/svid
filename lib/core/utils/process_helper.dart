import 'dart:convert';
import 'dart:io';

/// Helper for spawning subprocesses without visible console windows on Windows.
///
/// On Windows, [Process.start] and [Process.run] create a visible console
/// window for every console application (yt-dlp.exe, ffmpeg.exe, etc.).
/// Dart's Process API doesn't expose Windows' CREATE_NO_WINDOW flag.
///
/// Workaround: `runInShell: true` on Windows routes through cmd.exe which
/// inherits the parent's (hidden) console instead of creating a new one.
class ProcessHelper {
  static const Duration fileManagerTimeout = Duration(seconds: 5);

  /// Start a process without showing a console window on Windows.
  /// On macOS/Linux, behaves identically to [Process.start].
  ///
  /// Note: runInShell is intentionally false on ALL platforms for Process.start.
  /// On Windows, runInShell wraps in cmd.exe which corrupts stdout stream
  /// handling — the progress stream closes prematurely, causing downloads
  /// to emit cancelled events. Console window may flash briefly on Windows,
  /// but stream integrity is preserved for correct download progress tracking.
  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      mode: mode,
    );
  }

  /// Run a process without showing a console window on Windows.
  /// On macOS/Linux, behaves identically to [Process.run].
  ///
  /// On Windows, uses `runInShell: true` to hide the console window.
  /// Arguments are escaped for cmd.exe metacharacters (& | < >) that
  /// Dart's Process API does not handle — URLs with query parameters
  /// like `?foo=bar&baz=qux` would otherwise be split on `&` by cmd.exe.
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    final isWindows = Platform.isWindows;
    return Process.run(
      executable,
      isWindows ? arguments.map(_escapeCmdMeta).toList() : arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: isWindows,
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  }

  /// Bypass-shell variant of [run] for invoking app-managed binaries
  /// whose **executable path may contain spaces**. Use this when the
  /// binary lives under `getApplicationSupportDirectory()` on Windows
  /// (the path resolves to `%APPDATA%\<CompanyName>\<ProductName>\...`
  /// and `<CompanyName>` here is `"Bui Xuan Mai"` per the Windows
  /// runner VERSIONINFO — the embedded space breaks cmd.exe path
  /// resolution under the regular [run] path).
  ///
  /// 2026-05-25 production failure (vidcombo_2026-05-25.log):
  ///   ffmpeg audio recode emitted `'C:\Users\<u>\AppData\Roaming\Bui'
  ///   is not recognized as an internal or external command`. The
  ///   path was truncated at the first space inside `Bui Xuan Mai`
  ///   because [run] uses `runInShell: true` on Windows, which wraps
  ///   the call in `cmd /c <executable> <args>` and cmd.exe parses
  ///   the executable as `Bui` (everything after the first space
  ///   becomes arguments to a non-existent command).
  ///
  /// [runDirect] passes the executable + args verbatim to
  /// `CreateProcessW` (`runInShell: false`). The executable path is
  /// not parsed by any shell, so spaces inside it are preserved.
  /// The trade-off: cmd.exe metacharacter escaping (`& | < > ^`)
  /// from [run] is NOT applied — callers must NOT pass URL args
  /// with raw `&` through this helper. For binary-path-only args
  /// (file paths + flags + numeric values), `runInShell: false`
  /// is safe AND the only correct option when the executable path
  /// contains spaces.
  ///
  /// Known callsites (P0 fix 2026-05-25):
  ///   - ytdlp_datasource ffprobe audio bitrate probe
  ///   - ytdlp_datasource ffmpeg audio bitrate recode (prod failure)
  ///   - gallerydl_datasource extraction (URL is one whole arg, not
  ///     concatenated; no shell = no `&` splitting risk either)
  ///
  /// Console-window risk: on Windows release builds Flutter is GUI-
  /// subsystem so child processes do not allocate a visible console
  /// by default. If a tester observes a console flash, follow up
  /// with a `CREATE_NO_WINDOW` startup flag via native channel; do
  /// NOT preemptively expand scope of this P0 fix.
  static Future<ProcessResult> runDirect(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  }

  /// Open a directory in the platform file manager.
  static Future<ProcessResult> openDirectoryInFileManager(
    String directoryPath,
  ) {
    if (Platform.isMacOS) {
      return Process.run('open', [directoryPath]).timeout(fileManagerTimeout);
    }
    if (Platform.isWindows) {
      return Process.run('explorer.exe', [
        _windowsPath(directoryPath),
      ]).timeout(fileManagerTimeout);
    }
    return Process.run('xdg-open', [directoryPath]).timeout(fileManagerTimeout);
  }

  /// Reveal a file in the platform file manager.
  ///
  /// Linux has no universal "select this file" command, so it opens the parent
  /// directory or [fallbackDirectory] when supplied.
  static Future<ProcessResult> revealInFileManager(
    String filePath, {
    String? fallbackDirectory,
  }) async {
    if (Platform.isMacOS) {
      final result = await Process.run('open', [
        '-R',
        filePath,
      ]).timeout(fileManagerTimeout);
      if (result.exitCode != 0 && fallbackDirectory != null) {
        return openDirectoryInFileManager(fallbackDirectory);
      }
      return result;
    }
    if (Platform.isWindows) {
      return Process.run('explorer.exe', [
        '/select,',
        _windowsPath(filePath),
      ]).timeout(fileManagerTimeout);
    }
    return openDirectoryInFileManager(
      fallbackDirectory ?? File(filePath).parent.path,
    );
  }

  /// Open a file with the OS default application.
  static Future<ProcessResult> openFileWithSystem(String filePath) {
    if (Platform.isMacOS) {
      return Process.run('open', [filePath]).timeout(fileManagerTimeout);
    }
    if (Platform.isWindows) {
      return Process.run('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        _windowsPath(filePath),
      ]).timeout(fileManagerTimeout);
    }
    return Process.run('xdg-open', [filePath]).timeout(fileManagerTimeout);
  }

  /// Open a Windows Settings URI such as `ms-settings:notifications`.
  static Future<ProcessResult> openWindowsSettings(String settingsUri) {
    return Process.run('explorer.exe', [
      settingsUri,
    ]).timeout(fileManagerTimeout);
  }

  /// Escape cmd.exe metacharacters for arguments passed via runInShell.
  ///
  /// Dart's Process API only auto-quotes arguments that contain spaces or
  /// double quotes. Unquoted arguments with `&`, `|`, `<`, `>` are
  /// interpreted as cmd.exe operators — e.g., a URL like
  /// `https://instagram.com/reel/x/?igsh=abc&sender_device=web` causes
  /// cmd.exe to run `sender_device=web` as a separate command.
  ///
  /// Arguments that contain spaces are skipped because Dart wraps them in
  /// double quotes, where these characters are already treated literally.
  static String _escapeCmdMeta(String arg) {
    // Args with spaces/tabs are auto-quoted by Dart's Process API,
    // so metacharacters inside double quotes are already literal.
    if (arg.contains(' ') || arg.contains('\t')) return arg;
    if (!arg.contains('&') &&
        !arg.contains('|') &&
        !arg.contains('<') &&
        !arg.contains('>') &&
        !arg.contains('%')) {
      return arg;
    }
    return arg
        .replaceAll('^', '^^')
        .replaceAll('&', '^&')
        .replaceAll('|', '^|')
        .replaceAll('<', '^<')
        .replaceAll('>', '^>')
        .replaceAll('%', '%%');
  }

  static String _windowsPath(String value) => value.replaceAll('/', '\\');
}
