enum ImportItemStatus {
  queued,
  preloading,
  loaded,
  processing,
  completed,
  failed,
  skipped,
  canceled,
}

class ImportItemState {
  final String id;
  final String path;
  final String filename;
  final ImportItemStatus status;
  final String? error;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? durationMs;
  final String? thumbnailPath;
  final int index;

  const ImportItemState({
    required this.id,
    required this.path,
    required this.filename,
    required this.status,
    required this.error,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    required this.durationMs,
    required this.thumbnailPath,
    required this.index,
  });

  factory ImportItemState.queued({
    required String id,
    required String path,
    required String filename,
    required int index,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    return ImportItemState(
      id: id,
      path: path,
      filename: filename,
      status: ImportItemStatus.queued,
      error: null,
      retryCount: 0,
      createdAt: ts,
      updatedAt: ts,
      durationMs: null,
      thumbnailPath: null,
      index: index,
    );
  }

  ImportItemState copyWith({
    String? id,
    String? path,
    String? filename,
    ImportItemStatus? status,
    String? error,
    bool clearError = false,
    int? retryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? durationMs,
    bool clearDurationMs = false,
    String? thumbnailPath,
    bool clearThumbnailPath = false,
    int? index,
  }) {
    return ImportItemState(
      id: id ?? this.id,
      path: path ?? this.path,
      filename: filename ?? this.filename,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      durationMs: clearDurationMs ? null : (durationMs ?? this.durationMs),
      thumbnailPath: clearThumbnailPath
          ? null
          : (thumbnailPath ?? this.thumbnailPath),
      index: index ?? this.index,
    );
  }
}

class ImportState {
  final int total;
  final int inProgress;
  final int completed;
  final int failed;
  final int skipped;
  final int canceled;
  final Map<String, ImportItemState> items;
  final DateTime updatedAt;
  final bool cancelRequested;

  const ImportState({
    required this.total,
    required this.inProgress,
    required this.completed,
    required this.failed,
    required this.skipped,
    required this.canceled,
    required this.items,
    required this.updatedAt,
    required this.cancelRequested,
  });

  factory ImportState.initial({DateTime? now}) {
    return ImportState(
      total: 0,
      inProgress: 0,
      completed: 0,
      failed: 0,
      skipped: 0,
      canceled: 0,
      items: const {},
      updatedAt: now ?? DateTime.now(),
      cancelRequested: false,
    );
  }

  List<ImportItemState> get orderedItems {
    final list = items.values.toList(growable: false);
    list.sort((a, b) {
      final byIndex = a.index.compareTo(b.index);
      if (byIndex != 0) return byIndex;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  String progressText() {
    if (total == 0) return '0/0';
    int ready = 0;
    int processing = 0;

    for (final item in items.values) {
      switch (item.status) {
        case ImportItemStatus.queued:
        case ImportItemStatus.preloading:
        case ImportItemStatus.loaded:
          ready += 1;
          break;
        case ImportItemStatus.processing:
          processing += 1;
          break;
        case ImportItemStatus.completed:
        case ImportItemStatus.failed:
        case ImportItemStatus.skipped:
        case ImportItemStatus.canceled:
          break;
      }
    }

    return '처리완료 $completed · 처리중 $processing · 준비 $ready · 실패 $failed';
  }

  ImportState copyWith({
    int? total,
    int? inProgress,
    int? completed,
    int? failed,
    int? skipped,
    int? canceled,
    Map<String, ImportItemState>? items,
    DateTime? updatedAt,
    bool? cancelRequested,
  }) {
    return ImportState(
      total: total ?? this.total,
      inProgress: inProgress ?? this.inProgress,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      canceled: canceled ?? this.canceled,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

