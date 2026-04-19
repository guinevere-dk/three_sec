import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import '../models/vlog_project.dart';
import 'auth_service.dart';
import 'notification_settings_service.dart';
import 'sync_queue_store.dart';
import '../utils/error_copy.dart';
import 'review_fallback_metrics.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// 🌩️ 클라우드 백업 서비스 (Firebase Storage + Firestore)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// Standard 등급 이상의 핵심 혜택
/// - Standard: 50GB 저장 용량
/// - Premium: 200GB 저장 용량
///
/// 기능:
/// - 영상 업로드/다운로드 (용량 제한 준수)
/// - Firestore 메타데이터 동기화 (앨범, 즐겨찾기 등)
/// - 백그라운드 업로드 큐 (순차 처리)
/// - 진행률 스트림
/// - uid 기반 보안

class CloudService {
  static final CloudService _instance = CloudService._internal();
  factory CloudService() => _instance;
  CloudService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final UserStatusManager _userStatusManager = UserStatusManager();
  final SyncQueueStore _syncQueueStore = SyncQueueStore();
  final ReviewFallbackMetrics _reviewFallbackMetrics = ReviewFallbackMetrics();

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📦 상수 정의
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 등급별 저장 용량 제한 (바이트)
  static const int _standardStorageLimit = 50 * 1024 * 1024 * 1024; // 50GB
  static const int _premiumStorageLimit = 200 * 1024 * 1024 * 1024; // 200GB
  static const int _maxRetryAttempts = 5;

  static const String _errorAuthRequired = 'auth_required';
  static const String _errorGuestModeBlocked = 'guest_mode_blocked';
  static const String _errorTierRequired = 'tier_required';
  static const String _errorStorageLimit = 'storage_limit';
  static const String _errorCloudApiDisabled = 'cloud_api_disabled';
  static const String _errorPermissionDenied = 'permission_denied';
  static const String _errorNetwork = 'network_unavailable';
  static const String _errorQuota = 'quota_exceeded';
  static const String _errorUploadFailed = 'upload_failed';
  static const String _errorFileSystem = 'file_system_error';
  static const String _errorNotFound = 'resource_not_found';

  /// Firestore 컬렉션 경로
  static const String _videosCollection = 'videos';
  static const String _vlogProjectsCollection = 'vlog_projects';
  static const String _usersCollection = 'users';
  static const String _usageEventsCollection = 'usageEvents';

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📤 업로드 큐 관리
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final List<UploadTask> _uploadQueue = [];
  final StreamController<UploadProgress> _progressController =
      StreamController<UploadProgress>.broadcast();
  final StreamController<SyncStatusSummary> _syncSummaryController =
      StreamController<SyncStatusSummary>.broadcast();

  bool _isProcessingQueue = false;
  bool _syncJobsLoaded = false;
  bool _isRestoringUploadQueue = false;
  List<SyncJob> _syncJobs = [];
  String? _lastImmediateUploadErrorCode;
  String? _lastImmediateUploadErrorCopy;
  final Map<String, Future<CloudPurgeResult>> _purgeInFlightByUid = {};

  /// 업로드 진행률 스트림
  Stream<UploadProgress> get uploadProgressStream => _progressController.stream;
  Stream<SyncStatusSummary> get syncSummaryStream =>
      _syncSummaryController.stream;
  String? get lastImmediateUploadErrorCode => _lastImmediateUploadErrorCode;
  String? get lastImmediateUploadErrorCopy => _lastImmediateUploadErrorCopy;

  void clearLastImmediateUploadError() {
    _lastImmediateUploadErrorCode = null;
    _lastImmediateUploadErrorCopy = null;
  }

  Future<void> initializeQueueStore() async {
    if (_syncJobsLoaded) return;
    _syncJobs = await _syncQueueStore.loadJobs();
    _syncJobsLoaded = true;
  }

  /// 앱 시작/복귀/로그인 복귀 시 저장된 업로드 큐를 재정렬 및 재시작
  Future<void> restoreUploadQueueFromStore() async {
    if (_isRestoringUploadQueue) return;
    _isRestoringUploadQueue = true;

    try {
      await _ensureQueueStoreLoaded();

      final uid = _getCurrentUserId();
      if (uid == null) {
        print('[CloudService] ⛔ 큐 복구 스킵: 로그인 사용자 미확인');
        return;
      }

      final recoverable = _syncJobs.where(_isRecoverableUploadJob).toList();
      if (recoverable.isEmpty) {
        print('[CloudService] 🔁 복구 대상 업로드 큐 없음');
        return;
      }

      var restored = 0;
      var skipped = 0;

      for (final job in recoverable) {
        if (job.ownerUid != null && job.ownerUid != uid) {
          skipped += 1;
          continue;
        }

        if (job.localPath == null ||
            job.localPath!.trim().isEmpty ||
            job.storagePath == null ||
            job.storagePath!.trim().isEmpty) {
          print(
            '[CloudService] ⚠️ 복구 스킵: 동기화 메타데이터 누락 '
            '(videoId=${job.entityId}, localPath=${job.localPath}, storagePath=${job.storagePath})',
          );
          skipped += 1;
          continue;
        }

        final file = File(job.localPath!);
        if (!await file.exists()) {
          print(
            '[CloudService] ⚠️ 복구 스킵: 로컬 파일 미존재 '
            '(videoId=${job.entityId}, localPath=${job.localPath})',
          );
          skipped += 1;
          continue;
        }

        final dedupeKey = _uploadTaskDedupeKey(
          localPath: job.localPath,
          projectId: job.projectId,
          createdAt: job.createdAt,
        );

        if (_hasUploadTaskForDedupeKey(
          key: dedupeKey,
          videoId: job.entityId,
          storagePath: job.storagePath!,
          localPath: job.localPath,
          includeSyncJobs: false,
        )) {
          print(
            '[CloudService] 🔁 복구 큐 중복 스킵 '
            '(videoId=${job.entityId}, dedupe=$dedupeKey)',
          );
          skipped += 1;
          continue;
        }

        final availableAt = _restoreAvailableAt(job);
        _uploadQueue.add(
          UploadTask(
            videoFile: file,
            videoId: job.entityId,
            storagePath: job.storagePath!,
            fileSize: await file.length(),
            uid: uid,
            localPath: job.localPath,
            projectId: job.projectId,
            attemptCount: job.attemptCount,
            createdAt: job.createdAt,
            availableAt: availableAt,
          ),
        );

        await _setSyncJobStateForVideo(
          videoId: job.entityId,
          status: SyncJobStatus.inProgress,
          attemptCount: job.attemptCount,
        );
        restored += 1;
      }

      print(
        '[CloudService] 🔁 업로드 큐 복구 완료: restored=$restored, skipped=$skipped, '
        'queueDepth=${_uploadQueue.length}',
      );

      if (restored > 0 && !_isProcessingQueue) {
        _processUploadQueue();
      }
    } finally {
      _isRestoringUploadQueue = false;
    }
  }

  bool _isRecoverableUploadJob(SyncJob job) {
    if (job.entityType != SyncJobEntityType.clip || job.action != SyncJobAction.upload) {
      return false;
    }

    return _isActiveUploadJobStatus(job.status);
  }

  bool _isActiveUploadJobStatus(SyncJobStatus status) {
    return status == SyncJobStatus.queued ||
        status == SyncJobStatus.inProgress ||
        status == SyncJobStatus.failed;
  }

  DateTime? _restoreAvailableAt(SyncJob job) {
    if (job.status == SyncJobStatus.failed) {
      if (job.nextRetryAt == null) return DateTime.now();
      return job.nextRetryAt;
    }

    return null;
  }

  String _uploadTaskDedupeKey({
    required String? localPath,
    required String? projectId,
    required DateTime createdAt,
  }) {
    return '${localPath ?? ''}|${projectId ?? ''}|${createdAt.toIso8601String()}';
  }

  bool _hasUploadTaskForDedupeKey({
    required String key,
    required String videoId,
    required String storagePath,
    String? localPath,
    bool includeSyncJobs = true,
  }) {
    if (_uploadQueue.any(
      (task) =>
          _uploadTaskDedupeKey(
            localPath: task.localPath,
            projectId: task.projectId,
            createdAt: task.createdAt,
          ) ==
            key ||
          task.videoId == videoId ||
          task.storagePath == storagePath ||
          (localPath != null && task.localPath != null && task.localPath == localPath),
    )) {
      return true;
    }

    if (!includeSyncJobs) {
      return false;
    }

    return _syncJobs.any(
      (task) =>
          task.entityType == SyncJobEntityType.clip &&
          task.action == SyncJobAction.upload &&
          _isActiveUploadJobStatus(task.status) &&
          (task.entityId == videoId ||
              task.storagePath == storagePath ||
              (localPath != null &&
                  task.localPath != null &&
                  task.localPath == localPath)),
    );
  }

  int _nextAttemptCountForVideo(String videoId) {
    final index = _syncJobs.indexWhere(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.entityId == videoId &&
          j.action == SyncJobAction.upload,
    );
    if (index == -1) return 0;
    return _syncJobs[index].attemptCount;
  }

  Future<void> _setSyncJobStateForVideo({
    required String videoId,
    required SyncJobStatus status,
    required int attemptCount,
    DateTime? nextRetryAt,
    String? errorCode,
    String? errorMessage,
  }) async {
    await _ensureQueueStoreLoaded();

    final index = _syncJobs.indexWhere(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.entityId == videoId &&
          j.action == SyncJobAction.upload,
    );

    if (index == -1) return;

    final prev = _syncJobs[index];
    _syncJobs[index] = SyncJob(
      id: prev.id,
      entityType: prev.entityType,
      entityId: prev.entityId,
      action: prev.action,
      ownerUid: prev.ownerUid,
      status: status,
      storagePath: prev.storagePath,
      projectId: prev.projectId,
      localPath: prev.localPath,
      attemptCount: attemptCount,
      createdAt: prev.createdAt,
      nextRetryAt: nextRetryAt,
      lastErrorCode: errorCode ?? prev.lastErrorCode,
      lastErrorMessage: errorMessage ?? prev.lastErrorMessage,
    );

    await _syncQueueStore.saveJobs(_syncJobs);
  }

  Future<void> _ensureQueueStoreLoaded() async {
    if (_syncJobsLoaded) return;
    await initializeQueueStore();
  }

  bool _isStorageObjectNotFound(FirebaseException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toLowerCase();
    return code == 'object-not-found' ||
        message.contains('object does not exist at location') ||
        (message.contains('not found') && message.contains('404'));
  }

  bool _ensureNotGuestForCloud(String operation) {
    if (!_authService.isGuest) return true;

    print('[CloudService] ✗ 게스트 모드 차단: $operation');
    unawaited(
      _reviewFallbackMetrics.recordCloudAccessBlocked(
        operation: operation,
        reason: 'guest_mode',
      ),
    );
    return false;
  }

  SettableMetadata _buildVideoMetadata(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    final contentType = switch (ext) {
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.avi' => 'video/x-msvideo',
      '.mpeg' || '.mpg' => 'video/mpeg',
      _ => 'video/mp4',
    };

    return SettableMetadata(contentType: contentType);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🔐 보안 검증
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 사용자 인증 확인
  String? _getCurrentUserId() {
    if (_authService.isGuest) {
      print('[CloudService] ✗ 게스트 모드에서는 인증 기반 조회가 비활성입니다.');
      return null;
    }

    final user = _authService.currentUser;
    if (user == null) {
      print('[CloudService] ✗ 로그인 필요 (auth.currentUser=null)');
      return null;
    }
    return user.uid;
  }

  /// Standard 등급 이상 확인
  bool _checkStandardOrAbove() {
    if (!_userStatusManager.isStandardOrAbove()) {
      print(
        '[CloudService] ✗ Standard 등급 이상 필요 (현재: ${_userStatusManager.currentTier})',
      );
      return false;
    }
    return true;
  }

  /// 저장 용량 제한 확인
  Future<bool> _checkStorageLimit(int fileSize) async {
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    // 현재 사용량 조회
    final currentUsage = await _getCurrentStorageUsage(uid);

    // 등급별 제한
    final limit = switch (_userStatusManager.currentTier) {
      UserTier.premium => _premiumStorageLimit,
      UserTier.standard => _standardStorageLimit,
      UserTier.free => 0,
    };

    final afterUpload = currentUsage + fileSize;

    if (afterUpload > limit) {
      final usageGB = (currentUsage / (1024 * 1024 * 1024)).toStringAsFixed(2);
      final limitGB = (limit / (1024 * 1024 * 1024)).toStringAsFixed(0);
      print('[CloudService] ✗ 저장 용량 초과: ${usageGB}GB / ${limitGB}GB');
      return false;
    }

    return true;
  }

  /// 현재 저장 용량 사용량 조회
  Future<int> _getCurrentStorageUsage(String uid) async {
    try {
      final snapshot = await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .get();

      if (snapshot.exists) {
        return snapshot.data()?['storageUsage'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService] ✗ 사용량 조회 실패: $e '
        '(requestedUid=$uid, authUid=$authUid, signedIn=${_authService.isSignedIn})',
      );
      return 0;
    }
  }

  String _usageEventId(String videoId, String reason) => '${reason}_$videoId';

  /// 저장 용량 사용량 업데이트 (멱등 + 음수 방지)
  Future<void> _updateStorageUsageIdempotent({
    required String uid,
    required String videoId,
    required int delta,
    required String reason,
  }) async {
    final eventId = _usageEventId(videoId, reason);
    final userRef = _firestore.collection(_usersCollection).doc(uid);
    final eventRef = userRef.collection(_usageEventsCollection).doc(eventId);

    try {
      await _firestore.runTransaction((tx) async {
        final eventSnap = await tx.get(eventRef);
        if (eventSnap.exists) {
          print('[CloudService] usage 이벤트 중복 스킵: $eventId');
          return;
        }

        final userSnap = await tx.get(userRef);
        final currentUsage = userSnap.data()?['storageUsage'] as int? ?? 0;
        final nextUsage = max(0, currentUsage + delta);
        final appliedDelta = nextUsage - currentUsage;

        tx.set(userRef, {
          'storageUsage': nextUsage,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(eventRef, {
          'uid': uid,
          'videoId': videoId,
          'reason': reason,
          'deltaRequested': delta,
          'deltaApplied': appliedDelta,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      print(
        '[CloudService] ✓ 사용량 업데이트(멱등): '
        'event=$eventId, delta=${delta > 0 ? '+' : ''}${(delta / (1024 * 1024)).toStringAsFixed(2)}MB',
      );
    } catch (e) {
      print('[CloudService] ✗ 사용량 업데이트 실패(event=$eventId): $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📤 업로드 기능
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 영상 업로드 (큐에 추가)
  ///
  /// [videoFile] 업로드할 영상 파일
  /// [albumName] 앨범 이름
  /// [isFavorite] 즐겨찾기 여부
  ///
  /// 반환: 업로드 작업 ID (Firestore 문서 ID)
  Future<String?> uploadVideo({
    required File videoFile,
    required String albumName,
    bool isFavorite = false,
    String? localPath,
  }) async {
    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[CloudService] 📤 업로드 요청');
    print('[CloudService]   - 파일: ${p.basename(videoFile.path)}');
    print('[CloudService]   - 앨범: $albumName');
    print('[CloudService]   - 즐겨찾기: $isFavorite');

    if (!_ensureNotGuestForCloud('클라우드 이동')) {
      return null;
    }

    // 1. 보안 검증
    final uid = _getCurrentUserId();
    if (uid == null) return null;

    if (!_checkStandardOrAbove()) {
      return null;
    }

    // 2. 파일 크기 확인
    final fileSize = await videoFile.length();
    print(
      '[CloudService]   - 파일 크기: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB',
    );

    // 3. 용량 제한 확인
    if (!await _checkStorageLimit(fileSize)) {
      return null;
    }

    // 4. Firestore 메타데이터 생성
    final videoId = _firestore.collection(_videosCollection).doc().id;
    final fileName = p.basename(videoFile.path);
    final storagePath = 'users/$uid/videos/$videoId/$fileName';

    try {
      // Firestore 메타데이터 저장
      await _firestore.collection(_videosCollection).doc(videoId).set({
        'uid': uid,
        'videoId': videoId,
        'fileName': fileName,
        'storagePath': storagePath,
        if (localPath != null) 'localPath': localPath,
        'albumName': albumName,
        'isFavorite': isFavorite,
        'fileSize': fileSize,
        'uploadStatus': 'queued',
        'uploadProgress': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('[CloudService] ✓ 메타데이터 생성: $videoId');

      // 5. 업로드 큐에 추가
      await _addToUploadQueue(
        videoFile: videoFile,
        videoId: videoId,
        storagePath: storagePath,
        fileSize: fileSize,
        uid: uid,
        localPath: localPath,
      );

      return videoId;
    } catch (e) {
      print('[CloudService] ✗ 업로드 준비 실패: $e');
      return null;
    }
  }

  Future<String?> uploadVideoImmediate({
    required File videoFile,
    required String albumName,
    bool isFavorite = false,
    String? localPath,
  }) async {
    clearLastImmediateUploadError();

    if (!_ensureNotGuestForCloud('클라우드 이동')) {
      _lastImmediateUploadErrorCode = _errorGuestModeBlocked;
      _lastImmediateUploadErrorCopy =
          '게스트 모드에서는 클라우드 이동이 비활성입니다. 로그인 후 이용해 주세요.';
      return null;
    }

    final uid = _getCurrentUserId();
    if (uid == null) {
      _lastImmediateUploadErrorCode = _errorAuthRequired;
      _lastImmediateUploadErrorCopy = '로그인이 필요해요. 다시 로그인한 뒤 클라우드 이동을 재시도해주세요.';
      return null;
    }
    if (!_checkStandardOrAbove()) {
      _lastImmediateUploadErrorCode = _errorTierRequired;
      _lastImmediateUploadErrorCopy =
          '클라우드 이동은 Standard 이상에서 사용할 수 있어요. 플랜을 확인해주세요.';
      return null;
    }

    final fileSize = await videoFile.length();
    if (!await _checkStorageLimit(fileSize)) {
      _lastImmediateUploadErrorCode = _errorStorageLimit;
      _lastImmediateUploadErrorCopy =
          '저장 용량이 부족해 클라우드 이동에 실패했어요. 용량 정리 후 다시 시도해주세요.';
      return null;
    }

    final videoId = _firestore.collection(_videosCollection).doc().id;
    final fileName = p.basename(videoFile.path);
    final storagePath = 'users/$uid/videos/$videoId/$fileName';

    try {
      await _firestore.collection(_videosCollection).doc(videoId).set({
        'uid': uid,
        'videoId': videoId,
        'fileName': fileName,
        'storagePath': storagePath,
        if (localPath != null) 'localPath': localPath,
        'albumName': albumName,
        'isFavorite': isFavorite,
        'fileSize': fileSize,
        'uploadStatus': 'uploading',
        'uploadProgress': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final metadata = _buildVideoMetadata(videoFile.path);
      print(
        '[CloudService][Diag] immediate upload metadata: ${metadata.contentType}',
      );
      final ref = _storage.ref().child(storagePath);
      final task = await ref.putFile(videoFile, metadata);
      final downloadUrl = await task.ref.getDownloadURL();

      await _firestore.collection(_videosCollection).doc(videoId).update({
        'uploadStatus': 'completed',
        'uploadProgress': 100,
        'downloadUrl': downloadUrl,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _updateStorageUsageIdempotent(
        uid: uid,
        videoId: videoId,
        delta: fileSize,
        reason: 'upload_completed',
      );
      if (localPath != null) {
        await VideoManager().markClipCloudSynced(localPath);
      }
      clearLastImmediateUploadError();
      return videoId;
    } catch (e) {
      final detail = _classifySyncError(e.toString());
      _lastImmediateUploadErrorCode = detail.code;
      _lastImmediateUploadErrorCopy = detail.copy;

      await _safeUpdateFailureMetadata(
        videoId: videoId,
        detail: detail,
        rawError: e.toString(),
        phase: 'immediate_upload',
      );

      print(
        '[CloudService] ✗ 즉시 업로드 실패 '
        '(code=${detail.code}, retryable=${detail.retryable}): $e',
      );
      return null;
    }
  }

  /// 업로드 큐에 작업 추가
  Future<void> _addToUploadQueue({
    required File videoFile,
    required String videoId,
    required String storagePath,
    required int fileSize,
    required String uid,
    String? localPath,
  }) async {
    await _ensureQueueStoreLoaded();

    final now = DateTime.now();
    final projectId = localPath != null ? p.dirname(localPath).split('/').last : null;
    final dedupeKey = _uploadTaskDedupeKey(
      localPath: localPath,
      projectId: projectId,
      createdAt: now,
    );

    final hasQueuedTaskDuplicate = _hasUploadTaskForDedupeKey(
      key: dedupeKey,
      videoId: videoId,
      storagePath: storagePath,
      localPath: localPath,
      includeSyncJobs: false,
    );

    final hasActiveSyncDuplicate = _syncJobs.any(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.action == SyncJobAction.upload &&
          _isActiveUploadJobStatus(j.status) &&
          (j.entityId == videoId ||
              j.storagePath == storagePath ||
              (localPath != null &&
                  j.localPath != null &&
                  j.localPath == localPath)),
    );

    final existing = _syncJobs.any(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.entityId == videoId &&
          j.action == SyncJobAction.upload &&
          _isActiveUploadJobStatus(j.status),
    );

    if (!existing) {
      _syncJobs.add(
        SyncJob(
          id: 'clip:$videoId:upload',
          entityType: SyncJobEntityType.clip,
          entityId: videoId,
          action: SyncJobAction.upload,
          ownerUid: uid,
          status: SyncJobStatus.queued,
          storagePath: storagePath,
          localPath: localPath,
          attemptCount: 0,
          createdAt: now,
        ),
      );
      await _syncQueueStore.saveJobs(_syncJobs);
    }

    if (hasQueuedTaskDuplicate) {
      print(
        '[CloudService] ⚠️ 큐 중복 삽입 스킵: '
        '(videoId=$videoId, dedupe=$dedupeKey)',
      );
      return;
    }

    if (hasActiveSyncDuplicate && !existing) {
      print(
        '[CloudService] ⚠️ 동기화 작업 중복 삽입 스킵: '
        '(videoId=$videoId, storagePath=$storagePath, localPath=$localPath)',
      );
      return;
    }

    final attemptCount = _nextAttemptCountForVideo(videoId);

    if (existing) {
      await _setSyncJobStateForVideo(
        videoId: videoId,
        status: SyncJobStatus.inProgress,
        attemptCount: attemptCount,
        nextRetryAt: null,
      );
    }

    final uploadTask = UploadTask(
      videoFile: videoFile,
      videoId: videoId,
      storagePath: storagePath,
      fileSize: fileSize,
      uid: uid,
      localPath: localPath,
      projectId: projectId,
      attemptCount: attemptCount,
      createdAt: now,
    );

    _uploadQueue.add(uploadTask);
    print('[CloudService] ✓ 큐에 추가 (큐 크기: ${_uploadQueue.length})');

    // 큐 처리 시작
    if (!_isProcessingQueue) {
      _processUploadQueue();
    }
  }

  /// 업로드 큐 순차 처리
  Future<void> _processUploadQueue() async {
    if (!_ensureNotGuestForCloud('백그라운드 업로드')) {
      _uploadQueue.clear();
      return;
    }

    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    print('[CloudService] 🔄 큐 처리 시작');

    while (_uploadQueue.isNotEmpty) {
      final task = _uploadQueue.removeAt(0);

      if (task.availableAt != null &&
          DateTime.now().isBefore(task.availableAt!)) {
        _uploadQueue.add(task);
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      await _executeUpload(task);
    }

    _isProcessingQueue = false;
    print('[CloudService] ✓ 큐 처리 완료');
  }

  /// 실제 업로드 실행
  Future<void> _executeUpload(UploadTask task) async {
    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[CloudService] ⚡ 업로드 시작: ${task.videoId}');
    final authUidAtStart = _authService.currentUser?.uid;
    print(
      '[CloudService][Diag] upload context '
      'taskUid=${task.uid}, authUid=$authUidAtStart, '
      'signedIn=${_authService.isSignedIn}, path=${task.storagePath}',
    );

  try {
      // Firebase Storage 업로드
      final metadata = _buildVideoMetadata(task.videoFile.path);
      print(
        '[CloudService][Diag] queue upload metadata: ${metadata.contentType}',
      );
      final ref = _storage.ref().child(task.storagePath);
      final uploadTask = ref.putFile(task.videoFile, metadata);

      // 진행률 모니터링
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        final progressPercent = (progress * 100).toInt();

        // Firestore 진행률 업데이트
        _firestore.collection(_videosCollection).doc(task.videoId).update({
          'uploadProgress': progressPercent,
          'uploadStatus': 'uploading',
        });

        // 스트림 발행
        _progressController.add(
          UploadProgress(
            videoId: task.videoId,
            progress: progress,
            bytesTransferred: snapshot.bytesTransferred,
            totalBytes: snapshot.totalBytes,
          ),
        );

        if (progressPercent % 20 == 0) {
          print('[CloudService] 📊 진행률: $progressPercent%');
        }
      });

      // 업로드 완료 대기
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Firestore 업데이트 (완료)
      await _firestore.collection(_videosCollection).doc(task.videoId).update({
        'uploadStatus': 'completed',
        'uploadProgress': 100,
        'downloadUrl': downloadUrl,
        'completedAt': FieldValue.serverTimestamp(),
      });

      // 사용량 업데이트
      await _updateStorageUsageIdempotent(
        uid: task.uid,
        videoId: task.videoId,
        delta: task.fileSize,
        reason: 'upload_completed',
      );

      if (task.localPath != null) {
        await VideoManager().markClipCloudSynced(task.localPath!);
      }

      await _setSyncJobStateForVideo(
        videoId: task.videoId,
        status: SyncJobStatus.completed,
        attemptCount: task.attemptCount,
      );
      await _removeSyncJobForVideo(task.videoId);

      print('[CloudService] ✓ 업로드 완료: ${task.videoId}');
      print('[CloudService]   - URL: $downloadUrl');
  } catch (e) {
      final authUidOnError = _authService.currentUser?.uid;
      final detail = _classifySyncError(e.toString());
      print(
        '[CloudService] ✗ 업로드 실패 '
        '(code=${detail.code}, retryable=${detail.retryable}, attempt=${task.attemptCount + 1}): $e '
        '[diag taskUid=${task.uid}, authUid=$authUidOnError, signedIn=${_authService.isSignedIn}]',
      );

      await _safeUpdateFailureMetadata(
        videoId: task.videoId,
        detail: detail,
        rawError: e.toString(),
        phase: 'queue_upload',
      );

      final nextRetryAt = await _markSyncJobFailed(
        task.videoId,
        e.toString(),
        detail.code,
      );
      if (nextRetryAt == null) {
        await _setSyncJobStateForVideo(
          videoId: task.videoId,
          status: SyncJobStatus.failed,
          attemptCount: task.attemptCount + 1,
          errorCode: detail.code,
          errorMessage: e.toString(),
        );
      }
      if (detail.retryable &&
          nextRetryAt != null &&
          task.attemptCount < _maxRetryAttempts) {
        _uploadQueue.add(
          task.copyWith(
            attemptCount: task.attemptCount + 1,
            availableAt: nextRetryAt,
          ),
        );
        await _setSyncJobStateForVideo(
          videoId: task.videoId,
          status: SyncJobStatus.failed,
          attemptCount: task.attemptCount + 1,
          nextRetryAt: nextRetryAt,
          errorCode: detail.code,
          errorMessage: e.toString(),
        );
      } else if (!detail.retryable) {
        print('[CloudService] ⛔ 비재시도 오류로 큐 재시도 중단: ${detail.code}');
      }
    }
  }

  Future<void> _removeSyncJobForVideo(String videoId) async {
    await _ensureQueueStoreLoaded();
    _syncJobs.removeWhere(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.entityId == videoId &&
          j.action == SyncJobAction.upload,
    );
    await _syncQueueStore.saveJobs(_syncJobs);
  }

  Future<DateTime?> _markSyncJobFailed(
    String videoId,
    String error,
    String errorCode,
  ) async {
    await _ensureQueueStoreLoaded();
    final index = _syncJobs.indexWhere(
      (j) =>
          j.entityType == SyncJobEntityType.clip &&
          j.entityId == videoId &&
          j.action == SyncJobAction.upload,
    );
    if (index == -1) return null;

    final prev = _syncJobs[index];
    final attempt = prev.attemptCount + 1;
    final isTerminalFailure = _isNonRetryableErrorCode(errorCode) ||
        (!_classifySyncError(error).retryable) ||
        attempt >= _maxRetryAttempts;

    DateTime? nextRetryAt;
    if (!isTerminalFailure) {
      nextRetryAt = _computeBackoffWithJitter(attempt);
    }

    _syncJobs[index] = SyncJob(
      id: prev.id,
      entityType: prev.entityType,
      entityId: prev.entityId,
      action: prev.action,
      ownerUid: prev.ownerUid,
      status: SyncJobStatus.failed,
      storagePath: prev.storagePath,
      projectId: prev.projectId,
      localPath: prev.localPath,
      attemptCount: attempt,
      createdAt: prev.createdAt,
      lastErrorCode: errorCode,
      lastErrorMessage: error,
      nextRetryAt: nextRetryAt,
    );
    await _syncQueueStore.saveJobs(_syncJobs);
    return nextRetryAt;
  }

  bool _isNonRetryableErrorCode(String errorCode) {
    return errorCode == _errorAuthRequired ||
        errorCode == _errorGuestModeBlocked ||
        errorCode == _errorTierRequired ||
        errorCode == _errorPermissionDenied ||
        errorCode == _errorCloudApiDisabled ||
        errorCode == _errorStorageLimit ||
        errorCode == _errorQuota ||
        errorCode == _errorFileSystem ||
        errorCode == _errorNotFound;
  }

  DateTime _computeBackoffWithJitter(int attempt) {
    final bounded = attempt.clamp(1, _maxRetryAttempts);
    final baseMs = 1000 * (1 << (bounded - 1));
    final jitterMs = Random().nextInt(900);
    return DateTime.now().add(Duration(milliseconds: baseMs + jitterMs));
  }

  SyncErrorDetail _classifySyncError(String rawError) {
    final normalized = rawError.toLowerCase();

    if (normalized.contains('object-not-found') ||
        normalized.contains('storage/object-not-found') ||
        normalized.contains('object does not exist at location')) {
      return SyncErrorDetail(
        code: _errorNotFound,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('permission_denied') ||
        normalized.contains('permission denied') ||
        normalized.contains('unauthorized') ||
        normalized.contains('forbidden')) {
      return SyncErrorDetail(
        code: _errorPermissionDenied,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('not authenticated') ||
        normalized.contains('auth/currentuser is null') ||
        normalized.contains('auth required') ||
        normalized.contains('sign in')) {
      return SyncErrorDetail(
        code: _errorAuthRequired,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('cloud firestore api has not been used') ||
        normalized.contains('firestore.googleapis.com') ||
        normalized.contains('api is disabled')) {
      return SyncErrorDetail(
        code: _errorCloudApiDisabled,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('unavailable') ||
        normalized.contains('deadline-exceeded')) {
      return SyncErrorDetail(
        code: _errorNetwork,
        retryable: true,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('storage') ||
        normalized.contains('too large') ||
        normalized.contains('quota') ||
        normalized.contains('exceeded')) {
      if (normalized.contains('quota') || normalized.contains('exceeded')) {
        return SyncErrorDetail(
          code: _errorQuota,
          retryable: false,
          copy: ErrorCopy.syncFailureWithAction(rawError),
        );
      }

      if (normalized.contains('not found') ||
          normalized.contains('object-not-found') ||
          normalized.contains('does not exist')) {
        return SyncErrorDetail(
          code: _errorNotFound,
          retryable: false,
          copy: ErrorCopy.syncFailureWithAction(rawError),
        );
      }
    }

    if (normalized.contains('io exception') ||
        normalized.contains('filesystem') ||
        normalized.contains('no such file') ||
        normalized.contains('file not found') ||
        normalized.contains('os error')) {
      return SyncErrorDetail(
        code: _errorFileSystem,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    if (normalized.contains('firestore') ||
        normalized.contains('documentreference') ||
        normalized.contains('firestoreexception')) {
      return SyncErrorDetail(
        code: _errorUploadFailed,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(rawError),
      );
    }

    return SyncErrorDetail(
      code: _errorUploadFailed,
      retryable: true,
      copy: ErrorCopy.syncFailureWithAction(rawError),
    );
  }

  Future<void> _safeUpdateFailureMetadata({
    required String videoId,
    required SyncErrorDetail detail,
    required String rawError,
    required String phase,
  }) async {
    try {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag] failure metadata write '
        'videoId=$videoId, phase=$phase, authUid=$authUid, '
        'signedIn=${_authService.isSignedIn}, code=${detail.code}',
      );
      await _firestore.collection(_videosCollection).doc(videoId).update({
        'uploadStatus': 'failed',
        'errorCode': detail.code,
        'errorMessage': rawError,
        'errorCopy': detail.copy,
        'errorPhase': phase,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (metaErr) {
      print('[CloudService] ✗ 실패 메타데이터 기록 실패(videoId=$videoId): $metaErr');
    }
  }

  Future<SyncStatusSummary> getSyncStatusSummary() async {
    final uid = _getCurrentUserId();
    if (uid == null) {
      return const SyncStatusSummary();
    }

    try {
      final snapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .get();

      var queued = 0;
      var uploading = 0;
      var failed = 0;
      var completed = 0;

      for (final doc in snapshot.docs) {
        final status = (doc.data()['uploadStatus'] as String? ?? 'unknown')
            .toLowerCase();
        switch (status) {
          case 'queued':
            queued++;
            break;
          case 'uploading':
            uploading++;
            break;
          case 'failed':
            failed++;
            break;
          case 'completed':
            completed++;
            break;
          default:
            completed++;
            break;
        }
      }

      final summary = SyncStatusSummary(
        queuedCount: queued,
        uploadingCount: uploading,
        failedCount: failed,
        completedCount: completed,
      );
      _syncSummaryController.add(summary);
      return summary;
    } catch (_) {
      return const SyncStatusSummary();
    }
  }

  Future<void> enqueuePendingLocalUploads(
    VideoManager manager, {
    String trigger = 'manual',
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 자동 업로드')) return;

    final uid = _getCurrentUserId();
    if (uid == null) return;
    if (!_checkStandardOrAbove()) return;

    if (manager.recordedVideoPaths.isEmpty) {
      await manager.loadClipsFromCurrentAlbum();
    }

    for (final path in manager.recordedVideoPaths) {
      if (manager.isClipCloudSynced(path)) continue;
      final owner = manager.getClipOwnerAccountId(path);
      if (owner != null && owner != uid) continue;

      final file = File(path);
      if (!await file.exists()) continue;

      await uploadVideo(
        videoFile: file,
        albumName: manager.currentAlbum,
        localPath: path,
      );
    }

    print('[CloudService] auto upload trigger handled: $trigger');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📥 다운로드 기능
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 영상 다운로드
  ///
  /// [videoId] Firestore 영상 문서 ID
  /// [localPath] 로컬 저장 경로
  Future<bool> downloadVideo({
    required String videoId,
    required String localPath,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 다운로드')) return false;

    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[CloudService] 📥 다운로드 요청: $videoId');

    // 1. 보안 검증
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    if (!_checkStandardOrAbove()) {
      return false;
    }

    try {
      // 2. Firestore 메타데이터 조회
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();

      if (!doc.exists) {
        print('[CloudService] ✗ 영상을 찾을 수 없음');
        return false;
      }

      final data = doc.data()!;

      // 3. 소유권 확인 (보안)
      if (data['uid'] != uid) {
        print('[CloudService] ✗ 접근 권한 없음 (소유자: ${data['uid']})');
        return false;
      }

      final downloadUrl = data['downloadUrl'] as String?;
      if (downloadUrl == null) {
        print('[CloudService] ✗ 다운로드 URL 없음');
        return false;
      }

      // 4. Firebase Storage에서 다운로드
      final ref = _storage.refFromURL(downloadUrl);
      final file = File(localPath);

      await ref.writeToFile(file);

      print('[CloudService] ✓ 다운로드 완료: $localPath');
      return true;
    } catch (e) {
      print('[CloudService] ✗ 다운로드 실패: $e');
      return false;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🗂️ 메타데이터 관리
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 영상 메타데이터 업데이트
  Future<bool> updateVideoMetadata({
    required String videoId,
    String? albumName,
    bool? isFavorite,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 메타데이터 업데이트')) return false;

    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final updateData = <String, dynamic>{};

      if (albumName != null) updateData['albumName'] = albumName;
      if (isFavorite != null) updateData['isFavorite'] = isFavorite;

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .update(updateData);

      print('[CloudService] ✓ 메타데이터 업데이트: $videoId');
      return true;
    } catch (e) {
      print('[CloudService] ✗ 메타데이터 업데이트 실패: $e');
      return false;
    }
  }

  /// 사용자의 영상 목록 조회 (실시간 스트림)
  Stream<List<VideoMetadata>> getUserVideos({
    String? albumName,
    bool? isFavorite,
  }) {
    if (!_ensureNotGuestForCloud('클라우드 영상 목록 조회')) return Stream.value([]);

    final uid = _getCurrentUserId();
    if (uid == null) {
      return Stream.value([]);
    }

    Query query = _firestore
        .collection(_videosCollection)
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    if (albumName != null) {
      query = query.where('albumName', isEqualTo: albumName);
    }

    if (isFavorite != null) {
      query = query.where('isFavorite', isEqualTo: isFavorite);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return VideoMetadata.fromFirestore(doc);
      }).toList();
    });
  }

  /// 영상 삭제 (Storage + Firestore)
  Future<bool> deleteVideo(String videoId) async {
    if (!_ensureNotGuestForCloud('클라우드 영상 삭제')) return false;

    print('[CloudService] 🗑️ 삭제 요청: $videoId');

    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      // 1. Firestore 메타데이터 조회
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;

      // 2. 소유권 확인
      if (data['uid'] != uid) {
        print('[CloudService] ✗ 접근 권한 없음');
        return false;
      }

      final storagePath = data['storagePath'] as String;
      final fileSize = data['fileSize'] as int;

      // 3. Storage에서 파일 삭제
      final ref = _storage.ref().child(storagePath);
      await ref.delete();

      // 4. Firestore 문서 삭제
      await _firestore.collection(_videosCollection).doc(videoId).delete();

      // 5. 사용량 업데이트 (마이너스)
      await _updateStorageUsageIdempotent(
        uid: uid,
        videoId: videoId,
        delta: -fileSize,
        reason: 'delete_completed',
      );

      print('[CloudService] ✓ 삭제 완료: $videoId');
      return true;
    } catch (e) {
      print('[CloudService] ✗ 삭제 실패: $e');
      return false;
    }
  }

  Future<VideoMetadata?> findUserVideoByLocalPath(String localPath) async {
    if (!_ensureNotGuestForCloud('클라우드 메타데이터 조회')) return null;

    final uid = _getCurrentUserId();
    if (uid == null) return null;

    try {
      final byPathSnapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .where('localPath', isEqualTo: localPath)
          .get();

      if (byPathSnapshot.docs.isNotEmpty) {
        for (final doc in byPathSnapshot.docs) {
          final meta = VideoMetadata.fromFirestore(doc);
          if (meta.uploadStatus.toLowerCase() != 'completed') continue;
          return meta;
        }
        return VideoMetadata.fromFirestore(byPathSnapshot.docs.first);
      }

      final localName = p.basename(localPath);
      final byNameSnapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .where('fileName', isEqualTo: localName)
          .get();

      if (byNameSnapshot.docs.isEmpty) return null;

      for (final doc in byNameSnapshot.docs) {
        final meta = VideoMetadata.fromFirestore(doc);
        if (meta.uploadStatus.toLowerCase() != 'completed') continue;
        return meta;
      }

      return VideoMetadata.fromFirestore(byNameSnapshot.docs.first);
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteVideoByLocalPath(String localPath) async {
    final meta = await findUserVideoByLocalPath(localPath);
    if (meta == null) return false;
    return deleteVideo(meta.videoId);
  }

  /// 현재 로그인 사용자의 Cloud 데이터 전체 제거
  ///
  /// 삭제 대상:
  /// - videos 문서 + 연결된 Storage 파일
  /// - vlog_projects 문서
  /// - users/{uid} 문서
  Future<CloudPurgeResult> purgeCurrentUserCloudData() async {
    if (!_ensureNotGuestForCloud('클라우드 데이터 정리')) {
      return const CloudPurgeResult(
        success: false,
        message: '게스트 모드에서는 클라우드 정리가 비활성입니다.',
        failedPhase: 'guest_mode',
      );
    }

    final uid = _getCurrentUserId();
    if (uid == null) {
      return const CloudPurgeResult(
        success: false,
        message: '로그인이 필요합니다.',
        failedPhase: 'auth',
      );
    }

    final inFlight = _purgeInFlightByUid[uid];
    if (inFlight != null) {
      print(
        '[CloudService] purgeCurrentUserCloudData 중복 호출 감지: uid=$uid, 기존 작업 완료 대기',
      );
      return inFlight;
    }

    final future = _performPurgeCurrentUserCloudData(uid);
    _purgeInFlightByUid[uid] = future;

    try {
      return await future;
    } finally {
      if (identical(_purgeInFlightByUid[uid], future)) {
        _purgeInFlightByUid.remove(uid);
      }
    }
  }

  Future<CloudPurgeResult> _performPurgeCurrentUserCloudData(String uid) async {
    var deletedVideoDocs = 0;
    var deletedStorageFiles = 0;
    var skippedStorageDeletes = 0;
    var failedStorageDeletes = 0;
    var deletedProjectDocs = 0;
    final deletedVideoIds = <String>{};

    try {
      // 1) videos + storagePath 삭제
      final videoSnapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .get();

      for (final doc in videoSnapshot.docs) {
        final data = doc.data();
        final storagePath = (data['storagePath'] as String?)?.trim();
        final uploadStatus = (data['uploadStatus'] as String? ?? '')
            .trim()
            .toLowerCase();
        final hasDownloadUrl =
            ((data['downloadUrl'] as String?)?.trim().isNotEmpty ?? false);
        final shouldAttemptStorageDelete =
            uploadStatus == 'completed' || hasDownloadUrl;

        if (storagePath != null &&
            storagePath.isNotEmpty &&
            shouldAttemptStorageDelete) {
          try {
            await _storage.ref().child(storagePath).delete();
            deletedStorageFiles++;
          } on FirebaseException catch (e) {
            if (_isStorageObjectNotFound(e)) {
              skippedStorageDeletes++;
              print(
                '[CloudService] Storage 파일 미존재로 삭제 스킵: '
                'uid=$uid videoId=${doc.id} path=$storagePath code=${e.code} message=${e.message}',
              );
            } else {
              failedStorageDeletes++;
              print(
                '[CloudService] Storage 삭제 실패(비차단, 계속 진행): '
                'uid=$uid videoId=${doc.id} path=$storagePath code=${e.code} message=${e.message}',
              );
            }
          } catch (e) {
            failedStorageDeletes++;
            print(
              '[CloudService] Storage 삭제 실패(비차단, 계속 진행): '
              'uid=$uid videoId=${doc.id} path=$storagePath error=$e',
            );
          }
        } else if (storagePath != null && storagePath.isNotEmpty) {
          skippedStorageDeletes++;
          print(
            '[CloudService] 업로드 미완료 메타데이터로 Storage 삭제 스킵: '
            'uid=$uid videoId=${doc.id} status=${uploadStatus.isEmpty ? 'unknown' : uploadStatus} path=$storagePath',
          );
        }

        await doc.reference.delete();
        deletedVideoDocs++;
        deletedVideoIds.add(doc.id);
      }

      // 2) vlog_projects 삭제
      final projectSnapshot = await _firestore
          .collection(_vlogProjectsCollection)
          .where('uid', isEqualTo: uid)
          .get();

      for (final doc in projectSnapshot.docs) {
        await doc.reference.delete();
        deletedProjectDocs++;
      }

      // 3) users/{uid} 삭제
      await _firestore.collection(_usersCollection).doc(uid).delete();

      // 4) 로컬 동기화 큐/메모리 정리
      await _ensureQueueStoreLoaded();
      if (deletedVideoIds.isNotEmpty) {
        _syncJobs.removeWhere(
          (j) =>
              j.entityType == SyncJobEntityType.clip &&
              deletedVideoIds.contains(j.entityId),
        );
        await _syncQueueStore.saveJobs(_syncJobs);
      }
      _uploadQueue.removeWhere((task) => task.uid == uid);

      return CloudPurgeResult(
        success: true,
        message:
            'Cloud 데이터가 삭제되었습니다. '
            '(videos: $deletedVideoDocs, storageDeleted: $deletedStorageFiles, '
            'storageSkipped: $skippedStorageDeletes, storageFailedNonBlocking: $failedStorageDeletes, '
            'projects: $deletedProjectDocs)',
        deletedVideoDocs: deletedVideoDocs,
        deletedStorageFiles: deletedStorageFiles,
        deletedProjectDocs: deletedProjectDocs,
      );
    } catch (e) {
      return CloudPurgeResult(
        success: false,
        message: 'Cloud 데이터 삭제 실패: $e',
        failedPhase: 'firestore',
        deletedVideoDocs: deletedVideoDocs,
        deletedStorageFiles: deletedStorageFiles,
        deletedProjectDocs: deletedProjectDocs,
      );
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🧾 Vlog 프로젝트 메타데이터 관리
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<ProjectCloudMetadata?> upsertVlogProjectMetadata(
    VlogProject project,
  ) async {
    if (!_ensureNotGuestForCloud('프로젝트 메타데이터 업서트')) return null;

    final uid = _getCurrentUserId();
    if (uid == null) return null;

    try {
      final projectDocId =
          (project.cloudProjectId != null && project.cloudProjectId!.isNotEmpty)
          ? project.cloudProjectId!
          : _firestore.collection(_vlogProjectsCollection).doc().id;

      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][upsert][start] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'projectDocId=$projectDocId localProjectId=${project.id} '
        'clipCount=${project.clips.length} deleted=false',
      );

      await _firestore
          .collection(_vlogProjectsCollection)
          .doc(projectDocId)
          .set({
            'uid': uid,
            'localProjectId': project.id,
            'title': project.title,
            'clipPaths': project.clips.map((c) => c.path).toList(),
            'clipCount': project.clips.length,
            'folderName': project.folderName,
            'lockState': project.lockState,
            'clientCreatedAt': Timestamp.fromDate(project.createdAt),
            'clientUpdatedAt': Timestamp.fromDate(project.updatedAt),
            'lastSyncedAt': FieldValue.serverTimestamp(),
            'deleted': false,
          }, SetOptions(merge: true));

      print(
        '[CloudService][Diag][vlogMeta][upsert][ok] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'projectDocId=$projectDocId localProjectId=${project.id}',
      );

      return ProjectCloudMetadata(
        projectId: projectDocId,
        localProjectId: project.id,
        uid: uid,
        lastSyncedAt: DateTime.now(),
      );
    } on FirebaseException catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][upsert][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'projectDocId=${project.cloudProjectId ?? '(new)'} localProjectId=${project.id} '
        'code=${e.code} message=${e.message}',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 업서트 실패: $e');
      return null;
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][upsert][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'projectDocId=${project.cloudProjectId ?? '(new)'} localProjectId=${project.id} '
        'code=non_firebase_exception error=$e',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 업서트 실패: $e');
      return null;
    }
  }

  Future<Map<String, ProjectCloudMetadata>>
  getUserVlogProjectMetadataMap() async {
    if (!_ensureNotGuestForCloud('프로젝트 메타데이터 조회'))
      return <String, ProjectCloudMetadata>{};

    final uid = _getCurrentUserId();
    if (uid == null) return <String, ProjectCloudMetadata>{};

    try {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][get][start] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'filters=uid==$uid,deleted==false',
      );

      final snapshot = await _firestore
          .collection(_vlogProjectsCollection)
          .where('uid', isEqualTo: uid)
          .where('deleted', isEqualTo: false)
          .get();

      print(
        '[CloudService][Diag][vlogMeta][get][ok] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'docs=${snapshot.docs.length}',
      );

      final map = <String, ProjectCloudMetadata>{};
      for (final doc in snapshot.docs) {
        final meta = ProjectCloudMetadata.fromFirestore(doc);
        if (meta.localProjectId.isEmpty) continue;
        map[meta.localProjectId] = meta;
      }
      return map;
    } on FirebaseException catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][get][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'code=${e.code} message=${e.message}',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 조회 실패: $e');
      return <String, ProjectCloudMetadata>{};
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][get][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'code=non_firebase_exception error=$e',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 조회 실패: $e');
      return <String, ProjectCloudMetadata>{};
    }
  }

  Future<bool> deleteVlogProjectMetadata({
    required String localProjectId,
    String? cloudProjectId,
  }) async {
    if (!_ensureNotGuestForCloud('프로젝트 메타데이터 삭제')) return false;

    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][delete][start] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'cloudProjectId=${cloudProjectId ?? ''} localProjectId=$localProjectId',
      );

      if (cloudProjectId != null && cloudProjectId.isNotEmpty) {
        await _firestore
            .collection(_vlogProjectsCollection)
            .doc(cloudProjectId)
            .delete();
        print(
          '[CloudService][Diag][vlogMeta][delete][ok] '
          'collection=$_vlogProjectsCollection '
          'authUid=$authUid targetUid=$uid '
          'cloudProjectId=$cloudProjectId localProjectId=$localProjectId '
          'mode=direct_doc_delete',
        );
        return true;
      }

      final snapshot = await _firestore
          .collection(_vlogProjectsCollection)
          .where('uid', isEqualTo: uid)
          .where('localProjectId', isEqualTo: localProjectId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }

      print(
        '[CloudService][Diag][vlogMeta][delete][ok] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'cloudProjectId=(lookup) localProjectId=$localProjectId '
        'deletedDocs=${snapshot.docs.length}',
      );
      return true;
    } on FirebaseException catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][delete][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'cloudProjectId=${cloudProjectId ?? ''} localProjectId=$localProjectId '
        'code=${e.code} message=${e.message}',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 삭제 실패: $e');
      return false;
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][delete][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=$authUid targetUid=$uid '
        'cloudProjectId=${cloudProjectId ?? ''} localProjectId=$localProjectId '
        'code=non_firebase_exception error=$e',
      );
      print('[CloudService] ✗ vlog 프로젝트 메타데이터 삭제 실패: $e');
      return false;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📊 사용량 조회
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 현재 저장 용량 사용량 조회 (GB)
  Future<double> getStorageUsageGB() async {
    if (!_ensureNotGuestForCloud('클라우드 용량 조회')) return 0.0;

    final uid = _getCurrentUserId();
    if (uid == null) return 0.0;

    final usage = await _getCurrentStorageUsage(uid);
    return usage / (1024 * 1024 * 1024);
  }

  /// 저장 용량 제한 조회 (GB)
  double getStorageLimitGB() {
    final limit = switch (_userStatusManager.currentTier) {
      UserTier.premium => _premiumStorageLimit,
      UserTier.standard => _standardStorageLimit,
      UserTier.free => 0,
    };
    return limit / (1024 * 1024 * 1024);
  }

  /// 사용률 조회 (0.0 ~ 1.0)
  Future<double> getStorageUsageRatio() async {
    final usage = await getStorageUsageGB();
    final limit = getStorageLimitGB();
    if (limit <= 0) return 0.0;
    return usage / limit;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🔔 용량 알림 (Premium 전환 유도)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 용량 사용률 체크 및 알림
  ///
  /// 90% 이상 도달 시 Premium 전환 알림 트리거
  Future<void> checkUsageAndAlert(VideoManager _) async {
    if (!_ensureNotGuestForCloud('클라우드 용량 알림')) return;

    try {
      final notificationsEnabled = await NotificationSettingsService.instance
          .isNotificationsEnabled();
      if (!notificationsEnabled) {
        print('[CloudService] 알림 off 상태로 용량 알림 발송을 스킵합니다.');
        return;
      }

      final storageAlertEnabled = await NotificationSettingsService.instance
          .isCategoryEnabled(NotificationCategory.storageAlert);
      if (!storageAlertEnabled) {
        print('[CloudService] storage_alert 카테고리 off 상태로 용량 알림을 스킵합니다.');
        return;
      }

      final uid = _getCurrentUserId();
      if (uid == null) return;

      final limitBytes = switch (_userStatusManager.currentTier) {
        UserTier.premium => _premiumStorageLimit,
        UserTier.standard => _standardStorageLimit,
        UserTier.free => 0,
      };
      if (limitBytes <= 0) {
        print('[CloudService] Free 등급은 Cloud 미지원으로 용량 알림을 스킵합니다.');
        return;
      }

      final usedBytes = await _getCurrentStorageUsage(uid);
      final ratio = usedBytes / limitBytes;

      if (ratio >= 0.9) {
        // 90% 도달 시 알림 트리거
        print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('[CloudService] ⚠️ 용량 90% 도달!');
        print(
          '[CloudService]   - 현재 사용량: ${(ratio * 100).toStringAsFixed(1)}%',
        );
        print('[CloudService]   - 사용량: ${usedBytes / (1024 * 1024 * 1024)} GB');
        print('[CloudService]   - 제한: ${limitBytes / (1024 * 1024 * 1024)} GB');
        print('[CloudService] 📢 Premium 전환 알림 발송 준비');
        print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // TODO: FCM 푸시 알림 전송
        // await _sendHighUsageNotification();

        // TODO: 인앱 다이얼로그 표시
        // - "클라우드 저장 공간이 거의 찼습니다!"
        // - "Premium으로 업그레이드하여 200GB를 확보하세요"
        // - [업그레이드] 버튼 → PaywallScreen
      }
    } catch (e) {
      print('[CloudService] ✗ 용량 체크 실패: $e');
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 📦 데이터 모델
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// 업로드 작업
class UploadTask {
  final File videoFile;
  final String videoId;
  final String storagePath;
  final int fileSize;
  final String uid;
  final String? localPath;
  final String? projectId;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? availableAt;

  UploadTask({
    required this.videoFile,
    required this.videoId,
    required this.storagePath,
    required this.fileSize,
    required this.uid,
    this.localPath,
    this.projectId,
    required this.createdAt,
    this.attemptCount = 0,
    this.availableAt,
  });

  UploadTask copyWith({int? attemptCount, DateTime? availableAt}) {
    return UploadTask(
      videoFile: videoFile,
      videoId: videoId,
      storagePath: storagePath,
      fileSize: fileSize,
      uid: uid,
      localPath: localPath,
      projectId: projectId,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      availableAt: availableAt ?? this.availableAt,
    );
  }
}

class SyncErrorDetail {
  final String code;
  final bool retryable;
  final String copy;

  const SyncErrorDetail({
    required this.code,
    required this.retryable,
    required this.copy,
  });
}

class CloudPurgeResult {
  final bool success;
  final String message;
  final String? failedPhase;
  final int deletedVideoDocs;
  final int deletedStorageFiles;
  final int deletedProjectDocs;

  const CloudPurgeResult({
    required this.success,
    required this.message,
    this.failedPhase,
    this.deletedVideoDocs = 0,
    this.deletedStorageFiles = 0,
    this.deletedProjectDocs = 0,
  });
}

class SyncStatusSummary {
  final int queuedCount;
  final int uploadingCount;
  final int failedCount;
  final int completedCount;

  const SyncStatusSummary({
    this.queuedCount = 0,
    this.uploadingCount = 0,
    this.failedCount = 0,
    this.completedCount = 0,
  });

  bool get isAllCompleted =>
      queuedCount == 0 && uploadingCount == 0 && failedCount == 0;
}

/// 업로드 진행률
class UploadProgress {
  final String videoId;
  final double progress;
  final int bytesTransferred;
  final int totalBytes;

  UploadProgress({
    required this.videoId,
    required this.progress,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  int get progressPercent => (progress * 100).toInt();

  String get progressText =>
      '${(bytesTransferred / (1024 * 1024)).toStringAsFixed(1)}MB / '
      '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

/// 영상 메타데이터
class VideoMetadata {
  final String videoId;
  final String uid;
  final String fileName;
  final String storagePath;
  final String albumName;
  final bool isFavorite;
  final int fileSize;
  final String uploadStatus;
  final int uploadProgress;
  final String? downloadUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? errorCopy;

  VideoMetadata({
    required this.videoId,
    required this.uid,
    required this.fileName,
    required this.storagePath,
    required this.albumName,
    required this.isFavorite,
    required this.fileSize,
    required this.uploadStatus,
    required this.uploadProgress,
    this.downloadUrl,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.errorCopy,
  });

  factory VideoMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return VideoMetadata(
      videoId: doc.id,
      uid: data['uid'] ?? '',
      fileName: data['fileName'] ?? '',
      storagePath: data['storagePath'] ?? '',
      albumName: data['albumName'] ?? '',
      isFavorite: data['isFavorite'] ?? false,
      fileSize: data['fileSize'] ?? 0,
      uploadStatus: data['uploadStatus'] ?? 'unknown',
      uploadProgress: data['uploadProgress'] ?? 0,
      downloadUrl: data['downloadUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      errorCopy: data['errorCopy'] as String?,
    );
  }

  String get fileSizeText =>
      (fileSize / (1024 * 1024)).toStringAsFixed(2) + 'MB';
}

class ProjectCloudMetadata {
  final String projectId;
  final String localProjectId;
  final String uid;
  final DateTime? lastSyncedAt;

  const ProjectCloudMetadata({
    required this.projectId,
    required this.localProjectId,
    required this.uid,
    this.lastSyncedAt,
  });

  factory ProjectCloudMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProjectCloudMetadata(
      projectId: doc.id,
      localProjectId: data['localProjectId'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      lastSyncedAt: (data['lastSyncedAt'] as Timestamp?)?.toDate(),
    );
  }
}
