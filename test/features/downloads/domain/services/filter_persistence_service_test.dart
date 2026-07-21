import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/downloads/domain/services/filter_persistence_service.dart';
import 'package:ssvid/features/downloads/presentation/providers/filter_provider.dart';

void main() {
  late FilterPersistenceService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = FilterPersistenceService(prefs);
  });

  group('FilterPersistenceService — SortOption', () {
    test('getSortOption returns dateNewest by default', () {
      expect(service.getSortOption(), SortOption.dateNewest);
    });

    test('saveSortOption → getSortOption round-trip', () async {
      await service.saveSortOption(SortOption.nameAZ);
      expect(service.getSortOption(), SortOption.nameAZ);
    });

    test('round-trip for sizeLargest', () async {
      await service.saveSortOption(SortOption.sizeLargest);
      expect(service.getSortOption(), SortOption.sizeLargest);
    });

    test('round-trip for uploaderAZ', () async {
      await service.saveSortOption(SortOption.uploaderAZ);
      expect(service.getSortOption(), SortOption.uploaderAZ);
    });

    test('overwrites previous value', () async {
      await service.saveSortOption(SortOption.nameAZ);
      await service.saveSortOption(SortOption.durationLongest);
      expect(service.getSortOption(), SortOption.durationLongest);
    });

    test('unknown stored value falls back to dateNewest', () async {
      SharedPreferences.setMockInitialValues(
          {'downloads_filter_sort_option': 'bogus_value'});
      final prefs = await SharedPreferences.getInstance();
      final s = FilterPersistenceService(prefs);
      expect(s.getSortOption(), SortOption.dateNewest);
    });
  });

  group('FilterPersistenceService — FilterTab', () {
    test('getFilterTab returns FilterTab.all by default', () {
      expect(service.getFilterTab(), FilterTab.all);
    });

    test('saveFilterTab → getFilterTab round-trip', () async {
      await service.saveFilterTab(FilterTab.audio);
      expect(service.getFilterTab(), FilterTab.audio);
    });

    test('round-trip for video', () async {
      await service.saveFilterTab(FilterTab.video);
      expect(service.getFilterTab(), FilterTab.video);
    });

    test('round-trip for image', () async {
      await service.saveFilterTab(FilterTab.image);
      expect(service.getFilterTab(), FilterTab.image);
    });

    test('overwrites previous tab value', () async {
      await service.saveFilterTab(FilterTab.video);
      await service.saveFilterTab(FilterTab.audio);
      expect(service.getFilterTab(), FilterTab.audio);
    });

    test('unknown stored value falls back to FilterTab.all', () async {
      SharedPreferences.setMockInitialValues(
          {'downloads_filter_tab': 'unknown_tab'});
      final prefs = await SharedPreferences.getInstance();
      final s = FilterPersistenceService(prefs);
      expect(s.getFilterTab(), FilterTab.all);
    });
  });
}
