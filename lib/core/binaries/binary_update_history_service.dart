import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'binary_type.dart';
import 'binary_update_error_code.dart';

/// A single binary update attempt record.
class BinaryUpdateRecord {
  final String id;
  final BinaryType binaryType;
  final DateTime timestamp;
  final bool success;
  final String? oldVersion;
  final String? newVersion;
  final BinaryUpdateErrorCode? errorCode;
  final String? errorDetail;

  const BinaryUpdateRecord({
    required this.id,
    required this.binaryType,
    required this.timestamp,
    required this.success,
    this.oldVersion,
    this.newVersion,
    this.errorCode,
    this.errorDetail,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'binaryType': binaryType.name,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
    if (oldVersion != null) 'oldVersion': oldVersion,
    if (newVersion != null) 'newVersion': newVersion,
    if (errorCode != null) 'errorCode': errorCode!.name,
    if (errorDetail != null) 'errorDetail': errorDetail,
  };

  factory BinaryUpdateRecord.fromJson(Map<String, dynamic> json) {
    return BinaryUpdateRecord(
      id: json['id'] as String,
      binaryType: BinaryType.values.firstWhere(
        (t) => t.name == json['binaryType'],
        orElse: () => BinaryType.ytDlp,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
      oldVersion: json['oldVersion'] as String?,
      newVersion: json['newVersion'] as String?,
      errorCode: json['errorCode'] != null
          ? BinaryUpdateErrorCode.values.firstWhere(
              (c) => c.name == json['errorCode'],
              orElse: () => BinaryUpdateErrorCode.unknown,
            )
          : null,
      errorDetail: json['errorDetail'] as String?,
    );
  }
}

/// Persists binary update history in SharedPreferences.
/// Circular buffer of [maxRecords] entries (newest first).
class BinaryUpdateHistoryService {
  static const String storageKey = 'binary_update_history';
  static const int maxRecords = 20;
  static const _uuid = Uuid();

  final SharedPreferences _prefs;

  BinaryUpdateHistoryService(this._prefs);

  /// Add a successful update record.
  void addSuccess({
    required BinaryType binaryType,
    String? oldVersion,
    String? newVersion,
  }) {
    addRecord(BinaryUpdateRecord(
      id: _uuid.v4(),
      binaryType: binaryType,
      timestamp: DateTime.now(),
      success: true,
      oldVersion: oldVersion,
      newVersion: newVersion,
    ));
  }

  /// Add a failed update record.
  void addFailure({
    required BinaryType binaryType,
    required BinaryUpdateErrorCode errorCode,
    String? oldVersion,
    String? errorDetail,
  }) {
    addRecord(BinaryUpdateRecord(
      id: _uuid.v4(),
      binaryType: binaryType,
      timestamp: DateTime.now(),
      success: false,
      oldVersion: oldVersion,
      errorCode: errorCode,
      errorDetail: errorDetail,
    ));
  }

  /// Add a record to the history.
  void addRecord(BinaryUpdateRecord record) {
    final history = getHistory();
    history.insert(0, record);

    // Circular buffer: evict oldest when exceeding max
    final trimmed = history.length > maxRecords
        ? history.sublist(0, maxRecords)
        : history;

    _save(trimmed);
  }

  /// Get all history records (newest first).
  List<BinaryUpdateRecord> getHistory() {
    final json = _prefs.getString(storageKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => BinaryUpdateRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get history filtered by binary type (newest first).
  List<BinaryUpdateRecord> getHistoryForType(BinaryType type) {
    return getHistory().where((r) => r.binaryType == type).toList();
  }

  /// Clear all history.
  void clear() {
    _prefs.remove(storageKey);
  }

  void _save(List<BinaryUpdateRecord> records) {
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    _prefs.setString(storageKey, json);
  }
}
