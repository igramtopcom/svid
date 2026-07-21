import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/providers/backend_providers.dart';

/// View mode for the assistant screen
enum AssistantViewMode { welcome, chat, history }

/// Current view mode (welcome / chat / history)
final assistantViewModeProvider = StateProvider<AssistantViewMode>((ref) {
  // Auto-switch to welcome when active chat is cleared
  return AssistantViewMode.welcome;
});

/// Active AI chat session ID (null = show welcome screen)
final activeAiChatProvider = StateProvider<String?>((ref) => null);

/// AI sessions list provider
final aiSessionsProvider = FutureProvider.autoDispose<List<SessionListResponse>>((ref) async {
  final service = ref.watch(backendServiceProvider);
  final result = await service.listAiSessions();
  return result.when(
    success: (data) => data,
    failure: (e) => throw e,
  );
});

/// AI session detail provider (with messages)
final aiSessionDetailProvider =
    FutureProvider.autoDispose.family<SessionResponse, String>((ref, sessionId) async {
  final service = ref.watch(backendServiceProvider);
  final result = await service.getAiSession(sessionId);
  return result.when(
    success: (data) => data,
    failure: (e) => throw e,
  );
});

/// Search query for history filtering
final assistantSearchQueryProvider = StateProvider<String>((ref) => '');

/// Filter for history (all / active / escalated)
enum AssistantHistoryFilter { all, active, escalated }

final assistantHistoryFilterProvider =
    StateProvider<AssistantHistoryFilter>((ref) => AssistantHistoryFilter.all);

/// Selected session in history reading pane
final selectedHistorySessionProvider = StateProvider<String?>((ref) => null);
