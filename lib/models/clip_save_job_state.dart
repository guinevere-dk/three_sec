enum ClipSavePriority { normal, high }

enum ClipSaveJobStatus {
  queued,
  running,
  retrying,
  success,
  failed,
  skipped,
  canceled,
}

enum ClipSaveErrorKind { input, io, permission, codec, unknown }

class ClipSaveJob {
  final String id;
  final String sourcePath;
  final String destinationPath;
  final int durationMs;
  final int startMs;
  final int endMs;
  final ClipSavePriority priority;
  final ClipSaveJobStatus status;
  final int attempts;
  final int maxRetry;
  final DateTime createdAt;
  final String? lastError;
  final ClipSaveErrorKind errorKind;
  final String? sourceVideoId;

  const ClipSaveJob({
    required this.id,
    required this.sourcePath,
    required this.destinationPath,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.priority,
    required this.status,
    required this.attempts,
    required this.maxRetry,
    required this.createdAt,
    required this.lastError,
    required this.errorKind,
    required this.sourceVideoId,
  });

  factory ClipSaveJob.queued({
    required String id,
    required String sourcePath,
    required String destinationPath,
    required int startMs,
    required int endMs,
    required int durationMs,
    ClipSavePriority priority = ClipSavePriority.normal,
    int maxRetry = 2,
    String? sourceVideoId,
    DateTime? now,
  }) {
    return ClipSaveJob(
      id: id,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      durationMs: durationMs,
      startMs: startMs,
      endMs: endMs,
      priority: priority,
      status: ClipSaveJobStatus.queued,
      attempts: 0,
      maxRetry: maxRetry,
      createdAt: now ?? DateTime.now(),
      lastError: null,
      errorKind: ClipSaveErrorKind.unknown,
      sourceVideoId: sourceVideoId,
    );
  }

  ClipSaveJob copyWith({
    String? id,
    String? sourcePath,
    String? destinationPath,
    int? durationMs,
    int? startMs,
    int? endMs,
    ClipSavePriority? priority,
    ClipSaveJobStatus? status,
    int? attempts,
    int? maxRetry,
    DateTime? createdAt,
    String? lastError,
    bool clearLastError = false,
    ClipSaveErrorKind? errorKind,
    String? sourceVideoId,
    bool clearSourceVideoId = false,
  }) {
    return ClipSaveJob(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      destinationPath: destinationPath ?? this.destinationPath,
      durationMs: durationMs ?? this.durationMs,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      maxRetry: maxRetry ?? this.maxRetry,
      createdAt: createdAt ?? this.createdAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      errorKind: errorKind ?? this.errorKind,
      sourceVideoId: clearSourceVideoId
          ? null
          : (sourceVideoId ?? this.sourceVideoId),
    );
  }
}

class ClipSaveJobState {
  final int total;
  final int running;
  final int completed;
  final int failed;
  final int skipped;
  final int canceled;
  final List<ClipSaveJob> queue;
  final List<ClipSaveJob> activeJobs;
  final bool cancelRequested;

  const ClipSaveJobState({
    required this.total,
    required this.running,
    required this.completed,
    required this.failed,
    required this.skipped,
    required this.canceled,
    required this.queue,
    required this.activeJobs,
    required this.cancelRequested,
  });

  factory ClipSaveJobState.initial() {
    return const ClipSaveJobState(
      total: 0,
      running: 0,
      completed: 0,
      failed: 0,
      skipped: 0,
      canceled: 0,
      queue: [],
      activeJobs: [],
      cancelRequested: false,
    );
  }

  String progressText() {
    if (total == 0) return '0/0';
    return '$completed/$total 완료 · 실행중 $running · 실패 $failed · 건너뜀 $skipped · 취소 $canceled';
  }

  bool get hasPendingOrActive => queue.any(
    (job) =>
        job.status == ClipSaveJobStatus.queued ||
        job.status == ClipSaveJobStatus.running ||
        job.status == ClipSaveJobStatus.retrying,
  );

  List<ClipSaveJob> get failedOrSkippedJobs => queue
      .where(
        (job) =>
            job.status == ClipSaveJobStatus.failed ||
            job.status == ClipSaveJobStatus.skipped,
      )
      .toList(growable: false);

  ClipSaveJobState copyWith({
    int? total,
    int? running,
    int? completed,
    int? failed,
    int? skipped,
    int? canceled,
    List<ClipSaveJob>? queue,
    List<ClipSaveJob>? activeJobs,
    bool? cancelRequested,
  }) {
    return ClipSaveJobState(
      total: total ?? this.total,
      running: running ?? this.running,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      canceled: canceled ?? this.canceled,
      queue: queue ?? this.queue,
      activeJobs: activeJobs ?? this.activeJobs,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

enum RecordedClipSaveJobStatus { queued, running, saved, failed }

class RecordedClipSaveJob {
  final String jobId;
  final String sourceStagingPath;
  final String albumName;
  final String aspectPreset;
  final int createdAtMs;
  final RecordedClipSaveJobStatus status;
  final int retryCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  const RecordedClipSaveJob({
    required this.jobId,
    required this.sourceStagingPath,
    required this.albumName,
    required this.aspectPreset,
    required this.createdAtMs,
    required this.status,
    required this.retryCount,
    required this.lastErrorCode,
    required this.lastErrorMessage,
  });

  factory RecordedClipSaveJob.queued({
    required String jobId,
    required String sourceStagingPath,
    required String albumName,
    String aspectPreset = 'r9_16',
    int? createdAtMs,
  }) {
    return RecordedClipSaveJob(
      jobId: jobId,
      sourceStagingPath: sourceStagingPath,
      albumName: albumName,
      aspectPreset: aspectPreset,
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      status: RecordedClipSaveJobStatus.queued,
      retryCount: 0,
      lastErrorCode: null,
      lastErrorMessage: null,
    );
  }

  RecordedClipSaveJob copyWith({
    String? jobId,
    String? sourceStagingPath,
    String? albumName,
    String? aspectPreset,
    int? createdAtMs,
    RecordedClipSaveJobStatus? status,
    int? retryCount,
    String? lastErrorCode,
    String? lastErrorMessage,
    bool clearError = false,
  }) {
    return RecordedClipSaveJob(
      jobId: jobId ?? this.jobId,
      sourceStagingPath: sourceStagingPath ?? this.sourceStagingPath,
      albumName: albumName ?? this.albumName,
      aspectPreset: aspectPreset ?? this.aspectPreset,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastErrorCode: clearError ? null : (lastErrorCode ?? this.lastErrorCode),
      lastErrorMessage: clearError
          ? null
          : (lastErrorMessage ?? this.lastErrorMessage),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'jobId': jobId,
      'sourceStagingPath': sourceStagingPath,
      'albumName': albumName,
      'aspectPreset': aspectPreset,
      'createdAtMs': createdAtMs,
      'status': status.name,
      'retryCount': retryCount,
      'lastErrorCode': lastErrorCode,
      'lastErrorMessage': lastErrorMessage,
    };
  }

  factory RecordedClipSaveJob.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    final status = RecordedClipSaveJobStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => RecordedClipSaveJobStatus.queued,
    );
    return RecordedClipSaveJob(
      jobId: json['jobId'] as String? ?? '',
      sourceStagingPath: json['sourceStagingPath'] as String? ?? '',
      albumName: json['albumName'] as String? ?? '일상',
      aspectPreset: json['aspectPreset'] as String? ?? 'r9_16',
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      status: status,
      retryCount: json['retryCount'] as int? ?? 0,
      lastErrorCode: json['lastErrorCode'] as String?,
      lastErrorMessage: json['lastErrorMessage'] as String?,
    );
  }
}
