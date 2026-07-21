import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/core.dart';

/// Keyboard Shortcuts Help Dialog
/// Shows all available keyboard shortcuts for video player
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.dialog),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.accentHighlight.withValues(
                          alpha: AppOpacity.hover,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Icon(
                        Icons.keyboard_rounded,
                        color: AppColors.accentHighlight,
                        size: 20,
                      ),
                    ),
                    const Gap.smMd(),
                    Expanded(
                      child: Text(
                        AppLocalizations.keyboardShortcutsDialogTitle,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border(context)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('playback'), [
                        _ShortcutItem(
                          key: 'Space',
                          description: AppLocalizations.keyboardShortcutsItem('playPause'),
                        ),
                        _ShortcutItem(
                          key: 'K',
                          description: AppLocalizations.keyboardShortcutsItem('playPauseAlt'),
                        ),
                        _ShortcutItem(
                          key: '←',
                          description: AppLocalizations.keyboardShortcutsItem('seekBackward5s'),
                        ),
                        _ShortcutItem(
                          key: '→',
                          description: AppLocalizations.keyboardShortcutsItem('seekForward5s'),
                        ),
                        _ShortcutItem(
                          key: 'J',
                          description: AppLocalizations.keyboardShortcutsItem('seekBackward10s'),
                        ),
                        _ShortcutItem(
                          key: 'L',
                          description: AppLocalizations.keyboardShortcutsItem('seekForward10s'),
                        ),
                        _ShortcutItem(
                          key: '0-9',
                          description: AppLocalizations.keyboardShortcutsItem('seekPercentage'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('volume'), [
                        _ShortcutItem(key: '↑', description: AppLocalizations.keyboardShortcutsItem('volumeUp10')),
                        _ShortcutItem(key: '↓', description: AppLocalizations.keyboardShortcutsItem('volumeDown10')),
                        _ShortcutItem(key: 'M', description: AppLocalizations.keyboardShortcutsItem('muteUnmute')),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('view'), [
                        _ShortcutItem(
                          key: 'F',
                          description: AppLocalizations.keyboardShortcutsItem('toggleFullscreen'),
                        ),
                        _ShortcutItem(
                          key: 'Esc',
                          description: AppLocalizations.keyboardShortcutsItem('exitFullscreen'),
                        ),
                        _ShortcutItem(
                          key: 'Double Click',
                          description: AppLocalizations.keyboardShortcutsItem('toggleFullscreen'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('playbackSpeed'), [
                        _ShortcutItem(key: '<', description: AppLocalizations.keyboardShortcutsItem('decreaseSpeed')),
                        _ShortcutItem(key: '>', description: AppLocalizations.keyboardShortcutsItem('increaseSpeed')),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('frameCapture'), [
                        _ShortcutItem(
                          key: ',',
                          description: AppLocalizations.keyboardShortcutsItem('frameStepBack'),
                        ),
                        _ShortcutItem(
                          key: '.',
                          description: AppLocalizations.keyboardShortcutsItem('frameStepForward'),
                        ),
                        _ShortcutItem(
                          key: 'S',
                          description: AppLocalizations.keyboardShortcutsItem('screenshot'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('cinema'), [
                        _ShortcutItem(
                          key: 'G',
                          description: AppLocalizations.keyboardShortcutsItem('toggleCinemaMode'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('trim'), [
                        _ShortcutItem(
                          key: 'T',
                          description: AppLocalizations.keyboardShortcutsItem('toggleTrimMode'),
                        ),
                        _ShortcutItem(
                          key: 'I',
                          description: AppLocalizations.keyboardShortcutsItem('setInPoint'),
                        ),
                        _ShortcutItem(
                          key: 'O',
                          description: AppLocalizations.keyboardShortcutsItem('setOutPoint'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('abLoop'), [
                        _ShortcutItem(
                          key: 'A',
                          description: AppLocalizations.keyboardShortcutsItem('setAbPoint'),
                        ),
                        _ShortcutItem(
                          key: 'X',
                          description: AppLocalizations.keyboardShortcutsItem('clearAbLoop'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('chapters'), [
                        _ShortcutItem(key: 'N', description: AppLocalizations.keyboardShortcutsItem('nextChapter')),
                        _ShortcutItem(
                          key: 'P',
                          description: AppLocalizations.keyboardShortcutsItem('previousChapter'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('help'), [
                        _ShortcutItem(
                          key: '?',
                          description: AppLocalizations.keyboardShortcutsItem('showHelpDialog'),
                        ),
                        _ShortcutItem(
                          key: 'H',
                          description: AppLocalizations.keyboardShortcutsItem('showHelpDialog'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('browser'), [
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+T' : 'Ctrl+T',
                          description: AppLocalizations.keyboardShortcutsItem('newTab'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+W' : 'Ctrl+W',
                          description: AppLocalizations.keyboardShortcutsItem('closeTab'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+Shift+]' : 'Ctrl+Tab',
                          description: AppLocalizations.keyboardShortcutsItem('nextTab'),
                        ),
                        _ShortcutItem(
                          key:
                              Platform.isMacOS
                                  ? 'Cmd+Shift+['
                                  : 'Ctrl+Shift+Tab',
                          description: AppLocalizations.keyboardShortcutsItem('previousTab'),
                        ),
                        _ShortcutItem(key: 'Alt+Left', description: AppLocalizations.keyboardShortcutsItem('goBack')),
                        _ShortcutItem(
                          key: 'Alt+Right',
                          description: AppLocalizations.keyboardShortcutsItem('goForward'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+L' : 'Ctrl+L',
                          description: AppLocalizations.keyboardShortcutsItem('focusUrlBar'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+R' : 'Ctrl+R',
                          description: AppLocalizations.keyboardShortcutsItem('reloadPage'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('downloadList'), [
                        _ShortcutItem(
                          key: 'Up / K',
                          description: AppLocalizations.keyboardShortcutsItem('focusPrevItem'),
                        ),
                        _ShortcutItem(
                          key: 'Down / J',
                          description: AppLocalizations.keyboardShortcutsItem('focusNextItem'),
                        ),
                        _ShortcutItem(
                          key: 'Enter',
                          description: AppLocalizations.keyboardShortcutsItem('openDetailPanel'),
                        ),
                        _ShortcutItem(
                          key: 'Space',
                          description: AppLocalizations.keyboardShortcutsItem('toggleSelection'),
                        ),
                        _ShortcutItem(
                          key: 'Esc',
                          description: AppLocalizations.keyboardShortcutsItem('clearSelection'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('dialogs'), [
                        _ShortcutItem(key: 'Esc', description: AppLocalizations.keyboardShortcutsItem('closeDialog')),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+Enter' : 'Ctrl+Enter',
                          description: AppLocalizations.keyboardShortcutsItem('submitForm'),
                        ),
                      ]),
                      const Gap.lg(),
                      _buildSection(context, AppLocalizations.keyboardShortcutsSection('systemShortcuts'), [
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+Q' : 'Ctrl+Q',
                          description: AppLocalizations.keyboardShortcutsItem('quitApp'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+F' : 'Ctrl+F',
                          description: AppLocalizations.keyboardShortcutsItem('focusSearch'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+N' : 'Ctrl+N',
                          description: AppLocalizations.keyboardShortcutsItem('newDownload'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+,' : 'Ctrl+,',
                          description: AppLocalizations.keyboardShortcutsItem('systemSettings'),
                        ),
                        _ShortcutItem(
                          key:
                              Platform.isMacOS ? 'Cmd+Shift+V' : 'Ctrl+Shift+V',
                          description: AppLocalizations.keyboardShortcutsItem('pasteUrl'),
                        ),
                        _ShortcutItem(
                          key:
                              Platform.isMacOS ? 'Cmd+Shift+P' : 'Ctrl+Shift+P',
                          description: AppLocalizations.keyboardShortcutsItem('pauseAllDownloads'),
                        ),
                        _ShortcutItem(
                          key:
                              Platform.isMacOS ? 'Cmd+Shift+R' : 'Ctrl+Shift+R',
                          description: AppLocalizations.keyboardShortcutsItem('resumeAllDownloads'),
                        ),
                        _ShortcutItem(
                          key: Platform.isMacOS ? 'Cmd+P' : 'Ctrl+P',
                          description: AppLocalizations.keyboardShortcutsItem('openPlayer'),
                        ),
                        _ShortcutItem(
                          key:
                              Platform.isMacOS ? 'Cmd+Shift+M' : 'Ctrl+Shift+M',
                          description: AppLocalizations.keyboardShortcutsItem('togglePip'),
                        ),
                        if (Platform.isMacOS) ...[
                          _ShortcutItem(key: 'Cmd+H', description: AppLocalizations.keyboardShortcutsItem('hideApp')),
                          _ShortcutItem(
                            key: 'Cmd+M',
                            description: AppLocalizations.keyboardShortcutsItem('minimizeWindow'),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border(context)),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_ShortcutItem> shortcuts,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface1(context).withValues(alpha: AppOpacity.medium),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: AppColors.accentHighlight,
            ),
          ),
          const Gap.smMd(),
          ...shortcuts.map(
            (shortcut) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 112),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(
                        alpha: AppOpacity.medium,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Text(
                      shortcut.key,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Gap.md(),
                  Expanded(
                    child: Text(
                      shortcut.description,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(
                          alpha: AppOpacity.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutItem {
  final String key;
  final String description;

  _ShortcutItem({required this.key, required this.description});
}
