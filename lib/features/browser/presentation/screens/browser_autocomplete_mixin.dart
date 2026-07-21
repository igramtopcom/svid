import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/address_bar_autocomplete_service.dart';
import '../providers/browser_tab_providers.dart';
import '../widgets/browser_autocomplete_dropdown.dart';

/// Mixin that provides address bar autocomplete logic for BrowserScreen.
///
/// Extracted from _BrowserScreenState to reduce file size.
mixin BrowserAutocompleteMixin<T extends StatefulWidget> on State<T> {
  // ── Required abstract accessors ──

  WidgetRef get ref;
  TextEditingController get urlControllerForAutocomplete;
  FocusNode get urlFocusNodeForAutocomplete;
  LayerLink get layerLinkForAutocomplete;
  void Function(String url) get onNavigateToUrl;

  // ── State ──

  final autocompleteService = AddressBarAutocompleteService();
  OverlayEntry? autocompleteOverlay;
  List<AutocompleteSuggestion> autocompleteSuggestions = [];
  int selectedSuggestionIndex = -1;

  void onUrlTextChanged() {
    if (!urlFocusNodeForAutocomplete.hasFocus) return;
    updateSuggestions(urlControllerForAutocomplete.text);
  }

  void onUrlFocusChanged() {
    if (!urlFocusNodeForAutocomplete.hasFocus) {
      Future.delayed(
          const Duration(milliseconds: 150), hideAutocompleteOverlay);
    }
  }

  KeyEventResult handleUrlKeyEvent(FocusNode node, KeyEvent event) {
    if (autocompleteOverlay == null || autocompleteSuggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        selectedSuggestionIndex = (selectedSuggestionIndex + 1)
            .clamp(0, autocompleteSuggestions.length - 1);
      });
      autocompleteOverlay!.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        selectedSuggestionIndex = (selectedSuggestionIndex - 1)
            .clamp(-1, autocompleteSuggestions.length - 1);
      });
      autocompleteOverlay!.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (selectedSuggestionIndex >= 0) {
        selectSuggestion(autocompleteSuggestions[selectedSuggestionIndex]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      hideAutocompleteOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void updateSuggestions(String query) {
    final history = ref.read(browserHistoryServiceProvider).entries;
    final bookmarks = ref.read(browserBookmarkServiceProvider).bookmarks;
    final newSuggestions =
        autocompleteService.suggest(query, history, bookmarks);

    if (newSuggestions.isEmpty) {
      hideAutocompleteOverlay();
      return;
    }

    setState(() {
      autocompleteSuggestions = newSuggestions;
      selectedSuggestionIndex = -1;
    });

    if (autocompleteOverlay == null) {
      showAutocompleteOverlay();
    } else {
      autocompleteOverlay!.markNeedsBuild();
    }
  }

  void showAutocompleteOverlay() {
    final overlay = Overlay.of(context);
    autocompleteOverlay = OverlayEntry(
      builder: (_) => BrowserAutocompleteDropdown(
        layerLink: layerLinkForAutocomplete,
        suggestions: autocompleteSuggestions,
        selectedIndex: selectedSuggestionIndex,
        onSelect: selectSuggestion,
      ),
    );
    overlay.insert(autocompleteOverlay!);
  }

  void hideAutocompleteOverlay() {
    autocompleteOverlay?.remove();
    autocompleteOverlay = null;
    autocompleteSuggestions = [];
    selectedSuggestionIndex = -1;
  }

  void selectSuggestion(AutocompleteSuggestion suggestion) {
    hideAutocompleteOverlay();
    urlControllerForAutocomplete.text = suggestion.url;
    urlFocusNodeForAutocomplete.unfocus();
    onNavigateToUrl(suggestion.url);
  }
}
