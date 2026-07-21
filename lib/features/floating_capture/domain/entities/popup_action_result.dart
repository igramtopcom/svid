/// Result of a popup-initiated terminal action (Download / OpenInApp).
///
/// Sent from the main engine to the popup engine via the new v2.2 IPC method
/// `setActionResult` so the popup can transition to State 6/7/8 (Started /
/// Complete / Failed) per Stitch design.
///
/// Sealed hierarchy: any new variant is a compile-time error in popup-side
/// pattern matching (defensive against silent missing-handler bugs).
sealed class PopupActionResult {
  const PopupActionResult();

  /// JSON wire format for IPC.
  ///
  /// Schema:
  ///   `{ "type": "started" | "completed" | "failed" | "authRequired",
  ///      "filename"?: string, "savedPath"?: string, "message"?: string,
  ///      "errorCode"?: string, "containerRecodeNotice"?: string }`
  Map<String, dynamic> toJson();

  /// Decode wire format. Returns null if `type` is missing/unknown so the
  /// popup gracefully ignores malformed messages instead of crashing.
  static PopupActionResult? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) return null;
    switch (type) {
      case 'started':
        final filename = json['filename'] as String?;
        if (filename == null) return null;
        return PopupActionStarted(
          filename: filename,
          containerRecodeNotice: json['containerRecodeNotice'] as String?,
        );
      case 'completed':
        final filename = json['filename'] as String?;
        final path = json['savedPath'] as String?;
        if (filename == null || path == null) return null;
        return PopupActionCompleted(filename: filename, savedPath: path);
      case 'failed':
        final message = json['message'] as String?;
        if (message == null) return null;
        return PopupActionFailed(
          message,
          errorCode: json['errorCode'] as String?,
        );
      case 'authRequired':
        return const PopupActionAuthRequired();
      default:
        return null; // forward-compat: unknown variant from newer main engine
    }
  }
}

/// Direct download successfully enqueued — popup shows State 6 then auto-closes
/// in 4 seconds. [filename] is the file currently being written (truncated by
/// UI for display).
///
/// [containerRecodeNotice] is set when ContainerPlanner determined the
/// download will need a full re-encode to honor the user's chosen
/// container (e.g. AVI at 4K, MP4 against Opus audio). The popup's
/// State 6 displays this so the user knows the download will be
/// slower than usual — Codex audit fix for the silent-recode UX gap
/// where the floating capture path was logging the warning but never
/// surfacing it to the user.
class PopupActionStarted extends PopupActionResult {
  final String filename;
  final String? containerRecodeNotice;
  const PopupActionStarted({
    required this.filename,
    this.containerRecodeNotice,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'started',
    'filename': filename,
    if (containerRecodeNotice != null)
      'containerRecodeNotice': containerRecodeNotice,
  };

  @override
  bool operator ==(Object other) =>
      other is PopupActionStarted &&
      other.filename == filename &&
      other.containerRecodeNotice == containerRecodeNotice;
  @override
  int get hashCode => Object.hash(filename, containerRecodeNotice);
}

/// Download finished — rare case where user reopens popup from tray after
/// completion. State 7 shows "Open folder" + "Close" actions.
class PopupActionCompleted extends PopupActionResult {
  final String filename;
  final String savedPath;
  const PopupActionCompleted({required this.filename, required this.savedPath});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'completed',
    'filename': filename,
    'savedPath': savedPath,
  };

  @override
  bool operator ==(Object other) =>
      other is PopupActionCompleted &&
      other.filename == filename &&
      other.savedPath == savedPath;
  @override
  int get hashCode => Object.hash(filename, savedPath);
}

/// Direct download failed (yt-dlp error / network / format unavailable).
/// State 8 shows error message + per-class CTA when [errorCode] is set
/// (RC8.5). Pre-RC8.5 the popup only had a generic "Open app for
/// details" CTA — every non-auth failure class collapsed to the same
/// UX regardless of root cause (cookie DB locked, Deno missing,
/// ffmpeg encoder gap all looked identical). [errorCode] carries the
/// `DownloadErrorCode.name` string (kept as String not enum because
/// the floating popup process imports a narrow subset of the app to
/// keep startup fast — avoids forcing a `download_error_code.dart`
/// import into the floating window's compile graph). When null the
/// popup falls back to the legacy generic CTA.
class PopupActionFailed extends PopupActionResult {
  final String message;
  final String? errorCode;
  const PopupActionFailed(this.message, {this.errorCode});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'failed',
    'message': message,
    if (errorCode != null) 'errorCode': errorCode,
  };

  @override
  bool operator ==(Object other) =>
      other is PopupActionFailed &&
      other.message == message &&
      other.errorCode == errorCode;
  @override
  int get hashCode => Object.hash(message, errorCode);
}

/// Direct download blocked because video requires authentication (private,
/// members-only, age-restricted requiring sign-in). State 8b — primary action
/// switches to "Open in app" so user can use cookies-aware path.
class PopupActionAuthRequired extends PopupActionResult {
  const PopupActionAuthRequired();

  @override
  Map<String, dynamic> toJson() => const {'type': 'authRequired'};

  @override
  bool operator ==(Object other) => other is PopupActionAuthRequired;
  @override
  int get hashCode => 'authRequired'.hashCode;
}
