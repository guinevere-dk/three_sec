import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SyncJobEntityType { clip, project }

enum SyncJobAction { upload, download, delete }

class SyncJob {
  final String id;
  final SyncJobEntityType entityType;
  final String entityId;
  final SyncJobAction action;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime createdAt;

  const SyncJob({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.attemptCount,
    required this.createdAt,
    this.nextRetryAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType.name,
        'entityId': entityId,
        'action': action.name,
        'attemptCount': attemptCount,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
        'lastErrorCode': lastErrorCode,
        'lastErrorMessage': lastErrorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    return SyncJob(
      id: json['id'] as String,
      entityType: SyncJobEntityType.values.firstWhere(
        (e) => e.name == (json['entityType'] as String? ?? ''),
        orElse: () => SyncJobEntityType.clip,
      ),
      entityId: json['entityId'] as String? ?? '',
      action: SyncJobAction.values.firstWhere(
        (e) => e.name == (json['action'] as String? ?? ''),
        orElse: () => SyncJobAction.upload,
      ),
      attemptCount: json['attemptCount'] as int? ?? 0,
      nextRetryAt: (json['nextRetryAt'] as String?) != null
          ? DateTime.tryParse(json['nextRetryAt'] as String)
          : null,
      lastErrorCode: json['lastErrorCode'] as String?,
      lastErrorMessage: json['lastErrorMessage'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class SyncQueueStore {
  static const String _key = 'sync_jobs_v1';

  Future<List<SyncJob>> loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => SyncJob.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveJobs(List<SyncJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jobs.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(encoded));
  }
}

