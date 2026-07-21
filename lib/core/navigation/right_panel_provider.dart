import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/downloads/domain/entities/download_entity.dart';

/// Right panel display mode
enum RightPanelMode {
  quickStart, // URL input + platform shortcuts
  detail, // Selected download detail
  empty, // No content selected
}

/// Right panel state
class RightPanelState {
  final RightPanelMode mode;
  final DownloadEntity? selectedDownload;

  const RightPanelState({
    this.mode = RightPanelMode.quickStart,
    this.selectedDownload,
  });

  RightPanelState copyWith({
    RightPanelMode? mode,
    DownloadEntity? selectedDownload,
    bool clearDownload = false,
  }) {
    return RightPanelState(
      mode: mode ?? this.mode,
      selectedDownload: clearDownload ? null : (selectedDownload ?? this.selectedDownload),
    );
  }
}

/// Right panel state notifier
class RightPanelNotifier extends StateNotifier<RightPanelState> {
  RightPanelNotifier() : super(const RightPanelState());

  /// Show quick start (URL input + platforms)
  void showQuickStart() {
    state = const RightPanelState(mode: RightPanelMode.quickStart);
  }

  /// Show download detail
  void showDetail(DownloadEntity download) {
    state = RightPanelState(
      mode: RightPanelMode.detail,
      selectedDownload: download,
    );
  }

  /// Clear selection
  void clearSelection() {
    state = const RightPanelState(mode: RightPanelMode.quickStart);
  }
}

/// Right panel provider
final rightPanelProvider = StateNotifierProvider<RightPanelNotifier, RightPanelState>((ref) {
  return RightPanelNotifier();
});
