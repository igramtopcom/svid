import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/smart_queue_service.dart';
import 'downloads_notifier.dart';

final smartQueueServiceProvider = Provider<SmartQueueService>(
  (ref) => SmartQueueService(),
);

/// Reactive provider that computes platform download frequency
/// from completed downloads in current state.
final platformFrequencyProvider = Provider<Map<String, int>>((ref) {
  final state = ref.watch(downloadsNotifierProvider);
  final service = ref.read(smartQueueServiceProvider);
  return service.computePlatformFrequency(state.downloads);
});
