import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/providers/backend_providers.dart';

/// Feature requests list provider
final featureRequestsProvider =
    FutureProvider.autoDispose<List<FeatureRequestResponse>>((ref) async {
  final service = ref.watch(backendServiceProvider);
  final result = await service.listFeatureRequests();
  return result.when(
    success: (data) => data,
    failure: (e) => throw e,
  );
});
