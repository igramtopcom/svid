import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/providers/backend_providers.dart';

/// Ticket list provider
final ticketsProvider = FutureProvider.autoDispose<List<TicketListResponse>>((ref) async {
  final service = ref.watch(backendServiceProvider);
  final result = await service.listTickets();
  return result.when(
    success: (data) => data,
    failure: (e) => throw e,
  );
});

/// Ticket detail provider (with messages)
final ticketDetailProvider =
    FutureProvider.autoDispose.family<TicketResponse, String>((ref, ticketId) async {
  final service = ref.watch(backendServiceProvider);
  final result = await service.getTicket(ticketId);
  return result.when(
    success: (data) => data,
    failure: (e) => throw e,
  );
});
