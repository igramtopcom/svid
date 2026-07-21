import 'package:flutter/material.dart';

import '../../data/webview/app_webview.dart';
import '../../domain/services/find_in_page_service.dart';
import '../widgets/find_in_page_bar.dart';

/// Mixin that provides find-in-page logic for BrowserScreen.
///
/// Extracted from _BrowserScreenState to reduce file size.
mixin BrowserFindInPageMixin<T extends StatefulWidget> on State<T> {
  // ── Required abstract accessors ──
  AppWebViewController? get activeControllerForFind;

  // ── Find-in-page state ──
  bool showFindBar = false;
  int findCurrentMatch = 0;
  int findTotalMatches = 0;
  final findInPageService = FindInPageService();
  final findBarKey = GlobalKey<FindInPageBarState>();

  void toggleFindBar() {
    if (showFindBar) {
      closeFindBar();
    } else {
      setState(() => showFindBar = true);
    }
  }

  void closeFindBar() {
    final ctrl = activeControllerForFind;
    if (ctrl != null) {
      ctrl
          .runJavaScript(findInPageService.generateClearScript())
          .catchError((_) {});
    }
    setState(() {
      showFindBar = false;
      findCurrentMatch = 0;
      findTotalMatches = 0;
    });
  }

  Future<void> onFindSearch(String query) async {
    final ctrl = activeControllerForFind;
    if (ctrl == null) return;

    if (query.isEmpty) {
      ctrl
          .runJavaScript(findInPageService.generateClearScript())
          .catchError((_) {});
      setState(() {
        findCurrentMatch = 0;
        findTotalMatches = 0;
      });
      return;
    }

    try {
      final result = await ctrl.runJavaScriptReturningResult(
        findInPageService.generateFindScript(query),
      );
      final count = int.tryParse(result.toString().replaceAll("'", '')) ?? 0;
      if (mounted) {
        setState(() {
          findTotalMatches = count;
          findCurrentMatch = count > 0 ? 0 : 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          findTotalMatches = 0;
          findCurrentMatch = 0;
        });
      }
    }
  }

  Future<void> onFindNext() async {
    if (findTotalMatches <= 0) return;
    final ctrl = activeControllerForFind;
    if (ctrl == null) return;

    try {
      final result = await ctrl.runJavaScriptReturningResult(
        findInPageService.generateNavigateScript(
          currentIndex: findCurrentMatch,
          totalMatches: findTotalMatches,
          forward: true,
        ),
      );
      final idx = int.tryParse(result.toString().replaceAll("'", '')) ?? 0;
      if (mounted) setState(() => findCurrentMatch = idx);
    } catch (_) {}
  }

  Future<void> onFindPrevious() async {
    if (findTotalMatches <= 0) return;
    final ctrl = activeControllerForFind;
    if (ctrl == null) return;

    try {
      final result = await ctrl.runJavaScriptReturningResult(
        findInPageService.generateNavigateScript(
          currentIndex: findCurrentMatch,
          totalMatches: findTotalMatches,
          forward: false,
        ),
      );
      final idx = int.tryParse(result.toString().replaceAll("'", '')) ?? 0;
      if (mounted) setState(() => findCurrentMatch = idx);
    } catch (_) {}
  }
}
