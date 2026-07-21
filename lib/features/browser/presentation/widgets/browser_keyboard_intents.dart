import 'package:flutter/material.dart';

/// Intent for toggling find-in-page bar via keyboard shortcut.
class ToggleFindIntent extends Intent {
  const ToggleFindIntent();
}

/// Intent for opening a new tab.
class NewTabIntent extends Intent {
  const NewTabIntent();
}

/// Intent for focusing the URL bar.
class FocusUrlIntent extends Intent {
  const FocusUrlIntent();
}

/// Intent for reloading the current page.
class ReloadIntent extends Intent {
  const ReloadIntent();
}

/// Intent for toggling fullscreen mode.
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

/// Intent for exiting fullscreen mode.
class ExitFullscreenIntent extends Intent {
  const ExitFullscreenIntent();
}

/// Intent for closing the active browser tab.
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

/// Intent for switching to the next tab.
class NextTabIntent extends Intent {
  const NextTabIntent();
}

/// Intent for switching to the previous tab.
class PrevTabIntent extends Intent {
  const PrevTabIntent();
}

/// Intent for navigating back in the current tab.
class GoBackIntent extends Intent {
  const GoBackIntent();
}

/// Intent for navigating forward in the current tab.
class GoForwardIntent extends Intent {
  const GoForwardIntent();
}
