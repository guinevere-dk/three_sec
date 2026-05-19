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
    );
  }
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
