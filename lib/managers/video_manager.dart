import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thum;
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import 'dart:convert';
import 'user_status_manager.dart';
import '../models/vlog_project.dart';
import '../services/cloud_service.dart';
import '../services/auth_service.dart';
import '../services/local_index_service.dart';
import '../constants/clip_policy.dart';
import '../models/clip_save_job_state.dart';
import '../models/import_state.dart';
import '../utils/quality_policy.dart';

enum ClipTransferUiState {
  pendingUpload,
  pendingDownload,
  failedUpload,
  failedDownload,
}

class ImportPreviewData {
  final int? durationMs;
  final String? thumbnailPath;

  const ImportPreviewData({this.durationMs, this.thumbnailPath});
}

class VideoManager extends ChangeNotifier {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();
  static const int trimTimelineThumbCount = 3;
  static const int _timelineThumbMetaVersion = 1;
  static const int importWorkerDefaultConcurrency = 2;
  static const int importThumbnailWorkerDefaultConcurrency = 2;
  static const int clipSaveWorkerDefaultConcurrency = 2;
  static const int clipSaveSerialConcurrency = 1;
  static const int clipSaveMaxRetry = 2;

  static const _rawBaseName = 'raw_clips';
  static const _projectBaseName = 'vlog_projects';
  static const _vlogFoldersBaseName = 'vlog_folders';
  static const _systemClipAlbums = ['일상', '휴지통'];
  static const _systemVlogAlbums = ['기본', '휴지통'];
  static const _cloudSyncedKey = 'cloud_synced_paths';
  static const _clipDurationMetadataKey = 'clip_duration_metadata_v1';
  static const _clipOwnershipMetadataKey = 'clip_ownership_metadata_v1';
  static const _mergeMemoryPressureWindow = Duration(seconds: 30);
  static const int _mergeMemoryPressureGuardClipLimit1080p = 12;
  static const int _mergeMemoryPressureGuardClipLimit4k = 8;
  static const String _vlogMergeAbGroup = String.fromEnvironment(
    'vlog_merge_ab',
    defaultValue: 'A',
  );
  static const List<String> _tutorialSampleAssets = [
    'assets/tutorial/videos/tutorial_clip_capture_day.mp4',
    'assets/tutorial/videos/tutorial_clip_capture_night.mp4',
  ];

  // ✅ 독립된 폴더 시스템
  String currentAlbum = "일상";
  String currentVlogFolder = "";
  List<String> clipAlbums = List.from(_systemClipAlbums);
  List<String> vlogAlbums = List.from(_systemVlogAlbums);
  List<String> recordedVideoPaths = [];
  List<String> vlogProjectPaths = [];
  Set<String> favorites = {};
  final Map<String, Uint8List> thumbnailCache = {};
  Map<String, int> albumCounts = {}; // Public variable for UI
  final Map<String, List<Uint8List>> _timelineCache =
      {}; // Cache for timeline thumbnails
  final Map<String, Duration> _durationCache = {}; // Cache for video durations
  final Map<String, int> _persistedDurationMs = {};
  final Set<String> _cloudSyncedPaths = {};
  final Map<String, ClipTransferUiState> _clipTransferUiStateByPath = {};
  final Map<String, String?> _clipOwnerAccountByPath = {};
  final LocalIndexService _localIndexService = LocalIndexService();
  bool _importCancelRequested = false;
  bool _clipSaveCancelRequested = false;
  bool _clipSaveWorkerRunning = false;
  int _clipSaveWorkerConcurrency = clipSaveSerialConcurrency;
  Completer<void>? _clipSaveDrainCompleter;
  ImportState _importQueueState = ImportState.initial();
  ClipSaveJobState _clipSaveQueueState = ClipSaveJobState.initial();
  final ValueNotifier<ImportState> importQueueStateNotifier = ValueNotifier(
    ImportState.initial(),
  );
  final ValueNotifier<ClipSaveJobState> clipSaveQueueStateNotifier =
      ValueNotifier(ClipSaveJobState.initial());
  bool _isDisposed = false;

  // ✅ 프로젝트 리스트 (Phase 5)
  List<VlogProject> vlogProjects = [];

  bool get importCancelRequested => _importCancelRequested;
  bool get clipSaveCancelRequested => _clipSaveCancelRequested;
  bool get cancelRequested => _importCancelRequested;
  ImportState get importQueueState => _importQueueState;
  ClipSaveJobState get clipSaveQueueState => _clipSaveQueueState;

  DateTime? _lastMemoryPressureAt;
  int _memoryPressureEventCount = 0;

  DateTime? get lastMemoryPressureAt => _lastMemoryPressureAt;
  int get memoryPressureEventCount => _memoryPressureEventCount;
  bool get hasRecentMemoryPressure {
    final at = _lastMemoryPressureAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= _mergeMemoryPressureWindow;
  }

  int? get millisSinceLastMemoryPressure {
    final at = _lastMemoryPressureAt;
    if (at == null) return null;
    return DateTime.now().difference(at).inMilliseconds;
  }

  void recordMemoryPressureEvent() {
    final now = DateTime.now();
    _lastMemoryPressureAt = now;
    _memoryPressureEventCount += 1;
    debugPrint(
      '[VideoManager][MemoryPressure] event_count=$_memoryPressureEventCount '
      'last_at=${now.toIso8601String()}',
    );
  }

  void _warnIfRecentMemoryPressure(
    String stage, {
    required int clipCount,
    String? quality,
  }) {
    final at = _lastMemoryPressureAt;
    if (at == null) return;
    final elapsedMs = DateTime.now().difference(at).inMilliseconds;
    if (elapsedMs > _mergeMemoryPressureWindow.inMilliseconds) return;

    final resolvedQuality = normalizeExportQuality(quality);
    final clipLimit = resolvedQuality == kQuality4k
        ? _mergeMemoryPressureGuardClipLimit4k
        : _mergeMemoryPressureGuardClipLimit1080p;
    final bool exceedsLimit = clipCount > clipLimit;

    debugPrint(
      '[VideoManager][MergeGuard][MemoryPressure] stage=$stage '
      'recently=true clipCount=$clipCount quality=$resolvedQuality '
      'memory_pressure_events=$_memoryPressureEventCount '
      'last_pressure_ms=${DateTime.now().difference(at).inMilliseconds} '
      'warning=advisory',
    );

    if (exceedsLimit) {
      debugPrint(
        '[VideoManager][MergeGuard][MemoryPressure] stage=$stage '
        'clip_limit_warning clipCount=$clipCount limit=$clipLimit '
        'quality=$resolvedQuality (export may be risky)',
      );
    }
  }

  String _resolvedMergeAbGroup() {
    final String value = _vlogMergeAbGroup.trim().toUpperCase();
    return value == 'B' ? 'B' : 'A';
  }

  String _retryPlanForAttempt({
    required int attempt,
    required String abGroup,
    required bool forceRetry,
  }) {
    if (!forceRetry || attempt <= 1) return 'NONE';
    if (abGroup == 'B') {
      return 'QUALITY_AND_AUDIO';
    }
    return 'QUALITY_ONLY';
  }

  String _downgradeQualityForRetry(String quality) {
    if (quality == kQuality4k) return kQuality1080p;
    if (quality == kQuality1080p) return kQuality720p;
    return quality;
  }

  bool _isMergeRetryAllowed(
    Map<String, String> normalizedFailure,
    bool isForceStopped,
  ) {
    if (isForceStopped) return false;
    final normalizedFailCode = normalizedFailure['normalizedFailCode'];
    return normalizedFailCode == 'ASSET_LOADER' ||
        normalizedFailCode == 'ENCODER_ERROR';
  }

  void requestCancelAllQueues() {
    _importCancelRequested = true;
    _clipSaveCancelRequested = true;
    _importQueueState = _importQueueState.copyWith(
      cancelRequested: true,
      updatedAt: DateTime.now(),
    );
    _clipSaveQueueState = _clipSaveQueueState.copyWith(cancelRequested: true);
    _markRemainingClipSaveJobsCanceled();
    _emitQueueStateChanged();
  }

  void clearCancelAllQueues() {
    _importCancelRequested = false;
    _clipSaveCancelRequested = false;
    _importQueueState = _importQueueState.copyWith(
      cancelRequested: false,
      updatedAt: DateTime.now(),
    );
    _clipSaveQueueState = _clipSaveQueueState.copyWith(cancelRequested: false);
    _emitQueueStateChanged();
  }

  void requestCancelImportQueue() {
    _importCancelRequested = true;
    _importQueueState = _importQueueState.copyWith(
      cancelRequested: true,
      updatedAt: DateTime.now(),
    );
    _emitQueueStateChanged();
  }

  void clearCancelImportQueue() {
    _importCancelRequested = false;
    _importQueueState = _importQueueState.copyWith(
      cancelRequested: false,
      updatedAt: DateTime.now(),
    );
    _emitQueueStateChanged();
  }

  void requestCancelClipSaveQueue() {
    _clipSaveCancelRequested = true;
    _clipSaveQueueState = _clipSaveQueueState.copyWith(cancelRequested: true);
    _markRemainingClipSaveJobsCanceled();
    _emitQueueStateChanged();
  }

  void clearCancelClipSaveQueue() {
    _clipSaveCancelRequested = false;
    _clipSaveQueueState = _clipSaveQueueState.copyWith(cancelRequested: false);
    _emitQueueStateChanged();
  }

  void initializeImportQueue(List<ImportItemState> items) {
    final map = <String, ImportItemState>{
      for (final item in items) item.id: item,
    };
    _importCancelRequested = false;
    _importQueueState = _rebuildImportState(
      items: map,
      cancelRequested: false,
      updatedAt: DateTime.now(),
    );
    _emitQueueStateChanged();
  }

  void upsertImportItem(ImportItemState item) {
    final next = Map<String, ImportItemState>.from(_importQueueState.items);
    next[item.id] = item;
    _importQueueState = _rebuildImportState(
      items: next,
      cancelRequested: _importQueueState.cancelRequested,
      updatedAt: DateTime.now(),
    );
    _emitQueueStateChanged();
  }

  void markItemProcessing(String itemId) {
    _updateImportItemStatus(itemId, status: ImportItemStatus.processing);
  }

  void markItemPreloading(String itemId) {
    _updateImportItemStatus(itemId, status: ImportItemStatus.preloading);
  }

  void markItemLoaded(String itemId, {int? durationMs, String? thumbnailPath}) {
    _updateImportItemStatus(
      itemId,
      status: ImportItemStatus.loaded,
      durationMs: durationMs,
      thumbnailPath: thumbnailPath,
      clearError: true,
    );
  }

  void markItemSkipped(String itemId, {String? error}) {
    _updateImportItemStatus(
      itemId,
      status: ImportItemStatus.skipped,
      error: error,
    );
  }

  void markItemCanceled(String itemId, {String? error}) {
    _updateImportItemStatus(
      itemId,
      status: ImportItemStatus.canceled,
      error: error,
    );
  }

  void markItemFailed(
    String itemId, {
    String? error,
    bool incrementRetry = true,
  }) {
    _updateImportItemStatus(
      itemId,
      status: ImportItemStatus.failed,
      error: error,
      incrementRetry: incrementRetry,
    );
  }

  void markItemCompleted(
    String itemId, {
    int? durationMs,
    String? thumbnailPath,
  }) {
    _updateImportItemStatus(
      itemId,
      status: ImportItemStatus.completed,
      durationMs: durationMs,
      thumbnailPath: thumbnailPath,
      clearError: true,
    );
  }

  void markRemainingImportItemsCanceled() {
    _importCancelRequested = true;
    final now = DateTime.now();
    final next = Map<String, ImportItemState>.from(_importQueueState.items);
    var changed = false;
    for (final entry in next.entries) {
      final item = entry.value;
      if (item.status == ImportItemStatus.completed ||
          item.status == ImportItemStatus.failed ||
          item.status == ImportItemStatus.canceled ||
          item.status == ImportItemStatus.skipped) {
        continue;
      }
      next[entry.key] = item.copyWith(
        status: ImportItemStatus.canceled,
        error: 'cancel_requested',
        updatedAt: now,
      );
      changed = true;
    }
    if (!changed) return;
    _importQueueState = _rebuildImportState(
      items: next,
      cancelRequested: true,
      updatedAt: now,
    );
    _emitQueueStateChanged();
  }

  void initializeClipSaveQueue(List<ClipSaveJob> jobs) {
    final sorted = _sortClipSaveJobs(jobs);
    _clipSaveCancelRequested = false;
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: sorted,
      activeJobs: const [],
      cancelRequested: false,
    );
    _emitQueueStateChanged();
  }

  void enqueueClipSaveJobs(
    List<ClipSaveJob> jobs, {
    int concurrency = clipSaveSerialConcurrency,
  }) {
    if (jobs.isEmpty) return;
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue)
      ..addAll(jobs.map((job) => job.copyWith(maxRetry: clipSaveMaxRetry)));
    _clipSaveCancelRequested = false;
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: _sortClipSaveJobs(nextQueue),
      activeJobs: _clipSaveQueueState.activeJobs,
      cancelRequested: false,
    );
    _emitQueueStateChanged();
    unawaited(startClipSaveQueueWorker(concurrency: concurrency));
  }

  Future<void> startClipSaveQueueWorker({
    int concurrency = clipSaveSerialConcurrency,
  }) async {
    final effectiveConcurrency = concurrency.clamp(
      clipSaveSerialConcurrency,
      clipSaveWorkerDefaultConcurrency,
    );
    _clipSaveWorkerConcurrency = effectiveConcurrency;

    if (_clipSaveWorkerRunning) {
      return _clipSaveDrainCompleter?.future ?? Future.value();
    }

    _clipSaveWorkerRunning = true;
    _clipSaveDrainCompleter = Completer<void>();

    final runners = <Future<void>>[];
    for (var i = 0; i < _clipSaveWorkerConcurrency; i++) {
      runners.add(_clipSaveWorkerLoop());
    }

    await Future.wait(runners);
    _clipSaveWorkerRunning = false;
    if (!(_clipSaveDrainCompleter?.isCompleted ?? true)) {
      _clipSaveDrainCompleter?.complete();
    }
  }

  Future<void> _clipSaveWorkerLoop() async {
    while (true) {
      if (_clipSaveCancelRequested || _clipSaveQueueState.cancelRequested) {
        _markRemainingClipSaveJobsCanceled();
        return;
      }

      final nextJob = _dequeueNextRunnableClipSaveJob();
      if (nextJob == null) {
        return;
      }

      await _runClipSaveJobWithRetry(nextJob);
    }
  }

  ClipSaveJob? _dequeueNextRunnableClipSaveJob() {
    final queue = _clipSaveQueueState.queue;
    for (final job in queue) {
      if (job.status == ClipSaveJobStatus.queued ||
          job.status == ClipSaveJobStatus.retrying) {
        markClipSaveJobRunning(job.id);
        return _clipSaveQueueState.queue.firstWhere((e) => e.id == job.id);
      }
    }
    return null;
  }

  Future<void> _runClipSaveJobWithRetry(ClipSaveJob job) async {
    while (true) {
      if (_clipSaveCancelRequested || _clipSaveQueueState.cancelRequested) {
        markClipSaveJobCanceled(job.id, error: 'cancel_requested');
        await releaseClipSaveResourcesForJob(
          job,
          status: ClipSaveJobStatus.canceled,
        );
        return;
      }

      final current = _clipSaveQueueState.queue.firstWhere(
        (e) => e.id == job.id,
        orElse: () => job,
      );

      final targetAlbum = _resolveTargetAlbumFromJob(current);
      try {
        await saveExtractedClip(current.sourcePath, targetAlbum);
        markClipSaveJobSuccess(current.id);
        await releaseClipSaveResourcesForJob(
          current,
          status: ClipSaveJobStatus.success,
        );
        return;
      } catch (e) {
        final nextAttempts = current.attempts + 1;
        final errorMessage = '$e';
        final errorKind = classifyClipSaveError(errorMessage);

        if (nextAttempts <= current.maxRetry) {
          _setClipSaveJobRetrying(
            current.id,
            error: errorMessage,
            errorKind: errorKind,
          );
          await Future.delayed(const Duration(milliseconds: 250));
          continue;
        }

        markClipSaveJobFailed(
          current.id,
          error: errorMessage,
          errorKind: errorKind,
        );
        await releaseClipSaveResourcesForJob(
          current,
          status: ClipSaveJobStatus.failed,
        );
        return;
      }
    }
  }

  void retryClipSaveJob(String jobId) {
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue);
    final idx = nextQueue.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    final job = nextQueue[idx];
    if (job.status != ClipSaveJobStatus.failed &&
        job.status != ClipSaveJobStatus.skipped &&
        job.status != ClipSaveJobStatus.canceled) {
      return;
    }
    _clipSaveCancelRequested = false;
    nextQueue[idx] = job.copyWith(
      status: ClipSaveJobStatus.queued,
      attempts: 0,
      clearLastError: true,
      errorKind: ClipSaveErrorKind.unknown,
    );
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: _sortClipSaveJobs(nextQueue),
      activeJobs: _clipSaveQueueState.activeJobs,
      cancelRequested: false,
    );
    _emitQueueStateChanged();
    unawaited(
      startClipSaveQueueWorker(concurrency: _clipSaveWorkerConcurrency),
    );
  }

  void retryFailedClipSaveJobs() {
    final targetIds = _clipSaveQueueState.queue
        .where(
          (job) =>
              job.status == ClipSaveJobStatus.failed ||
              job.status == ClipSaveJobStatus.skipped ||
              job.status == ClipSaveJobStatus.canceled,
        )
        .map((job) => job.id)
        .toList(growable: false);
    for (final id in targetIds) {
      retryClipSaveJob(id);
    }
  }

  ClipSaveErrorKind classifyClipSaveError(String errorMessage) {
    final lowered = errorMessage.toLowerCase();
    if (lowered.contains('permission') ||
        lowered.contains('denied') ||
        lowered.contains('권한')) {
      return ClipSaveErrorKind.permission;
    }
    if (lowered.contains('codec') ||
        lowered.contains('ffmpeg') ||
        lowered.contains('format') ||
        lowered.contains('decode') ||
        lowered.contains('encode')) {
      return ClipSaveErrorKind.codec;
    }
    if (lowered.contains('input') ||
        lowered.contains('source') ||
        lowered.contains('not found') ||
        lowered.contains('no such file')) {
      return ClipSaveErrorKind.input;
    }
    if (lowered.contains('io') ||
        lowered.contains('disk') ||
        lowered.contains('storage') ||
        lowered.contains('space') ||
        lowered.contains('write') ||
        lowered.contains('read')) {
      return ClipSaveErrorKind.io;
    }
    return ClipSaveErrorKind.unknown;
  }

  Future<void> releaseClipSaveResourcesForJob(
    ClipSaveJob job, {
    required ClipSaveJobStatus status,
  }) async {
    releaseImportPreparationResourcesForPath(job.sourcePath);
    if (status == ClipSaveJobStatus.success) {
      try {
        final file = File(job.sourcePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 임시 파일 삭제 실패는 저장 결과에 영향 없으므로 무시
      }
    }
  }

  void _setClipSaveJobRetrying(
    String jobId, {
    String? error,
    ClipSaveErrorKind errorKind = ClipSaveErrorKind.unknown,
  }) {
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue);
    final idx = nextQueue.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    final current = nextQueue[idx];
    nextQueue[idx] = current.copyWith(
      status: ClipSaveJobStatus.retrying,
      attempts: current.attempts + 1,
      lastError: error,
      errorKind: errorKind,
    );
    final nextActive = List<ClipSaveJob>.from(_clipSaveQueueState.activeJobs)
      ..removeWhere((j) => j.id == jobId);
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: nextQueue,
      activeJobs: nextActive,
      cancelRequested: _clipSaveQueueState.cancelRequested,
    );
    _emitQueueStateChanged();
  }

  void _markRemainingClipSaveJobsCanceled() {
    _clipSaveCancelRequested = true;
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue);
    var changed = false;
    for (var i = 0; i < nextQueue.length; i++) {
      final job = nextQueue[i];
      if (job.status == ClipSaveJobStatus.success ||
          job.status == ClipSaveJobStatus.failed ||
          job.status == ClipSaveJobStatus.skipped ||
          job.status == ClipSaveJobStatus.canceled) {
        continue;
      }
      nextQueue[i] = job.copyWith(
        status: ClipSaveJobStatus.canceled,
        lastError: 'cancel_requested',
      );
      changed = true;
    }
    if (!changed) return;
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: nextQueue,
      activeJobs: const [],
      cancelRequested: true,
    );
    _emitQueueStateChanged();
  }

  String _resolveTargetAlbumFromJob(ClipSaveJob job) {
    final parts = p.split(job.destinationPath);
    if (parts.isNotEmpty && parts.first.trim().isNotEmpty) {
      return parts.first;
    }
    return currentAlbum;
  }

  List<ClipSaveJob> _sortClipSaveJobs(List<ClipSaveJob> jobs) {
    final sorted = List<ClipSaveJob>.from(jobs)
      ..sort((a, b) {
        final p0 = b.priority.index.compareTo(a.priority.index);
        if (p0 != 0) return p0;
        return a.createdAt.compareTo(b.createdAt);
      });
    return sorted;
  }

  void markClipSaveJobRunning(String jobId) {
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue);
    final nextActive = List<ClipSaveJob>.from(_clipSaveQueueState.activeJobs);
    final idx = nextQueue.indexWhere((j) => j.id == jobId);
    if (idx != -1) {
      final runningJob = nextQueue[idx].copyWith(
        status: ClipSaveJobStatus.running,
      );
      nextQueue[idx] = runningJob;
      if (!nextActive.any((j) => j.id == jobId)) {
        nextActive.add(runningJob);
      }
      _clipSaveQueueState = _rebuildClipSaveState(
        queue: nextQueue,
        activeJobs: nextActive,
        cancelRequested: _clipSaveQueueState.cancelRequested,
      );
      _emitQueueStateChanged();
    }
  }

  void markClipSaveJobSuccess(String jobId) {
    _completeClipSaveJob(jobId, status: ClipSaveJobStatus.success);
  }

  void markClipSaveJobSkipped(String jobId, {String? error}) {
    _completeClipSaveJob(
      jobId,
      status: ClipSaveJobStatus.skipped,
      error: error,
    );
  }

  void markClipSaveJobCanceled(String jobId, {String? error}) {
    _completeClipSaveJob(
      jobId,
      status: ClipSaveJobStatus.canceled,
      error: error,
    );
  }

  void markClipSaveJobFailed(
    String jobId, {
    String? error,
    ClipSaveErrorKind errorKind = ClipSaveErrorKind.unknown,
  }) {
    _completeClipSaveJob(
      jobId,
      status: ClipSaveJobStatus.failed,
      error: error,
      errorKind: errorKind,
      incrementAttempts: true,
    );
  }

  void _updateImportItemStatus(
    String itemId, {
    required ImportItemStatus status,
    String? error,
    bool clearError = false,
    bool incrementRetry = false,
    int? durationMs,
    String? thumbnailPath,
  }) {
    final current = _importQueueState.items[itemId];
    if (current == null) return;
    final now = DateTime.now();
    final nextItems = Map<String, ImportItemState>.from(
      _importQueueState.items,
    );
    nextItems[itemId] = current.copyWith(
      status: status,
      error: error,
      clearError: clearError,
      retryCount: incrementRetry ? current.retryCount + 1 : current.retryCount,
      durationMs: durationMs,
      thumbnailPath: thumbnailPath,
      updatedAt: now,
    );
    _importQueueState = _rebuildImportState(
      items: nextItems,
      cancelRequested: _importQueueState.cancelRequested,
      updatedAt: now,
    );
    _emitQueueStateChanged();
  }

  void _completeClipSaveJob(
    String jobId, {
    required ClipSaveJobStatus status,
    String? error,
    ClipSaveErrorKind errorKind = ClipSaveErrorKind.unknown,
    bool incrementAttempts = false,
  }) {
    final nextQueue = List<ClipSaveJob>.from(_clipSaveQueueState.queue);
    final idx = nextQueue.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    final current = nextQueue[idx];
    nextQueue[idx] = current.copyWith(
      status: status,
      lastError: error,
      clearLastError: error == null,
      errorKind: errorKind,
      attempts: incrementAttempts ? current.attempts + 1 : current.attempts,
    );
    final nextActive = List<ClipSaveJob>.from(_clipSaveQueueState.activeJobs)
      ..removeWhere((j) => j.id == jobId);
    _clipSaveQueueState = _rebuildClipSaveState(
      queue: nextQueue,
      activeJobs: nextActive,
      cancelRequested: _clipSaveQueueState.cancelRequested,
    );
    _emitQueueStateChanged();
  }

  ImportState _rebuildImportState({
    required Map<String, ImportItemState> items,
    required bool cancelRequested,
    required DateTime updatedAt,
  }) {
    var inProgress = 0;
    var completed = 0;
    var failed = 0;
    var skipped = 0;
    var canceled = 0;
    for (final item in items.values) {
      switch (item.status) {
        case ImportItemStatus.completed:
          completed++;
          break;
        case ImportItemStatus.failed:
          failed++;
          break;
        case ImportItemStatus.skipped:
          skipped++;
          break;
        case ImportItemStatus.canceled:
          canceled++;
          break;
        case ImportItemStatus.queued:
        case ImportItemStatus.preloading:
        case ImportItemStatus.loaded:
        case ImportItemStatus.processing:
          inProgress++;
          break;
      }
    }
    return ImportState(
      total: items.length,
      inProgress: inProgress,
      completed: completed,
      failed: failed,
      skipped: skipped,
      canceled: canceled,
      items: Map<String, ImportItemState>.unmodifiable(items),
      updatedAt: updatedAt,
      cancelRequested: cancelRequested,
    );
  }

  ClipSaveJobState _rebuildClipSaveState({
    required List<ClipSaveJob> queue,
    required List<ClipSaveJob> activeJobs,
    required bool cancelRequested,
  }) {
    var running = 0;
    var completed = 0;
    var failed = 0;
    var skipped = 0;
    var canceled = 0;
    for (final job in queue) {
      switch (job.status) {
        case ClipSaveJobStatus.queued:
          break;
        case ClipSaveJobStatus.running:
        case ClipSaveJobStatus.retrying:
          running++;
          break;
        case ClipSaveJobStatus.success:
          completed++;
          break;
        case ClipSaveJobStatus.failed:
          failed++;
          break;
        case ClipSaveJobStatus.skipped:
          skipped++;
          break;
        case ClipSaveJobStatus.canceled:
          canceled++;
          break;
      }
    }
    return ClipSaveJobState(
      total: queue.length,
      running: running,
      completed: completed,
      failed: failed,
      skipped: skipped,
      canceled: canceled,
      queue: List<ClipSaveJob>.unmodifiable(queue),
      activeJobs: List<ClipSaveJob>.unmodifiable(activeJobs),
      cancelRequested: cancelRequested,
    );
  }

  void _emitQueueStateChanged() {
    if (_isDisposed) return;
    importQueueStateNotifier.value = _importQueueState;
    clipSaveQueueStateNotifier.value = _clipSaveQueueState;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    importQueueStateNotifier.dispose();
    clipSaveQueueStateNotifier.dispose();
    super.dispose();
  }

  // 앱 시작 시 호출 (initAlbumSystem 등에서 호출)
  Future<void> loadProjects() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));

      if (!await projectDir.exists()) {
        await projectDir.create(recursive: true);
        vlogProjects = [];
      } else {
        // .json 파일 모두 읽기
        final files = projectDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.json'),
        );

        vlogProjects = files
            .map((file) {
              try {
                final jsonStr = file.readAsStringSync();
                return VlogProject.fromJson(jsonDecode(jsonStr));
              } catch (e) {
                print("Error parsing project: ${file.path}");
                return null;
              }
            })
            .whereType<VlogProject>()
            .toList();

        // 최신순 정렬
        vlogProjects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }

      await _hydrateProjectCloudMetadata();
      notifyListeners();
    } catch (e) {
      print("Error loading projects: $e");
    }
  }

  Future<void> _hydrateProjectCloudMetadata() async {
    if (AuthService().isGuest) {
      return;
    }

    final cloudMap = await CloudService().getUserVlogProjectMetadataMap();
    if (cloudMap.isEmpty) return;

    bool changed = false;
    vlogProjects = vlogProjects.map((project) {
      final cloud = cloudMap[project.id];
      if (cloud == null) return project;

      final bool sameId = project.cloudProjectId == cloud.projectId;
      final bool sameTime = project.cloudSyncedAt == cloud.lastSyncedAt;
      if (sameId && sameTime) return project;

      changed = true;
      return project.copyWith(
        cloudProjectId: cloud.projectId,
        cloudSyncedAt: cloud.lastSyncedAt,
        updatedAt: project.updatedAt,
      );
    }).toList();

    if (!changed) return;

    for (final project in vlogProjects) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));
        if (!await projectDir.exists()) {
          await projectDir.create(recursive: true);
        }
        final file = File(p.join(projectDir.path, '${project.id}.json'));
        await file.writeAsString(jsonEncode(project.toJson()));
      } catch (_) {
        // 로컬 보정 저장 실패는 무시하고 UI 반영 우선
      }
    }
  }

  // 현재 폴더에 맞는 프로젝트 필터링
  List<VlogProject> get filteredProjects {
    if (currentVlogFolder == '휴지통') {
      return vlogProjects.where((p) => p.folderName == '휴지통').toList();
    }
    // 휴지통이 아닌 경우: 해당 폴더인 것만 (단, '기본'의 경우 null도 포괄 가능하지만, 모델 기본값이 '기본'이므로 일치 비교)
    // 폴더 이동 시 '휴지통'으로 보내지 않은 프로젝트만 보여야 함 (휴지통 기능이 폴더 필드로 통합됨)
    // 만약 currentVlogFolder가 비어있으면(전체보기?) -> 요구사항은 currentVlogFolder 사용
    if (currentVlogFolder.isEmpty)
      return vlogProjects
          .where((p) => p.folderName != '휴지통')
          .toList(); // Fallback

    return vlogProjects
        .where((p) => p.folderName == currentVlogFolder)
        .toList();
  }

  // 프로젝트 폴더 이동
  Future<void> moveProjectToFolder(
    VlogProject project,
    String targetFolder,
  ) async {
    final updatedProject = project.copyWith(
      folderName: targetFolder,
      trashedFromFolderName: null,
    );
    await saveProject(updatedProject);
    notifyListeners();
  }

  Future<void> restoreProjectFromTrash(VlogProject project) async {
    final base = await _vlogFoldersBaseDir();
    final origin = project.trashedFromFolderName?.trim();
    String targetFolder = '기본';

    if (origin != null &&
        origin.isNotEmpty &&
        origin != '휴지통' &&
        origin != '일상') {
      final originDir = Directory(p.join(base.path, origin));
      if (await originDir.exists()) {
        targetFolder = origin;
      }
    }

    final restoredProject = project.copyWith(
      folderName: targetFolder,
      trashedFromFolderName: null,
    );
    await saveProject(restoredProject);
    notifyListeners();
  }

  Future<void> copyProjectToFolder(
    VlogProject project,
    String targetFolder,
  ) async {
    final timestamp = DateTime.now();
    final copiedProject = VlogProject(
      id: '${timestamp.microsecondsSinceEpoch}_${project.id.hashCode}',
      title: '${project.title} (Copy)',
      clips: project.clips
          .map(
            (clip) => clip.copyWith(
              id: '${timestamp.microsecondsSinceEpoch}_${clip.id.hashCode}',
            ),
          )
          .toList(),
      audioConfig: Map<String, double>.from(project.audioConfig),
      bgmPath: project.bgmPath,
      bgmVolume: project.bgmVolume,
      quality: project.quality,
      isFavorite: project.isFavorite,
      folderName: targetFolder,
      ownerAccountId: project.ownerAccountId,
      lockState: project.lockState,
      trashedFromFolderName: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    vlogProjects.insert(0, copiedProject);
    await saveProject(copiedProject);
    notifyListeners();
  }

  // 새 프로젝트 생성
  Future<VlogProject> createProject(
    List<String> videoPaths, {
    void Function(int current, int total, String path)? onClipPrepared,
  }) async {
    final timestamp = DateTime.now();
    final ownerUid = UserStatusManager().userId;
    // 현재 폴더가 휴지통이면 '기본'으로 생성, 아니면 현재 폴더 사용
    final folder = (currentVlogFolder == '휴지통' || currentVlogFolder.isEmpty)
        ? '기본'
        : currentVlogFolder;

    // Create initial clips from paths
    final clips = videoPaths.map((path) => VlogClip(path: path)).toList();

    _warnIfRecentMemoryPressure(
      'createProject',
      clipCount: clips.length,
      quality: null,
    );

    // Pre-cache durations for all clips (so edit screen doesn't need temp controllers)
    int failedClipPrecacheCount = 0;
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final int clipIndex = i + 1;
      final Stopwatch clipStopwatch = Stopwatch()..start();
      debugPrint(
        '[VideoManager][CreateProject][Clip] start '
        'clipIndex=$clipIndex totalClips=${clips.length} path=${clip.path}',
      );

      try {
        final clipDurationStartMs = DateTime.now().millisecondsSinceEpoch;
        final duration = await getVideoDuration(clip.path);
        final int durationMs = duration.inMilliseconds;
        clip.originalDuration = duration; // Store original duration
        debugPrint(
          '[VideoManager][CreateProject][Clip] duration_done '
          'clipIndex=$clipIndex path=${clip.path} '
          'durationMs=$durationMs startMs=$clipDurationStartMs '
          'elapsedMs=${DateTime.now().millisecondsSinceEpoch - clipDurationStartMs}',
        );

        if (clip.endTime == Duration.zero) {
          clip.endTime = duration;
        }

        if (duration > Duration.zero) {
          final Stopwatch thumbStopwatch = Stopwatch()..start();
          final bool thumbUpdated =
              await ensureTimelineThumbnailMetadataForClip(
                clip,
                durationMs: duration.inMilliseconds,
                count: trimTimelineThumbCount,
              );
          final thumbElapsed = thumbStopwatch.elapsedMilliseconds;
          debugPrint(
            '[VideoManager][CreateProject][Clip] thumbnail_done '
            'clipIndex=$clipIndex path=${clip.path} '
            'durationMs=$durationMs thumbUpdated=$thumbUpdated '
            'thumbElapsedMs=$thumbElapsed',
          );
        } else {
          failedClipPrecacheCount++;
          debugPrint(
            '[VideoManager][CreateProject][Clip] duration_zero clipIndex=$clipIndex '
            'path=${clip.path}',
          );
        }
      } catch (e) {
        failedClipPrecacheCount++;
        debugPrint(
          '[VideoManager][CreateProject][Clip] failure '
          'clipIndex=$clipIndex path=${clip.path} '
          'type=${e.runtimeType} message=$e',
        );
      }

      final clipElapsedMs = clipStopwatch.elapsedMilliseconds;
      final int durationMs = clip.originalDuration.inMilliseconds;
      debugPrint(
        '[VideoManager][CreateProject][Clip] end '
        'clipIndex=$clipIndex path=${clip.path} '
        'durationMs=$durationMs '
        'totalElapsedMs=$clipElapsedMs',
      );

      onClipPrepared?.call(clipIndex, clips.length, clip.path);
      debugPrint(
        '[VideoManager][CreateProject][Progress] '
        'current=$clipIndex total=${clips.length} path=${clip.path}',
      );
    }

    if (failedClipPrecacheCount > 0) {
      debugPrint(
        '[VideoManager][CreateProject] failedClipPrecacheCount=$failedClipPrecacheCount '
        'totalClips=${clips.length}',
      );
    }
    debugPrint(
      '[VideoManager] Pre-cached durations for ${clips.length} clips '
      'failedClipPrecacheCount=$failedClipPrecacheCount',
    );

    final newProject = VlogProject(
      id: timestamp.millisecondsSinceEpoch.toString(),
      title: "Vlog_${timestamp.year}${timestamp.month}${timestamp.day}",
      clips: clips, // Use clips instead of videoPaths
      folderName: folder,
      ownerAccountId: ownerUid,
      lockState: 'unlocked',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    vlogProjects.insert(0, newProject); // 리스트 맨 앞에 추가
    await saveProject(newProject);
    notifyListeners();
    return newProject;
  }

  // 프로젝트 저장 (파일 덮어쓰기)
  Future<void> saveProject(VlogProject project) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory(p.join(appDir.path, 'vlog_projects'));
      if (!await projectDir.exists()) await projectDir.create(recursive: true);

      var projectToSave = project;

      final cloudMeta = AuthService().isGuest
          ? null
          : await CloudService().upsertVlogProjectMetadata(project);
      if (cloudMeta != null) {
        projectToSave = project.copyWith(
          cloudProjectId: cloudMeta.projectId,
          cloudSyncedAt: cloudMeta.lastSyncedAt,
          updatedAt: project.updatedAt,
        );
      }

      final file = File(p.join(projectDir.path, '${project.id}.json'));
      await file.writeAsString(jsonEncode(projectToSave.toJson()));

      // 리스트 내 상태 업데이트 (필요 시)
      final index = vlogProjects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        vlogProjects[index] = projectToSave;
      }

      await _upsertLocalIndexProject(projectToSave);
    } catch (e) {
      print("Error saving project: $e");
    }
  }

  // 프로젝트 삭제
  Future<void> deleteProject(String id) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(appDir.path, 'vlog_projects', '$id.json'));

      VlogProject? target;
      for (final p in vlogProjects) {
        if (p.id == id) {
          target = p;
          break;
        }
      }
      if (!AuthService().isGuest) {
        await CloudService().deleteVlogProjectMetadata(
          localProjectId: id,
          cloudProjectId: target?.cloudProjectId,
        );
      }

      if (await file.exists()) {
        await file.delete();
      }

      vlogProjects.removeWhere((p) => p.id == id);
      await _removeLocalIndexByKey(id);
      notifyListeners();
    } catch (e) {
      print("Error deleting project: $e");
    }
  }

  static const platform = MethodChannel('com.dk.three_sec/video_engine');
  static const int _targetRecordingDurationMs = kTargetClipMs;
  static const String _recordingTrimMode = 'center';

  void _logChannelGuardFail({
    required String step,
    required String platformError,
    required String message,
  }) {
    debugPrint(
      '[VideoManager][Channel][GuardFail] '
      'step=$step platformError=$platformError message=$message',
    );
  }

  void _logChannelCallFail({
    required String step,
    required String platformError,
    required String message,
  }) {
    debugPrint(
      '[VideoManager][Channel][CallFail] '
      'step=$step platformError=$platformError message=$message',
    );
  }

  Future<Directory> _docDir() async => await getApplicationDocumentsDirectory();

  Future<Directory> _rawBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _rawBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _projectBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _projectBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _vlogFoldersBaseDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'vlogs', _vlogFoldersBaseName),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _rawAlbumDir(String album) async {
    final base = await _rawBaseDir();
    final dir = Directory(p.join(base.path, album));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _vlogFolderDir(String folderName) async {
    final base = await _vlogFoldersBaseDir();
    final dir = Directory(p.join(base.path, folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool _isReservedClipAlbum(String name) => _systemClipAlbums.contains(name);
  bool _isReservedVlogAlbum(String name) => _systemVlogAlbums.contains(name);

  Future<void> _updateAlbumClipCounts() async {
    final rawBase = await _rawBaseDir();
    final newCounts = <String, int>{};

    // 전체 앨범 순회
    for (final albumName in clipAlbums) {
      final albumDir = Directory(p.join(rawBase.path, albumName));
      if (await albumDir.exists()) {
        final count = albumDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.mp4'))
            .length;
        newCounts[albumName] = count;
      } else {
        newCounts[albumName] = 0;
      }
    }

    albumCounts = newCounts;
    notifyListeners();
  }

  Future<List<String>> _listProjectFiles() async {
    final projectDir = await _projectBaseDir();
    final files = projectDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    files.sort(
      (a, b) => File(
        b.path,
      ).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()),
    );
    return files.map((f) => f.path).toList();
  }

  Future<Uint8List?> getThumbnail(String videoPath) async {
    if (thumbnailCache.containsKey(videoPath)) return thumbnailCache[videoPath];

    final docDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(docDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) await thumbDir.create(recursive: true);

    final thumbFile = File(
      p.join(thumbDir.path, "${p.basename(videoPath)}.jpg"),
    );

    if (await thumbFile.exists()) {
      final data = await thumbFile.readAsBytes();
      thumbnailCache[videoPath] = data;
      return data;
    }

    if (!await File(videoPath).exists()) {
      return null;
    }

    final data = await thum.VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: thum.ImageFormat.JPEG,
      maxWidth: 400,
      quality: 70,
    );

    if (data != null) {
      thumbnailCache[videoPath] = data;
      thumbFile.writeAsBytes(data).catchError((_) => thumbFile);
    }
    return data;
  }

  Future<String> _thumbnailFilePathFor(String videoPath) async {
    final docDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(docDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) await thumbDir.create(recursive: true);
    return p.join(thumbDir.path, '${p.basename(videoPath)}.jpg');
  }

  Future<String?> ensureThumbnailFilePath(String videoPath) async {
    final outputPath = await _thumbnailFilePathFor(videoPath);
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      return outputPath;
    }

    await getThumbnail(videoPath);
    if (await outputFile.exists()) {
      return outputPath;
    }
    return null;
  }

  Future<ImportPreviewData> prepareImportPreview(
    String videoPath, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final durationFuture = getVideoDuration(videoPath);
    final thumbnailFuture = ensureThumbnailFilePath(videoPath);

    final results = await Future.wait<dynamic>([
      durationFuture,
      thumbnailFuture,
    ]).timeout(timeout);

    final Duration duration = results[0] as Duration;
    final String? thumbPath = results[1] as String?;

    return ImportPreviewData(
      durationMs: duration > Duration.zero ? duration.inMilliseconds : null,
      thumbnailPath: thumbPath,
    );
  }

  void releaseImportPreparationResourcesForPath(String videoPath) {
    thumbnailCache.remove(videoPath);
    _durationCache.remove(videoPath);
    _timelineCache.removeWhere((key, _) => key.startsWith('${videoPath}_'));
  }

  void releaseImportPreparationResourcesForPaths(Iterable<String> paths) {
    for (final path in paths) {
      releaseImportPreparationResourcesForPath(path);
    }
  }

  // Get multiple thumbnails distributed evenly across duration
  /// Get cached video duration. Creates a temporary controller only on first call.
  Future<Duration> getVideoDuration(String videoPath) async {
    if (_durationCache.containsKey(videoPath)) {
      return _durationCache[videoPath]!;
    }

    final persistedMs = _persistedDurationMs[videoPath];
    if (persistedMs != null && persistedMs > 0) {
      final persisted = Duration(milliseconds: persistedMs);
      _durationCache[videoPath] = persisted;
      return persisted;
    }

    final file = File(videoPath);
    if (!await file.exists()) return Duration.zero;

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final duration = controller.value.duration;
      await _setDurationCacheForPath(videoPath, duration);
      debugPrint(
        '[VideoManager] Cached duration for ${videoPath.split('/').last}: $duration',
      );
      return duration;
    } catch (e) {
      debugPrint('[VideoManager] Error getting duration: $e');
      return Duration.zero;
    } finally {
      await controller?.dispose();
      // Brief delay to allow native codec cleanup
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<List<Uint8List>> getTimelineThumbnails(
    String videoPath,
    int durationMs,
    int count, {
    VlogClip? clip,
  }) async {
    final List<Uint8List> thumbnails = [];
    if (durationMs <= 0 || count <= 0) return thumbnails;

    // Check memory cache
    final String cacheKey = "${videoPath}_${count}_$durationMs";
    if (_timelineCache.containsKey(cacheKey)) {
      return _timelineCache[cacheKey]!;
    }

    if (clip != null) {
      final fromMeta = await _loadTimelineThumbnailsFromClipMetadata(
        clip,
        durationMs: durationMs,
        count: count,
      );
      if (fromMeta.length == count) {
        _timelineCache[cacheKey] = fromMeta;
        return fromMeta;
      }
    }

    final interval = durationMs ~/ count;

    for (int i = 0; i < count; i++) {
      final timeMs = (interval * i) + (interval ~/ 2);
      try {
        final data = await thum.VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: thum.ImageFormat.JPEG,
          maxWidth: 150, // Small width for timeline
          quality: 50, // Lower quality for performance
          timeMs: timeMs,
        );
        if (data != null) {
          thumbnails.add(data);
        }
      } catch (e) {
        debugPrint("Error generating timeline thumb $i: $e");
      }
    }

    // Save to cache
    if (thumbnails.isNotEmpty) {
      _timelineCache[cacheKey] = thumbnails;
    }

    if (clip != null && thumbnails.length == count) {
      await _persistTimelineThumbMetadata(
        clip,
        videoPath: videoPath,
        durationMs: durationMs,
        count: count,
        bytesList: thumbnails,
      );
    }

    return thumbnails;
  }

  Future<bool> ensureTimelineThumbnailMetadataForClip(
    VlogClip clip, {
    required int durationMs,
    int count = trimTimelineThumbCount,
  }) async {
    final oldVersion = clip.timelineThumbMetaVersion;
    final oldDuration = clip.timelineThumbDurationMs;
    final oldCount = clip.timelineThumbCount;
    final oldPaths = List<String>.from(clip.timelineThumbPaths);

    await getTimelineThumbnails(clip.path, durationMs, count, clip: clip);

    return oldVersion != clip.timelineThumbMetaVersion ||
        oldDuration != clip.timelineThumbDurationMs ||
        oldCount != clip.timelineThumbCount ||
        !_listEquals(oldPaths, clip.timelineThumbPaths);
  }

  Future<List<Uint8List>> _loadTimelineThumbnailsFromClipMetadata(
    VlogClip clip, {
    required int durationMs,
    required int count,
  }) async {
    final metaValid =
        clip.timelineThumbMetaVersion == _timelineThumbMetaVersion &&
        clip.timelineThumbDurationMs == durationMs &&
        clip.timelineThumbCount == count &&
        clip.timelineThumbPaths.length == count;
    if (!metaValid) return const [];

    final loaded = <Uint8List>[];
    for (final path in clip.timelineThumbPaths) {
      final file = File(path);
      if (!await file.exists()) {
        return const [];
      }
      loaded.add(await file.readAsBytes());
    }
    return loaded;
  }

  Future<void> _persistTimelineThumbMetadata(
    VlogClip clip, {
    required String videoPath,
    required int durationMs,
    required int count,
    required List<Uint8List> bytesList,
  }) async {
    final thumbDir = await _timelineThumbDir();
    final baseKey = _timelineThumbBaseKey(videoPath);
    final newPaths = <String>[];

    for (var i = 0; i < bytesList.length; i++) {
      final filePath = p.join(
        thumbDir.path,
        '${baseKey}_v${_timelineThumbMetaVersion}_${durationMs}_${count}_$i.jpg',
      );
      final file = File(filePath);
      await file.writeAsBytes(bytesList[i], flush: false);
      newPaths.add(filePath);
    }

    clip.timelineThumbMetaVersion = _timelineThumbMetaVersion;
    clip.timelineThumbDurationMs = durationMs;
    clip.timelineThumbCount = count;
    clip.timelineThumbPaths = newPaths;
  }

  Future<Directory> _timelineThumbDir() async {
    final dir = Directory(
      p.join((await _docDir()).path, 'thumbnails', 'timeline'),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _timelineThumbBaseKey(String videoPath) {
    final name = p
        .basenameWithoutExtension(videoPath)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final hash = _stablePathHash(videoPath);
    return '${name}_$hash';
  }

  String _stablePathHash(String input) {
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, String> _buildExportFailureContext({
    required Object? platformCode,
    required String? platformMessage,
    required Object? details,
    required String fallbackErrorClass,
  }) {
    final Map<String, String> detailMap = {};
    if (details is Map) {
      for (final entry in details.entries) {
        final dynamic key = entry.key;
        final String keyText = key?.toString() ?? '';
        if (keyText.isNotEmpty) {
          detailMap[keyText] = entry.value?.toString() ?? '';
        }
      }
    }

    final String messageText = (platformMessage ?? '').toLowerCase();
    final String detailMessage = (detailMap['message'] ?? '').toLowerCase();
    final String cause = (detailMap['cause'] ?? '').toLowerCase();
    final String causeClass = (detailMap['causeClass'] ?? fallbackErrorClass)
        .toString()
        .toLowerCase();
    final String errorCode = (detailMap['errorCode'] ?? '')
        .toString()
        .toLowerCase();
    final String rawCode = (platformCode ?? '').toString().toLowerCase();
    final String stack = (detailMap['stack'] ?? '').toLowerCase();

    final String signatureText =
        '$rawCode $messageText $detailMessage $cause $causeClass $errorCode $stack';
    final String forceStopSignature = _detectForceStopSignature(signatureText);
    if (forceStopSignature.isNotEmpty) {
      return {
        'normalizedFailCode': 'EXTERNAL_FORCE_STOP',
        'normalizedFailSource': 'EXTERNAL_FORCE_STOP',
        'errorClass': detailMap['causeClass']?.toString() ?? fallbackErrorClass,
        'forceStopSignature': forceStopSignature,
      };
    }

    if (_isAssetLoaderFailure(signatureText, causeClass)) {
      return {
        'normalizedFailCode': 'ASSET_LOADER',
        'normalizedFailSource': 'ASSET_LOADER',
        'errorClass': detailMap['causeClass']?.toString() ?? fallbackErrorClass,
      };
    }

    if (_isEncoderFailure(signatureText, causeClass)) {
      return {
        'normalizedFailCode': 'ENCODER_ERROR',
        'normalizedFailSource': 'ENCODER_ERROR',
        'errorClass': detailMap['causeClass']?.toString() ?? fallbackErrorClass,
      };
    }

    return {
      'normalizedFailCode': 'UNKNOWN',
      'normalizedFailSource': 'UNKNOWN',
      'errorClass': detailMap['causeClass']?.toString() ?? fallbackErrorClass,
    };
  }

  bool _isAssetLoaderFailure(String signatureText, String causeClass) {
    return signatureText.contains('asset') ||
        signatureText.contains('loader') ||
        signatureText.contains('extract') ||
        causeClass.contains('asset') ||
        causeClass.contains('extractor') ||
        causeClass.contains('mediametadataretriever') ||
        causeClass.contains('mediamuxer');
  }

  bool _isEncoderFailure(String signatureText, String causeClass) {
    return signatureText.contains('encoder') ||
        signatureText.contains('encoding') ||
        signatureText.contains('decode') ||
        signatureText.contains('codec') ||
        causeClass.contains('encoder') ||
        causeClass.contains('codec') ||
        causeClass.contains('transformer');
  }

  String _detectForceStopSignature(String signatureText) {
    final lower = signatureText.toLowerCase();
    if (lower.contains('from pid')) return 'FROM_PID';
    if (lower.contains('runforcestop') ||
        lower.contains('run forcestop') ||
        lower.contains('run_force_stop')) {
      return 'RUN_FORCE_STOP';
    }
    if (lower.contains('killing') && lower.contains('pid'))
      return 'KILLING_FROM_PID';
    if (lower.contains('external force') || lower.contains('force stop'))
      return 'FORCE_STOP';
    return '';
  }

  Future<void> convertPhotoToVideo(String imagePath, String targetAlbum) async {
    final outDir = await _rawAlbumDir(targetAlbum);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final String rawOutPath = p.join(outDir.path, "photo_${timestamp}_raw.mp4");
    final String outPath = p.join(outDir.path, "photo_$timestamp.mp4");

    final convertDurationMs = kTargetClipSaveMs;
    if (convertDurationMs <= 0) {
      _logChannelGuardFail(
        step: 'photo_to_video',
        platformError: 'INVALID_DURATION',
        message: 'duration must be greater than 0 (ms)',
      );
      throw StateError('Invalid convert duration: $convertDurationMs');
    }

    final String result;
    try {
      result = await platform.invokeMethod('convertImageToVideo', {
        'imagePath': imagePath,
        'outputPath': rawOutPath,
        'duration': convertDurationMs,
      });
    } on PlatformException catch (e) {
      _logChannelCallFail(
        step: 'photo_to_video',
        platformError: e.code,
        message: e.message ?? e.toString(),
      );
      rethrow;
    } catch (e) {
      _logChannelCallFail(
        step: 'photo_to_video',
        platformError: 'UNKNOWN',
        message: e.toString(),
      );
      rethrow;
    }

    if (result != "SUCCESS") {
      throw Exception("Native Conversion Error: $result");
    }
    final normalized = await _normalizeRecordedVideo(
      rawOutPath,
      outPath,
      targetDurationMs: _targetRecordingDurationMs,
    );

    if (!normalized) {
      await File(rawOutPath).copy(outPath);
    }

    try {
      await File(rawOutPath).delete();
    } catch (_) {}

    await _setClipOwnership(
      outPath,
      ownerAccountId: UserStatusManager().userId,
    );
    await _updateAlbumClipCounts();
  }

  // 2. Vlog 추출 (Native Engine 호출)
  Future<String?> exportVlog({
    required List<VlogClip> clips, // Changed to List<VlogClip>
    required Map<String, double> audioConfig,
    String? bgmPath,
    double bgmVolume = 0.5,
    String quality = '1080p',
    String userTier = 'free',
    String? mergeSessionId,
    String? debugTag,
    bool Function()? isCancelRequested,
    String Function()? getExportPhase,
    double Function()? getExportProgress,
    String Function()? getExportCancelReason,
  }) async {
    final int exportStartMs = DateTime.now().millisecondsSinceEpoch;
    final String resolvedMergeSessionId =
        (mergeSessionId?.trim().isNotEmpty == true)
        ? mergeSessionId!.trim()
        : 'merge_$exportStartMs';
    final String mergeTraceId =
        '${resolvedMergeSessionId}_engine_${exportStartMs}';

    void _logExportState({
      required String phase,
      required String state,
      String? status,
      int? attempt,
      String? reason,
      int? resultBytes,
      String? outputPath,
      String? errorCode,
      String? details,
    }) {
      debugPrint(
        '[VideoManager][Export][State] phase=$phase state=$state '
        'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
        'attempt=$attempt status=$status reason=$reason '
        'outputPath=$outputPath resultBytes=$resultBytes '
        'errorCode=$errorCode details=$details',
      );
    }

    bool _isCancelRequested() {
      return isCancelRequested?.call() == true;
    }

    String _resolveExportPhase({required String fallbackPhase}) {
      final String? phaseFromUi = getExportPhase?.call();
      if (phaseFromUi != null && phaseFromUi.trim().isNotEmpty) {
        return phaseFromUi.trim();
      }
      return fallbackPhase;
    }

    String _resolveExportCancelReason({required String fallbackReason}) {
      final String? reason = getExportCancelReason?.call();
      if (reason != null && reason.trim().isNotEmpty) {
        return reason.trim();
      }
      return fallbackReason;
    }

    double? _resolveExportProgress() {
      return getExportProgress?.call();
    }

    bool hasLoggedCancel = false;

    bool _checkAndLogCancel({
      required String phase,
      required String reason,
      int? attempt,
    }) {
      if (!_isCancelRequested()) return false;

      final String exportPhase = _resolveExportPhase(fallbackPhase: phase);
      final double? progress = _resolveExportProgress();
      final String cancelReason = _resolveExportCancelReason(
        fallbackReason: reason,
      );

      _logExportState(
        phase: exportPhase,
        state: 'cancel',
        status: hasLoggedCancel ? 'cancelled_poll' : 'cancelled',
        attempt: attempt,
        reason: cancelReason,
        details:
            'progress=${progress != null ? progress.toStringAsFixed(3) : 'null'}',
      );
      hasLoggedCancel = true;
      return true;
    }

    final int totalDurationMs = clips.fold<int>(0, (sum, clip) {
      final playbackMs =
          clip.endTime.inMilliseconds - clip.startTime.inMilliseconds;
      if (playbackMs > 0) return sum + playbackMs;
      if (clip.originalDuration > Duration.zero)
        return sum + clip.originalDuration.inMilliseconds;
      if (clip.endTime > Duration.zero)
        return sum + clip.endTime.inMilliseconds;
      return sum;
    });
    final String? callerTag = debugTag;

    _logExportState(
      phase: 'init',
      state: 'preparing',
      status: 'start',
      reason: 'export_started',
    );

    if (_checkAndLogCancel(phase: 'init', reason: 'cancel_before_start')) {
      return null;
    }

    int missingAudioConfigCount = 0;
    int zeroOrNegativeVolumeCount = 0;
    int duplicatePathCount = 0;
    final Set<String> seenPaths = <String>{};
    final List<String> missingAudioPaths = [];
    final List<String> zeroVolumePaths = [];

    for (final clip in clips) {
      final String clipPath = clip.path;
      if (!seenPaths.add(clipPath)) {
        duplicatePathCount++;
      }
      if (!audioConfig.containsKey(clipPath)) {
        missingAudioConfigCount++;
        if (missingAudioPaths.length < 3) missingAudioPaths.add(clipPath);
      }
      final double? audioVolume = audioConfig[clipPath];
      if (audioVolume != null && audioVolume <= 0) {
        zeroOrNegativeVolumeCount++;
        if (zeroVolumePaths.length < 3) {
          zeroVolumePaths.add(clipPath);
        }
      }
    }

    try {
      final String abGroup = _resolvedMergeAbGroup();
      final normalizedTier = normalizeUserTierKey(userTier);
      final clampedQuality = clampExportQualityForTier(
        requestedQuality: normalizeExportQuality(quality),
        tier: userTierFromKey(normalizedTier),
      );
      final String fallbackQuality = _downgradeQualityForRetry(clampedQuality);

      _warnIfRecentMemoryPressure(
        'exportVlog',
        clipCount: clips.length,
        quality: clampedQuality,
      );

      debugPrint(
        '[VideoManager][Export] args_summary '
        'clipCount=${clips.length} totalDurationMs=$totalDurationMs '
        'quality=$clampedQuality tier=$normalizedTier '
        'audioConfigCount=${audioConfig.length} hasBgm=${bgmPath?.isNotEmpty == true} '
        'bgmVolume=$bgmVolume '
        'memoryPressureRecent=${hasRecentMemoryPressure} '
        'memoryPressureElapsedMs=${millisSinceLastMemoryPressure ?? -1} '
        'eventCount=${memoryPressureEventCount}',
      );

      _logExportState(
        phase: 'preflight',
        state: 'preparing',
        status: 'preflight_summary',
        details:
            'clipCount=${clips.length} totalDurationMs=$totalDurationMs quality=$clampedQuality '
            'tier=$normalizedTier',
      );

      debugPrint(
        '[VideoManager][Export] preflight_summary '
        'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId caller=${callerTag ?? "unknown"} '
        'duplicateClipPaths=$duplicatePathCount missingAudioConfigCount=$missingAudioConfigCount '
        'zeroOrNegativeVolumeCount=$zeroOrNegativeVolumeCount '
        'missingAudioSamples=${missingAudioPaths.join("|")} '
        'zeroVolumeSamples=${zeroVolumePaths.join("|")} ',
      );

      // 1. 🛡️ 권한 체크 (Android 13 대응)
      bool hasPermission = false;

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          // Android 13 이상: 세분화된 미디어 권한 필요
          final videos = await Permission.videos.request();
          final audio = await Permission.audio.request();
          // photos 권한은 이미지/비디오 혼합 시 필요할 수 있음
          final photos = await Permission.photos.request();

          hasPermission = videos.isGranted || photos.isGranted;
        } else {
          // Android 12 이하: 저장소 권한 필요
          final storage = await Permission.storage.request();
          hasPermission = storage.isGranted;
        }
      } else {
        // iOS
        hasPermission = true; // 보통 갤러리 접근 시 자동 처리되거나 별도 로직
      }

      if (!hasPermission) {
        print("❌ Export Error: 권한이 거부되었습니다.");
        _logExportState(
          phase: 'permission',
          state: 'error',
          status: 'permission_denied',
          reason: 'permission_check_failed',
        );
        debugPrint(
          '[VideoManager][Export][MergeComplete] result=null reason=permission_denied',
        );
        if (_checkAndLogCancel(
          phase: 'permission',
          reason: 'cancel_after_permission',
        )) {
          return null;
        }
        return null;
      }

      // 2. 📂 경로 설정
      final docDir = await getApplicationDocumentsDirectory();
      final vlogDir = Directory(p.join(docDir.path, 'Vlogs'));
      if (!await vlogDir.exists()) {
        await vlogDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(vlogDir.path, 'vlog_$timestamp.mp4');

      // 3. 🎞️ 대상 파일 준비
      if (clips.isEmpty) {
        print("❌ Export Error: 병합할 영상이 없습니다.");
        _logExportState(
          phase: 'validation',
          state: 'error',
          status: 'empty_clips',
          reason: 'validation_failed',
        );
        debugPrint(
          '[VideoManager][Export][MergeComplete] result=null reason=empty_clips',
        );
        if (_checkAndLogCancel(
          phase: 'validation',
          reason: 'cancel_after_validation',
        )) {
          return null;
        }
        return null;
      }

      print("🚀 Start Exporting... (Count: ${clips.length})");
      print("   - Output: $outputPath");
      print("   - Quality: $clampedQuality");
      print("   - User Tier: $normalizedTier");

      // 4. ⚡ Native Engine 호출
      final videoPaths = clips.map((c) => c.path).toList();
      final startTimes = clips.map((c) => c.startTime.inMilliseconds).toList();
      final endTimes = clips.map((c) => c.endTime.inMilliseconds).toList();

      Future<String?> invokeMergeAttempt({
        required int attempt,
        required String qualityValue,
        required String retryPlan,
        required bool audioSimplify,
      }) async {
        final args = {
          'videoPaths': videoPaths,
          'startTimes': startTimes, // Pass start times
          'endTimes': endTimes, // Pass end times
          'outputPath': outputPath,
          'audioChanges': audioConfig,
          'bgmPath': bgmPath,
          'bgmVolume': bgmVolume,
          'quality': qualityValue,
          'userTier': normalizedTier,
          'attempt': attempt,
          'abGroup': abGroup,
          'retryPlan': retryPlan,
          'audioSimplify': audioSimplify,
          'qualityPreset': qualityValue,
          'mergeSessionId': resolvedMergeSessionId,
          'mergeTraceId': mergeTraceId,
          'caller': callerTag ?? 'unknown',
        };

        debugPrint(
          '[VideoManager][Export] invoking_merge start clipCount=${clips.length} '
          'quality=$qualityValue tier=$normalizedTier totalDurationMs=$totalDurationMs '
          'attempt=$attempt retryPlan=$retryPlan audioSimplify=$audioSimplify '
          'abGroup=$abGroup qualityPreset=$qualityValue '
          'outputPath=$outputPath sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
          'caller=${callerTag ?? "unknown"}',
        );

        _logExportState(
          phase: 'rendering',
          state: 'rendering',
          status: 'invoke_start',
          attempt: attempt,
          outputPath: outputPath,
          reason: 'native_invoke',
          details:
              'quality=$qualityValue retryPlan=$retryPlan audioSimplify=$audioSimplify',
        );

        if (_checkAndLogCancel(
          phase: 'rendering',
          reason: 'cancel_before_native_invoke',
        )) {
          return null;
        }

        final String? result = await platform.invokeMethod('mergeVideos', args);

        final mergeElapsedMs =
            DateTime.now().millisecondsSinceEpoch - exportStartMs;
        bool resultExists = false;
        int resultBytes = -1;

        if (result != null) {
          try {
            final File resultFile = File(result);
            resultExists = await resultFile.exists();
            if (resultExists) {
              resultBytes = await resultFile.length();
            }
          } catch (_) {}
        }
        debugPrint(
          '[VideoManager][Export] invoke_merge_done '
          'elapsedMs=$mergeElapsedMs result=$result '
          'clipCount=${clips.length} quality=$qualityValue '
          'attempt=$attempt retryPlan=$retryPlan '
          'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
          'resultExists=$resultExists resultBytes=$resultBytes',
        );

        _logExportState(
          phase: 'rendering',
          state: result == null ? 'error' : 'rendering',
          status: result == null ? 'native_result_null' : 'native_result_ready',
          attempt: attempt,
          outputPath: result,
          resultBytes: resultBytes,
          reason: result == null
              ? 'platform_returned_null'
              : 'platform_returned_path',
        );

        debugPrint(
          '[VideoManager][Export] MergeComplete result=$result '
          'attempt=$attempt retryPlan=$retryPlan '
          'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
          'caller=${callerTag ?? "unknown"}',
        );

        if (result == null) {
          debugPrint(
            '[VideoManager][Export][MergeComplete] result=null '
            'reason=platform_returned_null attempt=$attempt '
            'retryPlan=$retryPlan '
            'abGroup=$abGroup '
            'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId',
          );
        }

        // 갤러리에 저장 (Gal 패키지 사용)
        if (result != null) {
          try {
            await Gal.putVideo(result, album: '2S_Vlog');
            _logExportState(
              phase: 'saving',
              state: 'done',
              status: 'gallery_saved',
              attempt: attempt,
              outputPath: result,
              resultBytes: resultBytes,
              reason: 'Gal.putVideo',
            );
            debugPrint(
              '[VideoManager][Export] SavedToGallery result=$result album=2S_Vlog',
            );
          } catch (e) {
            _logExportState(
              phase: 'saving',
              state: 'error',
              status: 'gallery_save_failed',
              attempt: attempt,
              outputPath: result,
              reason: 'Gal.putVideo_failed',
              details: e.toString(),
            );
            debugPrint('[VideoManager][Export] save_gallery_failed message=$e');
          }
        }

        return result;
      }

      for (int attempt = 1; attempt <= 2; attempt++) {
        final bool isRetryAttempt = attempt == 2;
        final String qualityValue = isRetryAttempt
            ? fallbackQuality
            : clampedQuality;
        final bool audioSimplify = isRetryAttempt && abGroup == 'B';
        final String retryPlan = _retryPlanForAttempt(
          attempt: attempt,
          abGroup: abGroup,
          forceRetry: isRetryAttempt,
        );

        try {
          if (_checkAndLogCancel(
            phase: 'rendering',
            reason: 'cancel_before_attempt_$attempt',
            attempt: attempt,
          )) {
            return null;
          }

          final String? result = await invokeMergeAttempt(
            attempt: attempt,
            qualityValue: qualityValue,
            retryPlan: retryPlan,
            audioSimplify: audioSimplify,
          );

          if (_checkAndLogCancel(
            phase: 'rendering',
            reason: 'cancel_after_attempt_$attempt',
            attempt: attempt,
          )) {
            return null;
          }
          if (result != null) {
            _logExportState(
              phase: 'done',
              state: 'done',
              status: 'merge_completed',
              attempt: attempt,
              outputPath: result,
              reason: 'export_success',
            );
            return result;
          }
          if (isRetryAttempt) {
            return null;
          }

          return null;
        } on PlatformException catch (e) {
          if (_checkAndLogCancel(
            phase: 'error',
            reason: 'cancel_after_platform_exception',
            attempt: attempt,
          )) {
            return null;
          }

          final int failElapsedMs =
              DateTime.now().millisecondsSinceEpoch - exportStartMs;
          final rawDetails = e.details;
          final detailText = rawDetails != null
              ? (rawDetails is String
                    ? rawDetails
                    : rawDetails is Map
                    ? jsonEncode(rawDetails)
                    : rawDetails.toString())
              : null;
          final clippedDetails = detailText != null && detailText.length > 4000
              ? detailText.substring(0, 4000)
              : detailText;
          final normalizedFailure = _buildExportFailureContext(
            platformCode: e.code,
            platformMessage: e.message,
            details: rawDetails,
            fallbackErrorClass: e.runtimeType.toString(),
          );
          final forceStopLabel = normalizedFailure['forceStopSignature'];
          final bool isForceStop =
              normalizedFailure['normalizedFailSource'] ==
                  'EXTERNAL_FORCE_STOP' ||
              normalizedFailure['normalizedFailCode'] == 'EXTERNAL_FORCE_STOP';
          final bool retryAllowed =
              attempt == 1 &&
              _isMergeRetryAllowed(normalizedFailure, isForceStop);
          final String nextRetryPlan = _retryPlanForAttempt(
            attempt: 2,
            abGroup: abGroup,
            forceRetry: true,
          );
          final bool nextAudioSimplify = abGroup == 'B';

          print("❌ Native Error [${e.code}] ${e.message}");
          if (clippedDetails != null) {
            print("❌ Native Error Details: $clippedDetails");
          } else {
            print("❌ Native Error Details: <none>");
          }
          debugPrint(
            '[VideoManager][Export][MergeFail] result=null exception=PlatformException '
            'type=${e.runtimeType} code=${e.code} message=${e.message} '
            'attempt=$attempt retryPlan=$retryPlan abGroup=$abGroup '
            'audioSimplify=$audioSimplify '
            'normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
            'normalizedFailSource=${normalizedFailure['normalizedFailSource']} '
            'errorClass=${normalizedFailure['errorClass']} '
            '${forceStopLabel != null ? 'forceStopSignature=$forceStopLabel ' : ''}'
            'details=$clippedDetails elapsedMs=$failElapsedMs '
            'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
            'caller=${callerTag ?? "unknown"}',
          );

          _logExportState(
            phase: 'error',
            state: 'error',
            status: 'merge_exception_platform',
            attempt: attempt,
            reason: 'platform_exception',
            errorCode: e.code,
            details:
                'message=${e.message} normalizedFailCode=${normalizedFailure['normalizedFailCode']}'
                ' normalizedFailSource=${normalizedFailure['normalizedFailSource']}'
                ' attempt=$attempt retryPlan=$retryPlan forceStop=$isForceStop',
          );

          if (retryAllowed) {
            if (_checkAndLogCancel(
              phase: 'error',
              reason: 'cancel_before_retry',
              attempt: attempt,
            )) {
              return null;
            }

            _logExportState(
              phase: 'error',
              state: 'error',
              status: 'retry_planned',
              attempt: attempt,
              reason: 'retry_allowed',
              details:
                  'normalizedFailCode=${normalizedFailure['normalizedFailCode']}'
                  ' nextRetryPlan=$nextRetryPlan',
            );
            debugPrint(
              '[VideoManager][Export][MergeRetry] decision=retry attempt=2 '
              'fromAttempt=$attempt normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
              'abGroup=$abGroup nextRetryPlan=$nextRetryPlan '
              'nextQuality=$fallbackQuality nextAudioSimplify=$nextAudioSimplify '
              'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
              'caller=${callerTag ?? "unknown"}',
            );
            continue;
          }

          _logExportState(
            phase: 'error',
            state: 'error',
            status: 'merge_exception_terminal',
            attempt: attempt,
            reason: 'retry_not_allowed',
            errorCode: e.code,
            details:
                'attempt=$attempt retryPlan=$retryPlan forceStop=$isForceStop'
                ' normalizedFailCode=${normalizedFailure['normalizedFailCode']}',
          );

          return null;
        } catch (e) {
          final int failElapsedMs =
              DateTime.now().millisecondsSinceEpoch - exportStartMs;
          final normalizedFailure = _buildExportFailureContext(
            platformCode: null,
            platformMessage: e.toString(),
            details: null,
            fallbackErrorClass: e.runtimeType.toString(),
          );
          final bool isForceStop =
              normalizedFailure['normalizedFailSource'] ==
                  'EXTERNAL_FORCE_STOP' ||
              normalizedFailure['normalizedFailCode'] == 'EXTERNAL_FORCE_STOP';
          final bool retryAllowed =
              attempt == 1 &&
              _isMergeRetryAllowed(normalizedFailure, isForceStop);
          final String nextRetryPlan = _retryPlanForAttempt(
            attempt: 2,
            abGroup: abGroup,
            forceRetry: true,
          );
          final bool nextAudioSimplify = abGroup == 'B';

          print("❌ Unexpected Error: $e");
          debugPrint(
            '[VideoManager][Export][MergeFail] result=null exception=${e.runtimeType} '
            'message=$e attempt=$attempt retryPlan=$retryPlan abGroup=$abGroup '
            'audioSimplify=$audioSimplify '
            'normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
            'normalizedFailSource=${normalizedFailure['normalizedFailSource']} '
            'errorClass=${normalizedFailure['errorClass']} '
            'elapsedMs=$failElapsedMs '
            'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
            'caller=${callerTag ?? "unknown"}',
          );

          _logExportState(
            phase: 'error',
            state: 'error',
            status: 'merge_exception_unexpected',
            attempt: attempt,
            reason: 'unexpected_exception',
            errorCode: e.runtimeType.toString(),
            details:
                'message=$e isForceStop=$isForceStop attempt=$attempt retryPlan=$retryPlan',
          );

          if (retryAllowed) {
            if (_checkAndLogCancel(
              phase: 'error',
              reason: 'cancel_before_retry',
              attempt: attempt,
            )) {
              return null;
            }

            _logExportState(
              phase: 'error',
              state: 'error',
              status: 'retry_planned',
              attempt: attempt,
              reason: 'retry_allowed',
              details:
                  'normalizedFailCode=${normalizedFailure['normalizedFailCode']}'
                  ' nextRetryPlan=$nextRetryPlan',
            );
            debugPrint(
              '[VideoManager][Export][MergeRetry] decision=retry attempt=2 '
              'fromAttempt=$attempt normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
              'abGroup=$abGroup nextRetryPlan=$nextRetryPlan '
              'nextQuality=$fallbackQuality nextAudioSimplify=$nextAudioSimplify '
              'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
              'caller=${callerTag ?? "unknown"}',
            );
            continue;
          }

          _logExportState(
            phase: 'error',
            state: 'error',
            status: 'merge_exception_terminal',
            attempt: attempt,
            reason: 'retry_not_allowed',
            errorCode: e.runtimeType.toString(),
            details:
                'attempt=$attempt retryPlan=$retryPlan isForceStop=$isForceStop',
          );

          return null;
        }
      }

      if (_checkAndLogCancel(
        phase: 'error',
        reason: 'cancel_after_attempt_loop',
      )) {
        return null;
      }

      _logExportState(
        phase: 'error',
        state: 'error',
        status: 'no_result_after_retry',
        attempt: 2,
        reason: 'all_attempts_completed',
      );

      return null;
    } on PlatformException catch (e) {
      if (_checkAndLogCancel(
        phase: 'error',
        reason: 'cancel_after_outer_platform_exception',
      )) {
        return null;
      }

      final int failElapsedMs =
          DateTime.now().millisecondsSinceEpoch - exportStartMs;
      final rawDetails = e.details;
      final detailText = rawDetails != null
          ? (rawDetails is String
                ? rawDetails
                : rawDetails is Map
                ? jsonEncode(rawDetails)
                : rawDetails.toString())
          : null;
      final clippedDetails = detailText != null && detailText.length > 4000
          ? detailText.substring(0, 4000)
          : detailText;
      final normalizedFailure = _buildExportFailureContext(
        platformCode: e.code,
        platformMessage: e.message,
        details: rawDetails,
        fallbackErrorClass: e.runtimeType.toString(),
      );
      final forceStopLabel = normalizedFailure['forceStopSignature'];

      print("❌ Native Error [${e.code}] ${e.message}");
      if (clippedDetails != null) {
        print("❌ Native Error Details: $clippedDetails");
      } else {
        print("❌ Native Error Details: <none>");
      }
      debugPrint(
        '[VideoManager][Export][MergeFail] result=null exception=PlatformException '
        'type=${e.runtimeType} code=${e.code} message=${e.message} '
        'normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
        'normalizedFailSource=${normalizedFailure['normalizedFailSource']} '
        'errorClass=${normalizedFailure['errorClass']} '
        '${forceStopLabel != null ? 'forceStopSignature=$forceStopLabel ' : ''}'
        'details=$clippedDetails elapsedMs=$failElapsedMs '
        'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
        'caller=${callerTag ?? "unknown"}',
      );
      _logExportState(
        phase: 'error',
        state: 'error',
        status: 'merge_exception_outer',
        errorCode: e.code,
        details: e.message,
      );
      return null;
    } catch (e) {
      if (_checkAndLogCancel(
        phase: 'error',
        reason: 'cancel_after_outer_exception',
      )) {
        return null;
      }

      final int failElapsedMs =
          DateTime.now().millisecondsSinceEpoch - exportStartMs;
      final normalizedFailure = _buildExportFailureContext(
        platformCode: null,
        platformMessage: e.toString(),
        details: null,
        fallbackErrorClass: e.runtimeType.toString(),
      );

      print("❌ Unexpected Error: $e");
      debugPrint(
        '[VideoManager][Export][MergeFail] result=null exception=${e.runtimeType} '
        'message=$e normalizedFailCode=${normalizedFailure['normalizedFailCode']} '
        'normalizedFailSource=${normalizedFailure['normalizedFailSource']} '
        'errorClass=${normalizedFailure['errorClass']} '
        'elapsedMs=$failElapsedMs '
        'sessionId=$resolvedMergeSessionId traceId=$mergeTraceId '
        'caller=${callerTag ?? "unknown"}',
      );
      _logExportState(
        phase: 'error',
        state: 'error',
        status: 'merge_exception_outer_unexpected',
        errorCode: e.runtimeType.toString(),
        details: e.toString(),
      );
      return null;
    }
  }

  // 휴지통으로 이동
  Future<void> moveProjectToTrash(String projectId) async {
    final index = vlogProjects.indexWhere((p) => p.id == projectId);
    if (index != -1) {
      final project = vlogProjects[index];
      final currentFolder = project.folderName;
      final updated = project.copyWith(
        folderName: '휴지통',
        trashedFromFolderName: currentFolder == '휴지통'
            ? project.trashedFromFolderName
            : currentFolder,
      );
      await saveProject(updated);
      notifyListeners();
    }
  }

  // ✅ Data Statistics Getters & Methods
  int get totalClipCount {
    int count = 0;
    for (var c in albumCounts.values) {
      count += c;
    }
    return count;
  }

  int get totalVlogCount => _vlogProjectCountCache;
  int _vlogProjectCountCache = 0;

  Future<void> _updateVlogProjectCount() async {
    final files = await _listProjectFiles();
    _vlogProjectCountCache = files.length;
    notifyListeners();
  }

  Future<String> calculateStorageUsage() async {
    int totalBytes = 0;

    final dirs = [
      await _rawBaseDir(),
      await _projectBaseDir(),
      await _vlogFoldersBaseDir(),
    ];

    for (final dir in dirs) {
      if (await dir.exists()) {
        await for (final file in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File) totalBytes += await file.length();
        }
      }
    }

    if (totalBytes < 1024) return "$totalBytes B";
    if (totalBytes < 1024 * 1024)
      return "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    if (totalBytes < 1024 * 1024 * 1024)
      return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> initAlbumSystem() async {
    final rawBase = await _rawBaseDir();
    final vlogBase = await _vlogFoldersBaseDir();
    await _loadCloudSyncedPaths();
    await _loadClipDurationMetadata();
    await _loadClipOwnershipMetadata();

    // ✅ 2. 독립 휴지통 생성
    // 라이브러리 시스템 폴더
    for (final systemName in _systemClipAlbums) {
      final dir = Directory(p.join(rawBase.path, systemName));
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    // Vlog 시스템 폴더
    for (final systemName in _systemVlogAlbums) {
      final dir = Directory(p.join(vlogBase.path, systemName));
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    await _projectBaseDir();
    await Directory(
      p.join((await _docDir()).path, 'thumbnails'),
    ).create(recursive: true);

    // 라이브러리 앨범 로드
    final clipEntities = rawBase.listSync().whereType<Directory>().toList();
    final clipAlbumWithTime = <MapEntry<String, DateTime>>[];
    for (final entity in clipEntities) {
      final name = p.basename(entity.path);
      final stat = await entity.stat();
      clipAlbumWithTime.add(MapEntry(name, stat.changed));
    }

    clipAlbumWithTime.sort((a, b) {
      if (a.key == "일상") return -1;
      if (b.key == "일상") return 1;
      if (a.key == "휴지통") return 1;
      if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    final sortedClipNames = clipAlbumWithTime.map((e) => e.key).toList();
    if (!sortedClipNames.contains("일상")) sortedClipNames.insert(0, "일상");
    if (!sortedClipNames.contains("휴지통")) sortedClipNames.add("휴지통");
    clipAlbums = sortedClipNames;

    // ✅ 앨범별 클립 수 캐시 업데이트
    await _updateAlbumClipCounts();

    // Vlog 앨범 로드
    final vlogEntities = vlogBase.listSync().whereType<Directory>().toList();
    final vlogAlbumWithTime = <MapEntry<String, DateTime>>[];
    for (final entity in vlogEntities) {
      final name = p.basename(entity.path);
      // ✅ "일상" 폴더는 클립 전용이므로 제외
      if (name == "일상") continue;
      final stat = await entity.stat();
      vlogAlbumWithTime.add(MapEntry(name, stat.changed));
    }

    vlogAlbumWithTime.sort((a, b) {
      if (a.key == "기본") return -1; // 기본 최상단
      if (b.key == "기본") return 1;
      if (a.key == "휴지통") return 1; // 휴지통 최하단
      if (b.key == "휴지통") return -1;
      return a.value.compareTo(b.value);
    });

    final sortedVlogNames = vlogAlbumWithTime.map((e) => e.key).toList();
    if (!sortedVlogNames.contains("기본")) sortedVlogNames.insert(0, "기본");
    if (!sortedVlogNames.contains("휴지통")) sortedVlogNames.add("휴지통");
    vlogAlbums = sortedVlogNames;

    // await loadVlogProjects(notify: false); // Deprecated or not used?
    // Using _updateVlogProjectCount instead for stats
    await _updateVlogProjectCount();

    // Phase 5: 프로젝트 로드
    await loadProjects();
    await _cleanupClipOwnershipMetadata();

    // notifyListeners(); // _updateVlogProjectCount calls notifyListeners
  }

  void clearClips() {
    recordedVideoPaths = [];
    notifyListeners();
  }

  Future<void> loadClipsFromCurrentAlbum() async {
    recordedVideoPaths = [];
    final albumDir = await _rawAlbumDir(currentAlbum);
    final files = albumDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
    files.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    recordedVideoPaths = files;
    unawaited(_preloadClipDurationsForPaths(recordedVideoPaths));
    await _cleanupCloudSyncedPaths();
    await _cleanupClipOwnershipMetadata();
    notifyListeners();
  }

  Future<List<String>> ensureTutorialSampleClips({
    String targetAlbum = '일상',
  }) async {
    final albumDir = await _rawAlbumDir(targetAlbum);
    final ensuredPaths = <String>[];

    for (final assetPath in _tutorialSampleAssets) {
      final fileName = 'clip_${p.basename(assetPath)}';
      final destinationPath = p.join(albumDir.path, fileName);
      final destinationFile = File(destinationPath);

      try {
        if (!await destinationFile.exists()) {
          final data = await rootBundle.load(assetPath);
          await destinationFile.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
        }

        await _setClipOwnership(
          destinationPath,
          ownerAccountId: UserStatusManager().userId,
        );
        await _upsertLocalIndexClip(destinationPath);
        await _removeDurationCacheForPath(destinationPath);
        ensuredPaths.add(destinationPath);
      } catch (e) {
        debugPrint(
          '[VideoManager][TutorialSample] ensure_failed '
          'asset=$assetPath target=$destinationPath error=$e',
        );
      }
    }

    await _updateAlbumClipCounts();
    if (currentAlbum == targetAlbum) {
      await loadClipsFromCurrentAlbum();
    }
    return ensuredPaths;
  }

  Future<void> _preloadClipDurationsForPaths(List<String> paths) async {
    final unresolved = paths
        .where(
          (path) =>
              !_durationCache.containsKey(path) &&
              !_persistedDurationMs.containsKey(path),
        )
        .toList();
    if (unresolved.isEmpty) return;

    for (final path in unresolved) {
      try {
        await getVideoDuration(path);
      } catch (_) {
        // Ignore per-file preload failure. UI fallback handles this case.
      }
    }
  }

  Future<void> loadVlogsFromCurrentFolder() async {
    if (currentVlogFolder.isEmpty) {
      vlogProjectPaths = [];
      notifyListeners();
      return;
    }

    final folderDir = await _vlogFolderDir(currentVlogFolder);
    final files = folderDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
    files.sort(
      (a, b) =>
          File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()),
    );
    vlogProjectPaths = files;
    await _cleanupCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> loadVlogProjects({bool notify = true}) async {
    vlogProjectPaths = await _listProjectFiles();
    await _cleanupCloudSyncedPaths();
    if (notify) notifyListeners();
  }

  /// 특정 앨범의 클립 목록 반환 (캐시 우선)
  List<String> getClipsInAlbum(String albumName) {
    // 현재 앨범이면 캐시된 데이터 사용
    if (currentAlbum == albumName) {
      return recordedVideoPaths;
    }
    // 다른 앨범은 빈 리스트 (UI에서는 getClipCountSync 사용)
    return [];
  }

  /// 특정 앨범의 클립 수를 실시간 조회 (동기적, 파일 시스템)
  int getClipCountSync(String albumName) {
    try {
      // 동기적으로 DocumentsDirectory 경로 구성
      final docPath =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (docPath.isEmpty) return 0;

      // Android/iOS 환경에서는 getApplicationDocumentsDirectory 경로 사용
      // 여기서는 간단히 처리 - 실제로는 비동기 필요하므로 캐시 맵 사용
      return albumCounts[albumName] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void toggleFavoritesBatch(List<String> paths) {
    for (var path in paths) {
      if (favorites.contains(path)) {
        favorites.remove(path);
      } else {
        favorites.add(path);
      }
    }
  }

  Future<void> toggleProjectFavoritesBatch(List<String> projectIds) async {
    if (projectIds.isEmpty) return;

    final selected = vlogProjects
        .where((project) => projectIds.contains(project.id))
        .toList();
    if (selected.isEmpty) return;

    final bool shouldFavorite = selected.any((project) => !project.isFavorite);
    for (final project in selected) {
      final updated = project.copyWith(isFavorite: shouldFavorite);
      await saveProject(updated);
    }

    notifyListeners();
  }

  Future<void> moveClipsBatch(List<String> paths, String targetAlbum) async {
    final targetDir = await _rawAlbumDir(targetAlbum);
    for (var oldPath in paths) {
      final dest = await _buildUniqueFilePath(
        targetDir.path,
        p.basename(oldPath),
      );
      try {
        await File(oldPath).rename(dest);
        await _moveClipOwnershipPath(oldPath, dest);
        await _moveDurationCachePath(oldPath, dest);
      } catch (_) {
        await File(oldPath).copy(dest);
        await File(oldPath).delete();
        await _moveClipOwnershipPath(oldPath, dest);
        await _moveDurationCachePath(oldPath, dest);
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> deleteClipsBatch(List<String> paths) async {
    // ✅ 영구 삭제 (휴지통 전용)
    for (var path in paths) {
      await File(path).delete();
      await _removeClipOwnershipForPath(path);
      await _removeDurationCacheForPath(path);
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> saveRecordedVideo(XFile video) async {
    final albumDir = await _rawAlbumDir(currentAlbum);
    final savePath = p.join(
      albumDir.path,
      "clip_${DateTime.now().millisecondsSinceEpoch}.mp4",
    );
    final currentPath = savePath;

    debugPrint(
      '[VideoManager] saveRecordedVideo_paths '
      'sourcePath=${video.path} '
      'outputPath=$currentPath '
      'targetDurationMs=$_targetRecordingDurationMs '
      'trimMode=$_recordingTrimMode',
    );

    final sourceDurationMs = await _getVideoDurationMsNative(video.path);
    if (sourceDurationMs != null && sourceDurationMs < _targetRecordingDurationMs) {
      debugPrint(
        '[VideoManager][Warn] source shorter than trim target '
        'sourceDurationMs=$sourceDurationMs targetDurationMs=$_targetRecordingDurationMs',
      );
    }
    final expectedClipMs = sourceDurationMs != null
        ? (sourceDurationMs < _targetRecordingDurationMs
              ? sourceDurationMs
              : _targetRecordingDurationMs)
        : _targetRecordingDurationMs;
    debugPrint(
      '[VideoManager] saveRecordedVideo '
      'sourceDurationMs=$sourceDurationMs '
      'targetDurationMs=$_targetRecordingDurationMs '
      'expectedClipMs=$expectedClipMs '
      'trimMode=$_recordingTrimMode '
      'normalize=always',
    );

    final normalized = await _normalizeRecordedVideo(video.path, currentPath);
    if (!normalized) {
      try {
        await File(video.path).copy(currentPath);
        debugPrint(
          '[VideoManager] normalize fallback(copy) source=${video.path.split('/').last} '
          'target=${currentPath.split('/').last}',
        );
      } catch (e) {
        debugPrint('[VideoManager] Copy fallback failed: $e');
        return;
      }
    }

    final normalizedDurationMs = await _getVideoDurationMsNative(currentPath);
    debugPrint(
      '[VideoManager] saveRecordedVideo_result '
      'sourceDurationMs=$sourceDurationMs '
      'targetDurationMs=$_targetRecordingDurationMs '
      'normalizedDurationMs=$normalizedDurationMs '
      'normalizeSuccess=$normalized',
    );

    await _setClipOwnership(
      currentPath,
      ownerAccountId: UserStatusManager().userId,
    );
    await _upsertLocalIndexClip(currentPath);

    await _removeDurationCacheForPath(currentPath);
    await loadClipsFromCurrentAlbum();
    await _updateAlbumClipCounts();
  }

  Future<int?> _getVideoDurationMsNative(String inputPath) async {
    try {
      final result = await platform.invokeMethod('getVideoDurationMs', {
        'inputPath': inputPath,
      });
      if (result is int) {
        return result;
      }
      if (result is num) {
        return result.toInt();
      }
      if (result is String) {
        return int.tryParse(result);
      }
    } on PlatformException catch (e) {
      _logChannelCallFail(
        step: 'duration_query',
        platformError: e.code,
        message: e.message ?? e.toString(),
      );
    } catch (e) {
      _logChannelCallFail(
        step: 'duration_query',
        platformError: 'UNKNOWN',
        message: e.toString(),
      );
    }
    return null;
  }

  Future<bool> _normalizeRecordedVideo(
    String sourcePath,
    String outputPath, {
    int? targetDurationMs,
  }) async {
    try {
      final effectiveTargetDurationMs =
          targetDurationMs ?? _targetRecordingDurationMs;
      if (effectiveTargetDurationMs <= 0) {
        _logChannelGuardFail(
          step: 'normalize',
          platformError: 'INVALID_DURATION',
          message: 'targetDurationMs must be greater than 0',
        );
        return false;
      }
      debugPrint(
        '[VideoManager] normalizeRecordedVideo_request '
        'sourcePath=$sourcePath '
        'outputPath=$outputPath '
        'targetDurationMs=$effectiveTargetDurationMs '
        'trimMode=$_recordingTrimMode',
      );

      final result = await platform.invokeMethod('normalizeVideoDuration', {
        'inputPath': sourcePath,
        'outputPath': outputPath,
        'targetDurationMs': effectiveTargetDurationMs,
        'trimMode': _recordingTrimMode,
      });

      debugPrint(
        '[VideoManager] normalizeRecordedVideo_response result=$result',
      );

      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      _logChannelCallFail(
        step: 'normalize',
        platformError: e.code,
        message: e.message ?? e.toString(),
      );
      return false;
    } catch (e) {
      _logChannelCallFail(
        step: 'normalize',
        platformError: 'UNKNOWN',
        message: e.toString(),
      );
      return false;
    }
  }

  Future<void> markClipCloudSynced(String path) async {
    _cloudSyncedPaths.add(path);
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> unmarkClipCloudSynced(String path) async {
    final removed = _cloudSyncedPaths.remove(path);
    if (!removed) return;
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  bool isClipCloudSynced(String path) => _cloudSyncedPaths.contains(path);

  void markClipTransferPendingUpload(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.pendingUpload;
    notifyListeners();
  }

  void markClipTransferPendingDownload(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.pendingDownload;
    notifyListeners();
  }

  void markClipTransferUploadFailed(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.failedUpload;
    notifyListeners();
  }

  void markClipTransferDownloadFailed(String path) {
    _clipTransferUiStateByPath[path] = ClipTransferUiState.failedDownload;
    notifyListeners();
  }

  void clearClipTransferUiState(String path) {
    if (_clipTransferUiStateByPath.remove(path) != null) {
      notifyListeners();
    }
  }

  ClipTransferUiState? getClipTransferUiState(String path) =>
      _clipTransferUiStateByPath[path];

  /// 사용자 전환(로그아웃/계정 변경) 시 사용자 종속 로컬 캐시 초기화
  Future<void> clearUserScopedLocalCache() async {
    _cloudSyncedPaths.clear();
    await _persistCloudSyncedPaths();
    notifyListeners();
  }

  Future<void> createNewClipAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_isReservedClipAlbum(trimmed)) return;

    final safeName = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = await _rawBaseDir();
    final target = Directory(p.join(base.path, safeName));
    if (await target.exists()) return;
    await target.create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> createNewVlogAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_isReservedVlogAlbum(trimmed)) return;

    final safeName = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = await _vlogFoldersBaseDir();
    final target = Directory(p.join(base.path, safeName));
    if (await target.exists()) return;
    await target.create(recursive: true);
    await initAlbumSystem();
  }

  Future<void> deleteClipAlbums(Set<String> names) async {
    final base = await _rawBaseDir();
    for (var name in names) {
      if (_isReservedClipAlbum(name)) continue;
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        for (var file in dir.listSync().whereType<File>()) {
          final trashDir = Directory(p.join(base.path, '휴지통'));
          if (!await trashDir.exists()) await trashDir.create(recursive: true);
          final trashName = "${name}__${p.basename(file.path)}";
          final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
          try {
            await file.rename(destPath);
          } catch (_) {
            await file.copy(destPath);
            await file.delete();
          }
        }
        await dir.delete(recursive: true);
      }
    }
  }

  Future<void> deleteVlogAlbums(Set<String> names) async {
    final base = await _vlogFoldersBaseDir();
    final movableFolders = names
        .where((name) => !_isReservedVlogAlbum(name))
        .toSet();

    // 프로젝트 메타데이터도 함께 보정 (폴더 삭제 시 휴지통으로 이동)
    final projectsToTrash = vlogProjects
        .where((p) => movableFolders.contains(p.folderName))
        .toList();
    for (final project in projectsToTrash) {
      await saveProject(
        project.copyWith(
          folderName: '휴지통',
          trashedFromFolderName: project.folderName,
        ),
      );
    }

    for (var name in names) {
      if (_isReservedVlogAlbum(name)) continue;
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        for (var file in dir.listSync().whereType<File>()) {
          final trashDir = Directory(p.join(base.path, '휴지통'));
          if (!await trashDir.exists()) await trashDir.create(recursive: true);
          final trashName = "${name}__${p.basename(file.path)}";
          final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
          try {
            await file.rename(destPath);
          } catch (_) {
            await file.copy(destPath);
            await file.delete();
          }
        }
        await dir.delete(recursive: true);
      }
    }

    notifyListeners();
  }

  Future<void> moveToTrash(String path) async {
    final trashDir = Directory(p.join((await _rawBaseDir()).path, '휴지통'));
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    final trashName = "${currentAlbum}__${p.basename(path)}";
    final destPath = await _buildUniqueFilePath(trashDir.path, trashName);
    await File(path).copy(destPath);
    await File(path).delete();
    await _moveClipOwnershipPath(path, destPath);
    await _moveDurationCachePath(path, destPath);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> restoreClip(String trashPath) async {
    final base = await _rawBaseDir();
    final fileName = p.basename(trashPath);
    String target = "일상";

    if (fileName.contains("__")) {
      final parts = fileName.split("__");
      final originAlbum = parts[0];
      final dir = Directory(p.join(base.path, originAlbum));
      if (await dir.exists()) {
        target = originAlbum;
      }
    }

    final newName = fileName.contains("__")
        ? fileName.split("__").sublist(1).join("__")
        : fileName;
    final targetDir = Directory(p.join(base.path, target));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final destPath = await _buildUniqueFilePath(targetDir.path, newName);
    await File(trashPath).copy(destPath);
    await File(trashPath).delete();
    await _moveClipOwnershipPath(trashPath, destPath);
    await _moveDurationCachePath(trashPath, destPath);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  // ✅ Vlog Trash Support
  Future<void> moveVlogToTrash(String path) async {
    final trashDir = Directory(
      p.join((await _vlogFoldersBaseDir()).path, '휴지통'),
    );
    if (!await trashDir.exists()) await trashDir.create(recursive: true);

    // Prefix with Origin Folder for Restore
    final origin = currentVlogFolder.isEmpty ? "기본" : currentVlogFolder;
    final trashName = "${origin}__${p.basename(path)}";
    final destPath = await _buildUniqueFilePath(trashDir.path, trashName);

    await File(path).copy(destPath);
    await File(path).delete();

    notifyListeners();
    // Refresh list if needed (handled by screen)
  }

  Future<void> restoreVlog(String trashPath) async {
    final base = await _vlogFoldersBaseDir();
    final fileName = p.basename(trashPath);
    String target = "기본";

    if (fileName.contains("__")) {
      final parts = fileName.split("__");
      final originFolder = parts[0];
      final dir = Directory(p.join(base.path, originFolder));
      if (await dir.exists()) {
        target = originFolder;
      }
    }

    final newName = fileName.contains("__")
        ? fileName.split("__").sublist(1).join("__")
        : fileName;
    final targetDir = Directory(p.join(base.path, target));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final destPath = await _buildUniqueFilePath(targetDir.path, newName);

    await File(trashPath).copy(destPath);
    await File(trashPath).delete();

    notifyListeners();
  }

  Future<void> executeTransfer(
    String target,
    bool isMove,
    List<String> list,
  ) async {
    if (isMove) {
      // 이동: 대상 폴더로 이동 (moveClipsBatch가 이미 rename 처리)
      await moveClipsBatch(list, target);
    } else {
      // 복사: 대상 폴더로 복사하고 원본 유지
      final targetDir = await _rawAlbumDir(target);
      for (var sourcePath in list) {
        final dest = await _buildUniqueFilePath(
          targetDir.path,
          p.basename(sourcePath),
        );
        await File(sourcePath).copy(dest);
        await _copyClipOwnershipPath(sourcePath, dest);
        await _copyDurationCachePath(sourcePath, dest);
      }
    }
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<String> _buildUniqueFilePath(String dirPath, String baseName) async {
    String candidate = p.join(dirPath, baseName);
    if (!await File(candidate).exists()) return candidate;

    final name = p.basenameWithoutExtension(baseName);
    final ext = p.extension(baseName);
    int index = 1;
    while (true) {
      candidate = p.join(dirPath, '${name}_$index$ext');
      if (!await File(candidate).exists()) return candidate;
      index++;
    }
  }

  Future<String?> getFirstClipPath(String n) async {
    if (n == "Vlog") {
      if (vlogProjectPaths.isNotEmpty) {
        final project = vlogProjects.firstWhere(
          (p) => p.id == vlogProjectPaths.first,
          orElse: () => vlogProjects.first,
        );
        return project.clips.isNotEmpty ? project.clips.first.path : null;
      }
      final projects = await _listProjectFiles();
      vlogProjectPaths = projects;
      // We can't easily get the first clip path without loading the project json.
      // For now, return null or try loading the first project.
      // Optimization: assuming loadProjects() was called.
      if (vlogProjects.isNotEmpty) {
        return vlogProjects.first.clips.isNotEmpty
            ? vlogProjects.first.clips.first.path
            : null;
      }
      return null;
    }
    final dir = Directory(p.join((await _rawBaseDir()).path, n));
    if (!await dir.exists()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .toList();
    return files.isNotEmpty ? files.first.path : null;
  }

  Future<int> getClipCount(String name) async {
    if (name == "Vlog") {
      return vlogProjectPaths.length;
    }
    final dir = Directory(p.join((await _rawBaseDir()).path, name));
    if (!await dir.exists()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .length;
  }

  Future<void> deletePermanently(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _clipTransferUiStateByPath.remove(path);
    await _removeClipOwnershipForPath(path);
    await _removeLocalIndexByKey(path);
    await _removeDurationCacheForPath(path);
    notifyListeners();
    await _updateAlbumClipCounts();
  }

  Future<void> _loadCloudSyncedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_cloudSyncedKey) ?? [];
    _cloudSyncedPaths
      ..clear()
      ..addAll(stored.where((path) => File(path).existsSync()));
  }

  Future<void> _persistCloudSyncedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cloudSyncedKey, _cloudSyncedPaths.toList());
  }

  Future<void> _cleanupCloudSyncedPaths() async {
    final removed = _cloudSyncedPaths
        .where((path) => !File(path).existsSync())
        .toList();
    if (removed.isEmpty) return;
    _cloudSyncedPaths.removeAll(removed);
    await _persistCloudSyncedPaths();
  }

  String? getClipOwnerAccountId(String path) => _clipOwnerAccountByPath[path];

  String getClipLockState(String path) => 'unlocked';

  bool isClipLocked(String path) => false;

  String getClipStatusBadge(String path) {
    final transferState = getClipTransferUiState(path);
    switch (transferState) {
      case ClipTransferUiState.pendingUpload:
      case ClipTransferUiState.pendingDownload:
        return '로딩중';
      case ClipTransferUiState.failedUpload:
      case ClipTransferUiState.failedDownload:
        return '동기화 실패';
      case null:
        break;
    }

    if (isClipCloudSynced(path)) return '동기화됨';
    return '기기';
  }

  bool isClipVisibleByStorageFilter(String path, String filter) {
    switch (filter) {
      case 'device':
        return !isClipCloudSynced(path);
      case 'cloud':
        return isClipCloudSynced(path);
      case 'all':
      default:
        return true;
    }
  }

  Future<void> recalculateLockStatesForAccount(String? currentUid) async {
    // Deprecated: clip lock feature removed.
    notifyListeners();
  }

  Future<void> handleLogoutLocalData({
    required String? ownerAccountId,
    required String policy,
  }) async {
    if (ownerAccountId == null) return;

    if (policy == 'delete') {
      final allClips = await _listAllClipPaths();
      for (final path in allClips) {
        if (_clipOwnerAccountByPath[path] != ownerAccountId) continue;
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        await _removeClipOwnershipForPath(path);
      }

      final ownedProjects = vlogProjects
          .where((p) => p.ownerAccountId == ownerAccountId)
          .map((p) => p.id)
          .toList();
      for (final id in ownedProjects) {
        await deleteProject(id);
      }
      await _updateAlbumClipCounts();
      return;
    }

    // Deprecated policy: clip lock feature removed.
  }

  Future<List<String>> _listAllClipPaths() async {
    final base = await _rawBaseDir();
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp4'))
        .map((file) => file.path)
        .toList();
  }

  Future<String> saveMergedProject(
    String sourcePath,
    String targetVlogFolder,
  ) async {
    final folderDir = await _vlogFolderDir(targetVlogFolder);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(folderDir.path, baseName);
    final destFile = File(candidate);
    if (await destFile.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      candidate = p.join(
        folderDir.path,
        "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}",
      );
    }
    await File(sourcePath).copy(candidate);
    await loadVlogsFromCurrentFolder();
    await markClipCloudSynced(candidate);
    return candidate;
  }

  Future<Directory> getAppDocDir() async =>
      await getApplicationDocumentsDirectory();

  Future<void> saveExtractedClip(String sourcePath, String targetAlbum) async {
    final albumDir = await _rawAlbumDir(targetAlbum);
    final baseName = p.basename(sourcePath);
    String candidate = p.join(albumDir.path, baseName);

    // 타임스탬프로 이름 고유화
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // clip_prefix 없으면 붙이기
    if (!baseName.startsWith("clip_")) {
      candidate = p.join(
        albumDir.path,
        "clip_${timestamp}_${p.basename(sourcePath)}",
      );
    } else {
      // 이미 clip_ 형식이면 뒤에 랜덤 숫자만 더해서 충돌 방지
      candidate = p.join(
        albumDir.path,
        "${p.basenameWithoutExtension(baseName)}_$timestamp${p.extension(baseName)}",
      );
    }

    await File(sourcePath).copy(candidate);
    final sourceOwner = getClipOwnerAccountId(sourcePath);
    if (sourceOwner != null) {
      await _copyClipOwnershipPath(sourcePath, candidate);
    } else {
      await _setClipOwnership(
        candidate,
        ownerAccountId: UserStatusManager().userId,
      );
    }
    await _copyDurationCachePath(sourcePath, candidate);

    // 현재 앨범이면 리스트 갱신
    if (currentAlbum == targetAlbum) {
      await loadClipsFromCurrentAlbum();
    }
    await _updateAlbumClipCounts();
  }

  Future<void> _setClipOwnership(
    String path, {
    required String? ownerAccountId,
  }) async {
    _clipOwnerAccountByPath[path] = ownerAccountId;
    await _persistClipOwnershipMetadata();
  }

  Future<void> _removeClipOwnershipForPath(String path) async {
    final changed = _clipOwnerAccountByPath.remove(path) != null;
    if (changed) {
      await _persistClipOwnershipMetadata();
    }
  }

  Future<void> _moveClipOwnershipPath(String oldPath, String newPath) async {
    final owner = _clipOwnerAccountByPath[oldPath];
    await _removeClipOwnershipForPath(oldPath);
    _clipOwnerAccountByPath[newPath] = owner;
    await _persistClipOwnershipMetadata();
    await _removeLocalIndexByKey(oldPath);
    await _upsertLocalIndexClip(newPath);
  }

  Future<void> _copyClipOwnershipPath(
    String sourcePath,
    String targetPath,
  ) async {
    _clipOwnerAccountByPath[targetPath] = _clipOwnerAccountByPath[sourcePath];
    await _persistClipOwnershipMetadata();
    await _upsertLocalIndexClip(targetPath);
  }

  Future<void> _upsertLocalIndexClip(String path) async {
    final entries = await _localIndexService.loadEntries();
    final owner = getClipOwnerAccountId(path) ?? UserStatusManager().userId;

    final entry = LocalIndexEntry(
      id: path,
      type: 'clip',
      pathOrKey: path,
      ownerAccountId: owner,
      lockState: 'unlocked',
      updatedAt: DateTime.now(),
    );

    final index = entries.indexWhere(
      (e) => e.pathOrKey == path && e.type == 'clip',
    );
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _upsertLocalIndexProject(VlogProject project) async {
    final entries = await _localIndexService.loadEntries();
    final entry = LocalIndexEntry(
      id: project.id,
      type: 'project',
      pathOrKey: project.id,
      ownerAccountId: project.ownerAccountId,
      lockState: project.lockState,
      updatedAt: DateTime.now(),
    );
    final index = entries.indexWhere(
      (e) => e.pathOrKey == project.id && e.type == 'project',
    );
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _removeLocalIndexByKey(String key) async {
    final entries = await _localIndexService.loadEntries();
    entries.removeWhere((e) => e.pathOrKey == key);
    await _localIndexService.saveEntries(entries);
  }

  Future<void> _loadClipOwnershipMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipOwnershipMetadataKey);
    _clipOwnerAccountByPath.clear();
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final owner = value['ownerAccountId'];
        _clipOwnerAccountByPath[key] = owner is String ? owner : null;
      });
    } catch (e) {
      debugPrint('[VideoManager] Failed to load clip ownership metadata: $e');
    }
  }

  Future<void> _persistClipOwnershipMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, Map<String, dynamic>>{};
    for (final entry in _clipOwnerAccountByPath.entries) {
      final path = entry.key;
      encoded[path] = {'ownerAccountId': entry.value};
    }
    await prefs.setString(_clipOwnershipMetadataKey, jsonEncode(encoded));
  }

  Future<void> _cleanupClipOwnershipMetadata() async {
    final allPaths = await _listAllClipPaths();
    final existing = allPaths.toSet();
    final removeTargets = _clipOwnerAccountByPath.keys
        .where((path) => !existing.contains(path))
        .toList();
    if (removeTargets.isEmpty) return;
    for (final path in removeTargets) {
      _clipOwnerAccountByPath.remove(path);
    }
    await _persistClipOwnershipMetadata();
  }

  Future<void> _loadClipDurationMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipDurationMetadataKey);
    if (raw == null || raw.isEmpty) {
      _persistedDurationMs.clear();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final loaded = <String, int>{};
      decoded.forEach((key, value) {
        if (key is String && value is num && value > 0) {
          loaded[key] = value.toInt();
        }
      });

      // 파일이 사라진 엔트리 정리
      loaded.removeWhere((path, _) => !File(path).existsSync());

      _persistedDurationMs
        ..clear()
        ..addAll(loaded);

      // 메모리 캐시에 바로 채워서 첫 화면 표시 속도 개선
      _persistedDurationMs.forEach((path, ms) {
        _durationCache[path] = Duration(milliseconds: ms);
      });

      await prefs.setString(
        _clipDurationMetadataKey,
        jsonEncode(_persistedDurationMs),
      );
    } catch (e) {
      debugPrint('[VideoManager] Failed to load clip duration metadata: $e');
    }
  }

  Future<void> _persistClipDurationMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _clipDurationMetadataKey,
      jsonEncode(_persistedDurationMs),
    );
  }

  Future<void> _setDurationCacheForPath(
    String path,
    Duration duration, {
    bool persist = true,
  }) async {
    if (duration <= Duration.zero) return;
    _durationCache[path] = duration;
    if (!persist) return;

    _persistedDurationMs[path] = duration.inMilliseconds;
    await _persistClipDurationMetadata();
  }

  Future<void> _removeDurationCacheForPath(String path) async {
    _durationCache.remove(path);
    if (_persistedDurationMs.remove(path) != null) {
      await _persistClipDurationMetadata();
    }
  }

  Future<void> _moveDurationCachePath(String oldPath, String newPath) async {
    final duration =
        _durationCache[oldPath] ??
        (_persistedDurationMs[oldPath] != null
            ? Duration(milliseconds: _persistedDurationMs[oldPath]!)
            : null);

    await _removeDurationCacheForPath(oldPath);
    if (duration != null) {
      await _setDurationCacheForPath(newPath, duration);
    }
  }

  Future<void> _copyDurationCachePath(
    String sourcePath,
    String targetPath,
  ) async {
    final duration =
        _durationCache[sourcePath] ??
        (_persistedDurationMs[sourcePath] != null
            ? Duration(milliseconds: _persistedDurationMs[sourcePath]!)
            : null);
    if (duration == null) return;
    await _setDurationCacheForPath(targetPath, duration);
  }
}

final VideoManager videoManager = VideoManager();
