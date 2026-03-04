import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalIndexEntry {
  final String id;
  final String type; // clip | project
  final String pathOrKey;
  final String? ownerAccountId;
  final String lockState;
  final DateTime updatedAt;

  const LocalIndexEntry({
    required this.id,
    required this.type,
    required this.pathOrKey,
    required this.ownerAccountId,
    required this.lockState,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'pathOrKey': pathOrKey,
        'ownerAccountId': ownerAccountId,
        'lockState': lockState,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LocalIndexEntry.fromJson(Map<String, dynamic> json) {
    return LocalIndexEntry(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'clip',
      pathOrKey: json['pathOrKey'] as String? ?? '',
      ownerAccountId: json['ownerAccountId'] as String?,
      lockState: json['lockState'] as String? ?? 'unlocked',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
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

