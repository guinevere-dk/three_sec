import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalIndexEntry {
  final String id;
  final String type; // clip | project
  final String pathOrKey;
  final String? ownerAccountId;
  final String lockState;
  final DateTime updatedAt;
  final String? cloudVideoId;
  final String? cloudStoragePath;
  final String? cloudStorageTier;
  final String? cloudState;
  final String? cloudFileName;
  final int? cloudFileSize;
  final String? albumName;
  final String? thumbnailStoragePath;
  final String? thumbnailStatus;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final int? durationMs;

  const LocalIndexEntry({
    required this.id,
    required this.type,
    required this.pathOrKey,
    required this.ownerAccountId,
    required this.lockState,
    required this.updatedAt,
    this.cloudVideoId,
    this.cloudStoragePath,
    this.cloudStorageTier,
    this.cloudState,
    this.cloudFileName,
    this.cloudFileSize,
    this.albumName,
    this.thumbnailStoragePath,
    this.thumbnailStatus,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'pathOrKey': pathOrKey,
    'ownerAccountId': ownerAccountId,
    'lockState': lockState,
    'updatedAt': updatedAt.toIso8601String(),
    if (cloudVideoId != null) 'cloudVideoId': cloudVideoId,
    if (cloudStoragePath != null) 'cloudStoragePath': cloudStoragePath,
    if (cloudStorageTier != null) 'cloudStorageTier': cloudStorageTier,
    if (cloudState != null) 'cloudState': cloudState,
    if (cloudFileName != null) 'cloudFileName': cloudFileName,
    if (cloudFileSize != null) 'cloudFileSize': cloudFileSize,
    if (albumName != null) 'albumName': albumName,
    if (thumbnailStoragePath != null)
      'thumbnailStoragePath': thumbnailStoragePath,
    if (thumbnailStatus != null) 'thumbnailStatus': thumbnailStatus,
    if (thumbnailWidth != null) 'thumbnailWidth': thumbnailWidth,
    if (thumbnailHeight != null) 'thumbnailHeight': thumbnailHeight,
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory LocalIndexEntry.fromJson(Map<String, dynamic> json) {
    return LocalIndexEntry(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'clip',
      pathOrKey: json['pathOrKey'] as String? ?? '',
      ownerAccountId: json['ownerAccountId'] as String?,
      lockState: json['lockState'] as String? ?? 'unlocked',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      cloudVideoId: json['cloudVideoId'] as String?,
      cloudStoragePath: json['cloudStoragePath'] as String?,
      cloudStorageTier: json['cloudStorageTier'] as String?,
      cloudState: json['cloudState'] as String?,
      cloudFileName: json['cloudFileName'] as String?,
      cloudFileSize: json['cloudFileSize'] is num
          ? (json['cloudFileSize'] as num).toInt()
          : int.tryParse('${json['cloudFileSize'] ?? ''}'),
      albumName: json['albumName'] as String?,
      thumbnailStoragePath: json['thumbnailStoragePath'] as String?,
      thumbnailStatus: json['thumbnailStatus'] as String?,
      thumbnailWidth: _readNullableInt(json['thumbnailWidth']),
      thumbnailHeight: _readNullableInt(json['thumbnailHeight']),
      durationMs: _readNullableInt(json['durationMs']),
    );
  }
}

int? _readNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

class LocalIndexService {
  static const String _key = 'local_index_entries_v1';

  Future<List<LocalIndexEntry>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => LocalIndexEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEntries(List<LocalIndexEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
