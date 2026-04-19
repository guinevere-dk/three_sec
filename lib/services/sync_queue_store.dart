import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SyncJobEntityType { clip, project }

enum SyncJobAction { upload, download, delete }

class SyncJob {
  final String? ownerUid;
  final String id;
  final SyncJobEntityType entityType;
  final String entityId;
  final SyncJobAction action;
  final SyncJobStatus status;
  final String? storagePath;
  final String? projectId;
  final String? localPath;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime createdAt;

  const SyncJob({
    this.ownerUid,
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    this.status = SyncJobStatus.queued,
    this.storagePath,
    this.projectId,
    this.localPath,
    required this.attemptCount,
    required this.createdAt,
    this.nextRetryAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        'id': id,
        'entityType': entityType.name,
        'entityId': entityId,
        'action': action.name,
        'status': status.name,
        'storagePath': storagePath,
        'projectId': projectId,
        'localPath': localPath,
        'attemptCount': attemptCount,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
        'lastErrorCode': lastErrorCode,
        'lastErrorMessage': lastErrorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    return SyncJob(
      ownerUid: json['ownerUid'] as String?,
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
      status: _parseSyncJobStatus(json['status'] as String?),
      storagePath: json['storagePath'] as String?,
      projectId: json['projectId'] as String?,
      localPath: json['localPath'] as String?,
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

enum SyncJobStatus {
  queued,
  inProgress,
  failed,
  completed,
  skipped,
  canceled,
}

SyncJobStatus _parseSyncJobStatus(dynamic rawStatus) {
  final status = (rawStatus as String? ?? '').trim().toLowerCase();
  for (final value in SyncJobStatus.values) {
    if (value.name == status) return value;
  }
  return SyncJobStatus.queued;
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

