import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';

/// Provider for the global database instance
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();

  // Dispose database when provider is disposed
  ref.onDispose(() {
    database.close();
  });

  return database;
});
