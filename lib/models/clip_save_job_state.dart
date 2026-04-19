enum ClipSavePriority {
  normal,
  high,
}

enum ClipSaveJobStatus {
  queued,
  running,
  retrying,
  success,
  failed,
  skipped,
  canceled,
}

enum ClipSaveErrorKind {
  input,
  io,
  permission,
  codec,
  unknown,
}

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

