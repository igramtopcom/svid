import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/download_path_suggestion_service.dart';

final downloadPathSuggestionServiceProvider =
    Provider<DownloadPathSuggestionService>(
  (ref) => DownloadPathSuggestionService(),
);
