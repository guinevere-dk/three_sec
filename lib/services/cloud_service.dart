import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thum;
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
  static const String _errorSubscriptionExpired = 'subscription_expired';
  static const String _errorPermissionDenied = 'permission_denied';
  static const String _errorNetwork = 'network_unavailable';
  static const String _errorQuota = 'quota_exceeded';
  static const String _errorUploadFailed = 'upload_failed';
  static const String _errorThumbnailGeneration = 'thumbnail_generation_failed';
  static const String _errorThumbnailUpload = 'thumbnail_upload_failed';
  static const String _errorThumbnailMetadata = 'thumbnail_metadata_failed';
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
  final StreamController<CloudStatsSnapshot> _cloudStatsController =
      StreamController<CloudStatsSnapshot>.broadcast();

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
  Stream<CloudStatsSnapshot> get cloudStatsStream =>
      _cloudStatsController.stream;
  String? get lastImmediateUploadErrorCode => _lastImmediateUploadErrorCode;
  String? get lastImmediateUploadErrorCopy => _lastImmediateUploadErrorCopy;

  void clearLastImmediateUploadError() {
    _lastImmediateUploadErrorCode = null;
    _lastImmediateUploadErrorCopy = null;
  }

  static String _maskUid(String? value) {
    final uid = value?.trim();
    if (uid == null || uid.isEmpty) return '<uid-unavailable>';
    if (uid.length <= 8) return '<masked-uid>';
    return '${uid.substring(0, 4)}...${uid.substring(uid.length - 4)}';
  }

  static String _redactErrorForMetadata(String rawError) {
    final trimmed = rawError.trim();
    if (trimmed.isEmpty) return '<redacted-error>';
    return trimmed
        .replaceAll(
          RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'),
          '<redacted-email>',
        )
        .replaceAll(RegExp(r'[A-Za-z]:[\\/][^\s)]+'), '<redacted-path>')
        .replaceAll(RegExp(r'/(?:[^\s)]+/)*[^\s)]+\.mp4'), '<redacted-path>')
        .replaceAll(RegExp(r'\b[\w.-]+\.mp4\b'), '<redacted-file>');
  }

  static String _maskId(String? value, {String label = 'id'}) {
    final id = value?.trim();
    if (id == null || id.isEmpty) return '<$label-unavailable>';
    if (id.length <= 8) return '<masked-$label>';
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  static String _redactedPathCountLabel(String? value) {
    final hasValue = value != null && value.trim().isNotEmpty;
    return hasValue ? '<redacted-path>' : '<path-unavailable>';
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
            '(videoId=${_maskId(job.entityId, label: 'video-id')}, '
            'localPath=${_redactedPathCountLabel(job.localPath)}, '
            'storagePath=${_redactedPathCountLabel(job.storagePath)})',
          );
          skipped += 1;
          continue;
        }

        final file = File(job.localPath!);
        if (!await file.exists()) {
          print(
            '[CloudService] ⚠️ 복구 스킵: 로컬 파일 미존재 '
            '(videoId=${_maskId(job.entityId, label: 'video-id')}, '
            'localPath=${_redactedPathCountLabel(job.localPath)})',
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
            '(videoId=${_maskId(job.entityId, label: 'video-id')}, '
            'dedupe=<redacted-dedupe-key>)',
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
            albumName: p.basename(p.dirname(job.localPath!)),
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
    if (job.entityType != SyncJobEntityType.clip ||
        job.action != SyncJobAction.upload) {
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
          (localPath != null &&
              task.localPath != null &&
              task.localPath == localPath),
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
  // ignore: unused_element
  bool _checkStandardOrAbove() {
    if (!_userStatusManager.isStandardOrAbove()) {
      print(
        '[CloudService] ✗ Standard 등급 이상 필요 (현재: ${_userStatusManager.currentTier})',
      );
      return false;
    }
    return true;
  }

  bool _canStartNewCloudWrite(String operation) {
    if (_userStatusManager.canStartNewCloudWrite()) return true;

    final reason = _cloudWriteBlockedReasonCode();
    print(
      '[CloudService] ✗ 신규 Cloud 작업 차단: '
      '$operation (reason=$reason, tier=${_userStatusManager.currentTier}, expiry=${_userStatusManager.lastKnownPaidExpiryAt}, graceEnds=${_userStatusManager.cloudReadGraceEndsAt})',
    );
    unawaited(
      _reviewFallbackMetrics.recordCloudAccessBlocked(
        operation: operation,
        reason: reason,
      ),
    );
    return false;
  }

  String _cloudWriteBlockedReasonCode() {
    if (_userStatusManager.isStandardOrAbove()) {
      return _errorSubscriptionExpired;
    }
    if (_userStatusManager.canReadExistingCloudClips()) {
      return _errorSubscriptionExpired;
    }
    return _errorTierRequired;
  }

  String _cloudWriteBlockedMessage() {
    final reason = _cloudWriteBlockedReasonCode();
    if (reason == _errorTierRequired) {
      return '클라우드 이동은 Standard 이상에서 사용할 수 있어요. 플랜을 확인해주세요.';
    }
    return subscriptionExpiredCloudWriteMessage();
  }

  bool _canReadExistingCloudClips(String operation) {
    if (_userStatusManager.canReadExistingCloudClips()) return true;

    print(
      '[CloudService] ✗ 구독 만료 grace 종료/권한 없음으로 Cloud read 차단: '
      '$operation (tier=${_userStatusManager.currentTier}, expiry=${_userStatusManager.lastKnownPaidExpiryAt}, graceEnds=${_userStatusManager.cloudReadGraceEndsAt})',
    );
    unawaited(
      _reviewFallbackMetrics.recordCloudAccessBlocked(
        operation: operation,
        reason: 'subscription_expired_or_grace_ended',
      ),
    );
    return false;
  }

  String subscriptionExpiredCloudWriteMessage() =>
      '구독이 만료되어 신규 Cloud 업로드/복사가 중지되었어요. 기존 Cloud 클립은 만료 후 30일 동안 이 기기에 복원할 수 있으며, 구독 복원 또는 재구독 후 Cloud 이용이 다시 가능해요.';

  String subscriptionExpiredCloudReadMessage() =>
      'Cloud 접근 가능 기간이 종료되었어요. 구독 복원 또는 재구독 후 Cloud 보관함과 복원을 다시 이용할 수 있어요.';

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
        '[CloudService] ✗ 사용량 조회 실패: errorType=${e.runtimeType} '
        '(requestedUid=${_maskUid(uid)}, authUid=${_maskUid(authUid)}, '
        'signedIn=${_authService.isSignedIn})',
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
          print('[CloudService] usage 이벤트 중복 스킵: eventId=<redacted-id>');
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
        'event=<redacted-id>, '
        'delta=${delta > 0 ? '+' : ''}${(delta / (1024 * 1024)).toStringAsFixed(2)}MB',
      );
    } catch (e) {
      print(
        '[CloudService] ✗ 사용량 업데이트 실패'
        '(event=<redacted-id>, errorType=${e.runtimeType})',
      );
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
    print('[CloudService]   - 파일: <redacted-file>');
    print('[CloudService]   - 앨범: $albumName');
    print('[CloudService]   - 즐겨찾기: $isFavorite');

    if (!_ensureNotGuestForCloud('클라우드 이동')) {
      return null;
    }

    // 1. 보안 검증
    final uid = _getCurrentUserId();
    if (uid == null) return null;

    if (!_canStartNewCloudWrite('클라우드 이동')) {
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

      print(
        '[CloudService] ✓ 메타데이터 생성: '
        'videoId=${_maskId(videoId, label: 'video-id')}',
      );

      // 5. 업로드 큐에 추가
      await _addToUploadQueue(
        videoFile: videoFile,
        videoId: videoId,
        storagePath: storagePath,
        fileSize: fileSize,
        uid: uid,
        albumName: albumName,
        localPath: localPath,
      );

      return videoId;
    } catch (e) {
      print(
        '[CloudService] ✗ 업로드 준비 실패: '
        'errorType=${e.runtimeType}',
      );
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
    var thumbnailGenerationAttemptCount = 0;
    var thumbnailGenerationSuccessCount = 0;
    var thumbnailGenerationFailureCount = 0;
    var thumbnailUploadAttemptCount = 0;
    var thumbnailUploadSuccessCount = 0;
    var thumbnailUploadFailureCount = 0;
    var thumbnailMetadataCommitSuccessCount = 0;
    var thumbnailMetadataCommitFailureCount = 0;
    var videoUploadSucceeded = false;
    var thumbnailGenerated = false;
    var thumbnailUploaded = false;
    var thumbnailMetadataCommitted = false;
    var localCleanupExecuted = false;

    void logThumbnailDiagnostics(String result) {
      print(
        '[CloudService][ThumbnailUpload] result=$result '
        'thumbnail_generation_attempt_count=$thumbnailGenerationAttemptCount '
        'thumbnail_generation_success=$thumbnailGenerationSuccessCount '
        'thumbnail_generation_failure=$thumbnailGenerationFailureCount '
        'thumbnail_upload_attempt_count=$thumbnailUploadAttemptCount '
        'thumbnail_upload_success=$thumbnailUploadSuccessCount '
        'thumbnail_upload_failure=$thumbnailUploadFailureCount '
        'thumbnail_metadata_commit_success=$thumbnailMetadataCommitSuccessCount '
        'thumbnail_metadata_commit_failure=$thumbnailMetadataCommitFailureCount '
        'local_cleanup_executed=$localCleanupExecuted',
      );
    }

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
    if (!_canStartNewCloudWrite('클라우드 이동')) {
      _lastImmediateUploadErrorCode = _cloudWriteBlockedReasonCode();
      _lastImmediateUploadErrorCopy = _cloudWriteBlockedMessage();
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
    final thumbnailStoragePath =
        'users/$uid/videos/$videoId/thumbnails/poster.jpg';

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
        'thumbnailStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      thumbnailGenerationAttemptCount++;
      final poster = await _generatePosterThumbnail(videoFile);
      if (poster == null) {
        thumbnailGenerationFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailGeneration,
          copy: '썸네일 생성에 실패해 클라우드 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'thumbnail_generation',
        );
      }
      thumbnailGenerated = true;
      thumbnailGenerationSuccessCount++;

      final metadata = _buildVideoMetadata(videoFile.path);
      print(
        '[CloudService][Diag] immediate upload metadata: ${metadata.contentType}',
      );
      final ref = _storage.ref().child(storagePath);
      final task = await ref.putFile(videoFile, metadata);
      final downloadUrl = await task.ref.getDownloadURL();
      videoUploadSucceeded = true;

      try {
        thumbnailUploadAttemptCount++;
        await _storage
            .ref()
            .child(thumbnailStoragePath)
            .putData(poster.bytes, SettableMetadata(contentType: 'image/jpeg'));
        thumbnailUploaded = true;
        thumbnailUploadSuccessCount++;
      } catch (_) {
        thumbnailUploadFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailUpload,
          copy: '썸네일 업로드에 실패해 클라우드 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'thumbnail_upload',
        );
      }

      try {
        await _firestore.collection(_videosCollection).doc(videoId).update({
          'uploadStatus': 'completed',
          'uploadProgress': 100,
          'downloadUrl': downloadUrl,
          'thumbnailStatus': 'completed',
          'thumbnailStoragePath': thumbnailStoragePath,
          'thumbnailWidth': poster.width,
          'thumbnailHeight': poster.height,
          'durationMs': poster.durationMs,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        thumbnailMetadataCommitted = true;
        thumbnailMetadataCommitSuccessCount++;
      } catch (_) {
        thumbnailMetadataCommitFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailMetadata,
          copy: '클라우드 메타데이터 저장에 실패해 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'thumbnail_metadata',
        );
      }

      await _updateStorageUsageIdempotent(
        uid: uid,
        videoId: videoId,
        delta: fileSize,
        reason: 'upload_completed',
      );
      if (localPath != null &&
          shouldRunLocalCleanupAfterUploadMove(
            videoUploadSucceeded: videoUploadSucceeded,
            thumbnailGenerated: thumbnailGenerated,
            thumbnailUploaded: thumbnailUploaded,
            metadataCommitted: thumbnailMetadataCommitted,
          )) {
        try {
          await VideoManager().removeLocalClipAfterCloudMove(
            path: localPath,
            albumName: albumName,
          );
          localCleanupExecuted = true;
          await VideoManager().syncCloudMetadataToLibrary(
            trigger: 'immediate_upload_move_to_cloud',
          );
        } catch (_) {
          // Local cleanup is best-effort after the Cloud upload is committed.
        }
      }
      clearLastImmediateUploadError();
      logThumbnailDiagnostics('success');
      return videoId;
    } catch (e) {
      final detail = e is _CloudThumbnailPipelineException
          ? SyncErrorDetail(code: e.code, retryable: true, copy: e.copy)
          : _classifySyncError(e.toString());
      _lastImmediateUploadErrorCode = detail.code;
      _lastImmediateUploadErrorCopy = detail.copy;

      await _safeUpdateFailureMetadata(
        videoId: videoId,
        detail: detail,
        rawError: e.toString(),
        phase: e is _CloudThumbnailPipelineException
            ? e.phase
            : 'immediate_upload',
      );

      print(
        '[CloudService] ✗ 즉시 업로드 실패 '
        '(code=${detail.code}, retryable=${detail.retryable})',
      );
      logThumbnailDiagnostics('failure');
      return null;
    }
  }

  @visibleForTesting
  static bool shouldRunLocalCleanupAfterUploadMove({
    required bool videoUploadSucceeded,
    required bool thumbnailGenerated,
    required bool thumbnailUploaded,
    required bool metadataCommitted,
  }) {
    return videoUploadSucceeded &&
        thumbnailGenerated &&
        thumbnailUploaded &&
        metadataCommitted;
  }

  @visibleForTesting
  static bool isCompletedCloudMoveMetadata(VideoMetadata metadata) {
    return metadata.uploadStatus.toLowerCase() == 'completed' &&
        metadata.hasCompletedThumbnail;
  }

  Future<_GeneratedPosterThumbnail?> _generatePosterThumbnail(
    File videoFile,
  ) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      final durationMs = controller.value.duration.inMilliseconds;
      if (durationMs <= 0) {
        return null;
      }

      final bytes = await thum.VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: thum.ImageFormat.JPEG,
        maxWidth: 720,
        quality: 82,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      final size = await _decodeImageSize(bytes);
      if (size == null || size.width <= 0 || size.height <= 0) {
        return null;
      }

      return _GeneratedPosterThumbnail(
        bytes: bytes,
        width: size.width,
        height: size.height,
        durationMs: durationMs,
      );
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  Future<_ImageSize?> _decodeImageSize(Uint8List bytes) async {
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
      final image = frame.image;
      final size = _ImageSize(width: image.width, height: image.height);
      image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeUpdateThumbnailFailureMetadata(String videoId) async {
    try {
      await _firestore.collection(_videosCollection).doc(videoId).set({
        'thumbnailStatus': 'failed',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort only; local source remains active when this fails.
    }
  }

  /// 업로드 큐에 작업 추가
  Future<void> _addToUploadQueue({
    required File videoFile,
    required String videoId,
    required String storagePath,
    required int fileSize,
    required String uid,
    required String albumName,
    String? localPath,
  }) async {
    await _ensureQueueStoreLoaded();

    final now = DateTime.now();
    final projectId = localPath != null
        ? p.dirname(localPath).split('/').last
        : null;
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
        '(videoId=${_maskId(videoId, label: 'video-id')}, '
        'dedupe=<redacted-dedupe-key>)',
      );
      return;
    }

    if (hasActiveSyncDuplicate && !existing) {
      print(
        '[CloudService] ⚠️ 동기화 작업 중복 삽입 스킵: '
        '(videoId=${_maskId(videoId, label: 'video-id')}, '
        'storagePath=${_redactedPathCountLabel(storagePath)}, '
        'localPath=${_redactedPathCountLabel(localPath)})',
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
      albumName: albumName,
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

    if (!_canStartNewCloudWrite('백그라운드 업로드')) {
      final blocked = List<UploadTask>.from(_uploadQueue);
      _uploadQueue.clear();
      for (final task in blocked) {
        await _setSyncJobStateForVideo(
          videoId: task.videoId,
          status: SyncJobStatus.failed,
          attemptCount: task.attemptCount,
          errorCode: _errorSubscriptionExpired,
          errorMessage: subscriptionExpiredCloudWriteMessage(),
        );
        await _safeUpdateFailureMetadata(
          videoId: task.videoId,
          detail: SyncErrorDetail(
            code: _errorSubscriptionExpired,
            retryable: false,
            copy: subscriptionExpiredCloudWriteMessage(),
          ),
          rawError: 'subscription expired before queue upload',
          phase: 'queue_upload_subscription_guard',
        );
      }
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
    print(
      '[CloudService] ⚡ 업로드 시작: '
      'videoId=${_maskId(task.videoId, label: 'video-id')}',
    );
    final authUidAtStart = _authService.currentUser?.uid;
    print(
      '[CloudService][Diag] upload context '
      'taskUid=${_maskUid(task.uid)}, authUid=${_maskUid(authUidAtStart)}, '
      'signedIn=${_authService.isSignedIn}, path=<redacted-path>',
    );

    var thumbnailGenerationAttemptCount = 0;
    var thumbnailGenerationSuccessCount = 0;
    var thumbnailGenerationFailureCount = 0;
    var thumbnailUploadAttemptCount = 0;
    var thumbnailUploadSuccessCount = 0;
    var thumbnailUploadFailureCount = 0;
    var thumbnailMetadataCommitSuccessCount = 0;
    var thumbnailMetadataCommitFailureCount = 0;
    var videoUploadSucceeded = false;
    var thumbnailGenerated = false;
    var thumbnailUploaded = false;
    var thumbnailMetadataCommitted = false;
    var localCleanupExecuted = false;

    void logQueueThumbnailDiagnostics(String result) {
      print(
        '[CloudService][ThumbnailUpload][Queue] result=$result '
        'thumbnail_generation_attempt_count=$thumbnailGenerationAttemptCount '
        'thumbnail_generation_success=$thumbnailGenerationSuccessCount '
        'thumbnail_generation_failure=$thumbnailGenerationFailureCount '
        'thumbnail_upload_attempt_count=$thumbnailUploadAttemptCount '
        'thumbnail_upload_success=$thumbnailUploadSuccessCount '
        'thumbnail_upload_failure=$thumbnailUploadFailureCount '
        'thumbnail_metadata_commit_success=$thumbnailMetadataCommitSuccessCount '
        'thumbnail_metadata_commit_failure=$thumbnailMetadataCommitFailureCount '
        'local_cleanup_executed=$localCleanupExecuted',
      );
    }

    try {
      if (!_canStartNewCloudWrite('백그라운드 업로드')) {
        final detail = SyncErrorDetail(
          code: _errorSubscriptionExpired,
          retryable: false,
          copy: subscriptionExpiredCloudWriteMessage(),
        );
        await _safeUpdateFailureMetadata(
          videoId: task.videoId,
          detail: detail,
          rawError: 'subscription expired before upload execution',
          phase: 'queue_upload_subscription_guard',
        );
        await _setSyncJobStateForVideo(
          videoId: task.videoId,
          status: SyncJobStatus.failed,
          attemptCount: task.attemptCount,
          errorCode: detail.code,
          errorMessage: detail.copy,
        );
        return;
      }

      final thumbnailStoragePath =
          'users/${task.uid}/videos/${task.videoId}/thumbnails/poster.jpg';
      await _firestore.collection(_videosCollection).doc(task.videoId).set({
        'uploadStatus': 'uploading',
        'uploadProgress': 0,
        'thumbnailStatus': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      thumbnailGenerationAttemptCount++;
      final poster = await _generatePosterThumbnail(task.videoFile);
      if (poster == null) {
        thumbnailGenerationFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(task.videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailGeneration,
          copy: '썸네일 생성에 실패해 클라우드 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'queue_thumbnail_generation',
        );
      }
      thumbnailGenerated = true;
      thumbnailGenerationSuccessCount++;

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
      videoUploadSucceeded = true;

      try {
        thumbnailUploadAttemptCount++;
        await _storage
            .ref()
            .child(thumbnailStoragePath)
            .putData(poster.bytes, SettableMetadata(contentType: 'image/jpeg'));
        thumbnailUploaded = true;
        thumbnailUploadSuccessCount++;
      } catch (_) {
        thumbnailUploadFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(task.videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailUpload,
          copy: '썸네일 업로드에 실패해 클라우드 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'queue_thumbnail_upload',
        );
      }

      try {
        // Firestore 업데이트 (완료)
        await _firestore
            .collection(_videosCollection)
            .doc(task.videoId)
            .update({
              'uploadStatus': 'completed',
              'uploadProgress': 100,
              'downloadUrl': downloadUrl,
              'thumbnailStatus': 'completed',
              'thumbnailStoragePath': thumbnailStoragePath,
              'thumbnailWidth': poster.width,
              'thumbnailHeight': poster.height,
              'durationMs': poster.durationMs,
              'completedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
        thumbnailMetadataCommitted = true;
        thumbnailMetadataCommitSuccessCount++;
      } catch (_) {
        thumbnailMetadataCommitFailureCount++;
        await _safeUpdateThumbnailFailureMetadata(task.videoId);
        throw const _CloudThumbnailPipelineException(
          code: _errorThumbnailMetadata,
          copy: '클라우드 메타데이터 저장에 실패해 이동을 완료하지 못했어요. 다시 시도해주세요.',
          phase: 'queue_thumbnail_metadata',
        );
      }

      // 사용량 업데이트
      await _updateStorageUsageIdempotent(
        uid: task.uid,
        videoId: task.videoId,
        delta: task.fileSize,
        reason: 'upload_completed',
      );

      if (task.localPath != null &&
          shouldRunLocalCleanupAfterUploadMove(
            videoUploadSucceeded: videoUploadSucceeded,
            thumbnailGenerated: thumbnailGenerated,
            thumbnailUploaded: thumbnailUploaded,
            metadataCommitted: thumbnailMetadataCommitted,
          )) {
        try {
          await VideoManager().removeLocalClipAfterCloudMove(
            path: task.localPath!,
            albumName: task.albumName,
          );
          localCleanupExecuted = true;
          await VideoManager().syncCloudMetadataToLibrary(
            trigger: 'queued_upload_move_to_cloud',
          );
        } catch (_) {
          // Local cleanup is best-effort after the Cloud upload is committed.
        }
      }

      await _setSyncJobStateForVideo(
        videoId: task.videoId,
        status: SyncJobStatus.completed,
        attemptCount: task.attemptCount,
      );
      await _removeSyncJobForVideo(task.videoId);

      print(
        '[CloudService] ✓ 업로드 완료: '
        'videoId=${_maskId(task.videoId, label: 'video-id')}',
      );
      print('[CloudService]   - URL: <redacted-url>');
      logQueueThumbnailDiagnostics('success');
    } catch (e) {
      final authUidOnError = _authService.currentUser?.uid;
      final detail = e is _CloudThumbnailPipelineException
          ? SyncErrorDetail(code: e.code, retryable: true, copy: e.copy)
          : _classifySyncError(e.toString());
      print(
        '[CloudService] ✗ 업로드 실패 '
        '(code=${detail.code}, retryable=${detail.retryable}, attempt=${task.attemptCount + 1}, '
        'errorType=${e.runtimeType}) '
        '[diag taskUid=${_maskUid(task.uid)}, '
        'authUid=${_maskUid(authUidOnError)}, signedIn=${_authService.isSignedIn}]',
      );

      await _safeUpdateFailureMetadata(
        videoId: task.videoId,
        detail: detail,
        rawError: e.toString(),
        phase: e is _CloudThumbnailPipelineException ? e.phase : 'queue_upload',
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
          errorMessage: _redactErrorForMetadata(e.toString()),
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
          errorMessage: _redactErrorForMetadata(e.toString()),
        );
      } else if (!detail.retryable) {
        print('[CloudService] ⛔ 비재시도 오류로 큐 재시도 중단: ${detail.code}');
      }
      logQueueThumbnailDiagnostics('failure');
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
    final isTerminalFailure =
        _isNonRetryableErrorCode(errorCode) ||
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
    final redactedError = _redactErrorForMetadata(rawError);

    if (normalized.contains('object-not-found') ||
        normalized.contains('storage/object-not-found') ||
        normalized.contains('object does not exist at location')) {
      return SyncErrorDetail(
        code: _errorNotFound,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    if (normalized.contains('permission_denied') ||
        normalized.contains('permission denied') ||
        normalized.contains('unauthorized') ||
        normalized.contains('forbidden')) {
      return SyncErrorDetail(
        code: _errorPermissionDenied,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    if (normalized.contains('not authenticated') ||
        normalized.contains('auth/currentuser is null') ||
        normalized.contains('auth required') ||
        normalized.contains('sign in')) {
      return SyncErrorDetail(
        code: _errorAuthRequired,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    if (normalized.contains('cloud firestore api has not been used') ||
        normalized.contains('firestore.googleapis.com') ||
        normalized.contains('api is disabled')) {
      return SyncErrorDetail(
        code: _errorCloudApiDisabled,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('unavailable') ||
        normalized.contains('deadline-exceeded')) {
      return SyncErrorDetail(
        code: _errorNetwork,
        retryable: true,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
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
          copy: ErrorCopy.syncFailureWithAction(redactedError),
        );
      }

      if (normalized.contains('not found') ||
          normalized.contains('object-not-found') ||
          normalized.contains('does not exist')) {
        return SyncErrorDetail(
          code: _errorNotFound,
          retryable: false,
          copy: ErrorCopy.syncFailureWithAction(redactedError),
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
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    if (normalized.contains('firestore') ||
        normalized.contains('documentreference') ||
        normalized.contains('firestoreexception')) {
      return SyncErrorDetail(
        code: _errorUploadFailed,
        retryable: false,
        copy: ErrorCopy.syncFailureWithAction(redactedError),
      );
    }

    return SyncErrorDetail(
      code: _errorUploadFailed,
      retryable: true,
      copy: ErrorCopy.syncFailureWithAction(redactedError),
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
        'videoId=<redacted-video-id>, phase=$phase, authUid=${_maskUid(authUid)}, '
        'signedIn=${_authService.isSignedIn}, code=${detail.code}',
      );
      await _firestore.collection(_videosCollection).doc(videoId).update({
        'uploadStatus': 'failed',
        'errorCode': detail.code,
        'errorMessage': _redactErrorForMetadata(rawError),
        'errorCopy': detail.copy,
        'errorPhase': phase,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (metaErr) {
      print(
        '[CloudService] ✗ 실패 메타데이터 기록 실패'
        '(videoId=<redacted-video-id>, errorType=${metaErr.runtimeType})',
      );
    }
  }

  Future<SyncStatusSummary> getSyncStatusSummary({bool emit = true}) async {
    final uid = _getCurrentUserId();
    if (uid == null) {
      return const SyncStatusSummary();
    }

    try {
      await _ensureQueueStoreLoaded();
      var queued = 0;
      var uploading = 0;
      var failed = 0;

      for (final job in _syncJobs) {
        if (job.ownerUid != null && job.ownerUid != uid) {
          continue;
        }
        if (job.entityType != SyncJobEntityType.clip ||
            job.action != SyncJobAction.upload) {
          continue;
        }
        if (job.localPath != null &&
            job.localPath!.trim().isNotEmpty &&
            !File(job.localPath!).existsSync()) {
          continue;
        }

        switch (job.status) {
          case SyncJobStatus.queued:
            queued++;
            break;
          case SyncJobStatus.inProgress:
            uploading++;
            break;
          case SyncJobStatus.failed:
            failed++;
            break;
          case SyncJobStatus.completed:
          case SyncJobStatus.skipped:
          case SyncJobStatus.canceled:
            break;
        }
      }

      final snapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .get();

      var completed = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (_isDeleted(data) || _isTrashOrTombstone(data)) {
          continue;
        }
        final status = (data['uploadStatus'] as String? ?? 'unknown')
            .toLowerCase();
        switch (status) {
          case 'queued':
          case 'uploading':
          case 'failed':
            // Firestore failure metadata is historical evidence. Profile only
            // shows actionable local sync queue failures.
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
      if (emit) {
        _syncSummaryController.add(summary);
      }
      return summary;
    } catch (_) {
      return const SyncStatusSummary();
    }
  }

  Future<int> getCompletedVideoCount() async {
    final uid = _getCurrentUserId();
    if (uid == null) return 0;

    try {
      final snapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .where('uploadStatus', isEqualTo: 'completed')
          .get();
      return snapshot.docs
          .where((doc) => !_isDeleted(doc.data()))
          .where((doc) => !_isTombstone(doc.data()))
          .where(
            (doc) =>
                _readString(doc.data()['storagePath']).trim().isNotEmpty ||
                _readString(doc.data()['downloadUrl']).trim().isNotEmpty,
          )
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<CloudStatsSnapshot> refreshCloudStatsSnapshot({
    String trigger = 'manual',
  }) async {
    final uid = _getCurrentUserId();
    if (uid == null || !_userStatusManager.canReadExistingCloudClips()) {
      final snapshot = CloudStatsSnapshot(
        cloudClipCount: 0,
        storageUsageGB: 0,
        storageLimitGB: getStorageLimitGB(),
        syncSummary: const SyncStatusSummary(),
        refreshedAt: DateTime.now(),
        trigger: trigger,
      );
      _cloudStatsController.add(snapshot);
      return snapshot;
    }

    final count = await getCompletedVideoCount();
    final usage = await getStorageUsageGB();
    final summary = await getSyncStatusSummary(emit: false);
    final snapshot = CloudStatsSnapshot(
      cloudClipCount: count,
      storageUsageGB: usage,
      storageLimitGB: getStorageLimitGB(),
      syncSummary: summary,
      refreshedAt: DateTime.now(),
      trigger: trigger,
    );
    _cloudStatsController.add(snapshot);
    return snapshot;
  }

  bool _isTrashOrTombstone(Map<String, dynamic> data) {
    final lifecycle = (data['lifecycleState'] as String? ?? '').toLowerCase();
    final cloudState = (data['cloudState'] as String? ?? '').toLowerCase();
    final trashed = data['trashed'] == true;
    return trashed ||
        lifecycle == 'trash' ||
        lifecycle == 'tombstone' ||
        cloudState == 'trash' ||
        cloudState == 'tombstone';
  }

  bool _isDeleted(Map<String, dynamic> data) {
    final lifecycle = (data['lifecycleState'] as String? ?? '').toLowerCase();
    final cloudState = (data['cloudState'] as String? ?? '').toLowerCase();
    return data['deleted'] == true ||
        lifecycle == 'deleted' ||
        cloudState == 'deleted';
  }

  bool _isTombstone(Map<String, dynamic> data) {
    final lifecycle = (data['lifecycleState'] as String? ?? '').toLowerCase();
    final cloudState = (data['cloudState'] as String? ?? '').toLowerCase();
    return lifecycle == 'tombstone' || cloudState == 'tombstone';
  }

  bool _isTrash(Map<String, dynamic> data) {
    final lifecycle = (data['lifecycleState'] as String? ?? '').toLowerCase();
    final cloudState = (data['cloudState'] as String? ?? '').toLowerCase();
    return data['trashed'] == true ||
        lifecycle == 'trash' ||
        cloudState == 'trash';
  }

  Future<List<VideoMetadata>> getCompletedUserVideos({
    bool includeTrash = false,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 보관함 목록 조회')) {
      return const <VideoMetadata>[];
    }

    final uid = _getCurrentUserId();
    if (uid == null) return const <VideoMetadata>[];
    if (!_canReadExistingCloudClips('클라우드 보관함 목록 조회')) {
      return const <VideoMetadata>[];
    }

    try {
      final snapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .where('uploadStatus', isEqualTo: 'completed')
          .get();

      final videos = snapshot.docs
          .map(VideoMetadata.fromFirestore)
          .where(
            (video) =>
                !video.isDeleted &&
                !video.isTombstone &&
                (includeTrash || !video.isTrash) &&
                (video.storagePath.trim().isNotEmpty ||
                    (video.downloadUrl?.trim().isNotEmpty ?? false)),
          )
          .toList();
      videos.sort((a, b) {
        final aTime = a.completedAt ?? a.createdAt ?? DateTime(0);
        final bTime = b.completedAt ?? b.createdAt ?? DateTime(0);
        return bTime.compareTo(aTime);
      });
      return videos;
    } catch (e) {
      print(
        '[CloudService] ✗ 클라우드 보관함 목록 조회 실패: '
        'errorType=${e.runtimeType}',
      );
      return const <VideoMetadata>[];
    }
  }

  Future<void> enqueuePendingLocalUploads(
    VideoManager manager, {
    String trigger = 'manual',
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 자동 업로드')) return;

    final uid = _getCurrentUserId();
    if (uid == null) return;
    if (!_canStartNewCloudWrite('클라우드 자동 업로드')) return;

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
    if (!_ensureNotGuestForCloud('Cloud 복원')) return false;

    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print(
      '[CloudService] 📥 다운로드 요청: '
      'videoId=${_maskId(videoId, label: 'video-id')}',
    );

    // 1. 보안 검증
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    if (!_canReadExistingCloudClips('Cloud 복원')) {
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

      // 3. 소유권 및 Storage 경로 확인 (보안)
      final docUid = (data['uid'] as String?)?.trim();
      final docVideoId = (data['videoId'] as String?)?.trim();
      if (docUid != uid) {
        print('[CloudService] ✗ 접근 권한 없음');
        return false;
      }

      final storagePath = (data['storagePath'] as String?)?.trim();
      final expectedVideoId = (docVideoId == null || docVideoId.isEmpty)
          ? videoId
          : docVideoId;
      final expectedPrefix = 'users/$uid/videos/$expectedVideoId/';
      if (storagePath == null ||
          storagePath.isEmpty ||
          !storagePath.startsWith(expectedPrefix)) {
        // 보안상 검증된 Storage 경로가 아니면 legacy downloadUrl도 사용하지 않는다.
        print('[CloudService] ✗ 검증되지 않은 Storage 경로');
        return false;
      }

      // 4. Firebase Storage에서 다운로드
      final ref = _storage.ref().child(storagePath);
      final file = File(localPath);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      final tempFile = File(
        p.join(
          parent.path,
          '.${p.basename(localPath)}.download_${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        await ref.writeToFile(tempFile);

        final expectedFileSize = data['fileSize'] is int
            ? data['fileSize'] as int
            : int.tryParse('${data['fileSize']}') ?? 0;
        if (expectedFileSize > 0) {
          final actualFileSize = await tempFile.length();
          if (actualFileSize != expectedFileSize) {
            print('[CloudService] ✗ 다운로드 파일 크기 검증 실패');
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            return false;
          }
        }

        if (await file.exists()) {
          // 호출부가 unique path를 만들지만, 혹시 모를 충돌 시 기존 최종 파일은 보존한다.
          print('[CloudService] ✗ 최종 파일이 이미 존재하여 복원 중단');
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          return false;
        }

        await tempFile.rename(localPath);
      } catch (_) {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }

      print('[CloudService] ✓ 다운로드 완료: localPath=<redacted-path>');
      return true;
    } catch (e) {
      print('[CloudService] ✗ 다운로드 실패: errorType=${e.runtimeType}');
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
    if (!_canStartNewCloudWrite('클라우드 메타데이터 업데이트')) return false;

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

      print(
        '[CloudService] ✓ 메타데이터 업데이트: '
        'videoId=${_maskId(videoId, label: 'video-id')}',
      );
      return true;
    } catch (e) {
      print('[CloudService] ✗ 메타데이터 업데이트 실패: errorType=${e.runtimeType}');
      return false;
    }
  }

  Future<bool> markVideoMovedToAlbum({
    required String videoId,
    required String albumName,
    String? localPath,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 이동 메타데이터 업데이트')) return false;
    if (!_canStartNewCloudWrite('클라우드 이동 메타데이터 업데이트')) return false;
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();
      if (!doc.exists || doc.data()?['uid'] != uid) return false;
      await doc.reference.set({
        'albumName': albumName,
        if (localPath != null) 'localPath': localPath,
        'lifecycleState': 'active',
        'cloudState': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      print(
        '[CloudService] ✗ 클립 이동 메타데이터 업데이트 실패: '
        'errorType=${e.runtimeType}',
      );
      return false;
    }
  }

  Future<bool> markVideoInTrashByLocalPath({
    required String localPath,
    required String originalAlbumName,
    required String trashLocalPath,
  }) async {
    final meta = await findUserVideoByLocalPath(localPath);
    if (meta == null) return false;
    return markVideoInTrash(
      videoId: meta.videoId,
      originalAlbumName: originalAlbumName,
      trashLocalPath: trashLocalPath,
    );
  }

  Future<bool> markVideoInTrash({
    required String videoId,
    required String originalAlbumName,
    String? trashLocalPath,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 휴지통 표시')) return false;
    if (!_canStartNewCloudWrite('클라우드 휴지통 표시')) return false;
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();
      if (!doc.exists || doc.data()?['uid'] != uid) return false;
      final data = doc.data()!;
      await doc.reference.set({
        'lifecycleState': 'trash',
        'cloudState': 'trash',
        'trashed': true,
        'trashedAt': FieldValue.serverTimestamp(),
        'trashedFromAlbumName': originalAlbumName,
        'originalAlbumName': data['originalAlbumName'] ?? originalAlbumName,
        'originalStoragePath':
            data['originalStoragePath'] ?? data['storagePath'],
        'originalStorageTier': data['originalStorageTier'] ?? 'cloud',
        if (trashLocalPath != null) 'localPath': trashLocalPath,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('[CloudService] ✗ 클라우드 휴지통 표시 실패: errorType=${e.runtimeType}');
      return false;
    }
  }

  Future<bool> restoreVideoFromTrash({
    required String videoId,
    required String albumName,
    String? localPath,
  }) async {
    if (!_ensureNotGuestForCloud('클라우드 휴지통 복원')) return false;
    if (!_canStartNewCloudWrite('클라우드 휴지통 복원')) return false;
    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();
      if (!doc.exists || doc.data()?['uid'] != uid) return false;
      await doc.reference.set({
        'albumName': albumName,
        'lifecycleState': 'active',
        'cloudState': 'active',
        'trashed': false,
        if (localPath != null) 'localPath': localPath,
        'restoredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('[CloudService] ✗ 클라우드 휴지통 복원 실패: errorType=${e.runtimeType}');
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
    if (!_canReadExistingCloudClips('클라우드 영상 목록 조회')) {
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

  Future<bool> _markVideoTombstoned({
    required String videoId,
    required String operationLabel,
  }) async {
    print(
      '[CloudService] Cloud tombstone requested: '
      'operation=$operationLabel '
      'videoId=${_maskId(videoId, label: 'video-id')}',
    );

    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;

      if (data['uid'] != uid) {
        print('[CloudService] Cloud tombstone denied: reason=owner_mismatch');
        return false;
      }

      await doc.reference.set({
        'lifecycleState': 'tombstone',
        'cloudState': 'tombstone',
        'trashed': false,
        'movedToDeviceAt': FieldValue.serverTimestamp(),
        'originalAlbumName': data['originalAlbumName'] ?? data['albumName'],
        'originalStoragePath':
            data['originalStoragePath'] ?? data['storagePath'],
        'originalStorageTier': data['originalStorageTier'] ?? 'cloud',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print(
        '[CloudService] Cloud tombstone completed: '
        'operation=$operationLabel '
        'videoId=${_maskId(videoId, label: 'video-id')}',
      );
      return true;
    } catch (e) {
      print(
        '[CloudService] Cloud tombstone failed: '
        'operation=$operationLabel errorType=${e.runtimeType}',
      );
      return false;
    }
  }

  Future<bool> _markVideoDeleted({
    required String videoId,
    required String operationLabel,
  }) async {
    print(
      '[CloudService] Cloud logical delete requested: '
      'operation=$operationLabel '
      'videoId=${_maskId(videoId, label: 'video-id')}',
    );

    final uid = _getCurrentUserId();
    if (uid == null) return false;

    try {
      final doc = await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .get();

      if (!doc.exists) return false;

      final data = doc.data()!;

      if (data['uid'] != uid) {
        print(
          '[CloudService] Cloud logical delete denied: reason=owner_mismatch',
        );
        return false;
      }

      await doc.reference.set({
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'lifecycleState': 'deleted',
        'cloudState': 'deleted',
        'trashed': false,
        'originalAlbumName': data['originalAlbumName'] ?? data['albumName'],
        'originalStoragePath':
            data['originalStoragePath'] ?? data['storagePath'],
        'originalStorageTier': data['originalStorageTier'] ?? 'cloud',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print(
        '[CloudService] Cloud logical delete completed: '
        'operation=$operationLabel '
        'videoId=${_maskId(videoId, label: 'video-id')}',
      );
      return true;
    } catch (e) {
      print(
        '[CloudService] Cloud logical delete failed: '
        'operation=$operationLabel errorType=${e.runtimeType}',
      );
      return false;
    }
  }

  /// 영상 영구 삭제 표시. Storage object는 물리 삭제하지 않는다.
  Future<bool> deleteVideo(String videoId) async {
    if (!_ensureNotGuestForCloud('클라우드 영상 삭제')) return false;
    if (!_canStartNewCloudWrite('클라우드 영상 삭제')) return false;

    return _markVideoDeleted(videoId: videoId, operationLabel: 'delete');
  }

  Future<bool> markVideoMovedToDevice(String videoId) async {
    if (!_ensureNotGuestForCloud('클라우드 영상 기기 이동')) return false;
    if (!_canReadExistingCloudClips('클라우드 영상 기기 이동')) return false;

    return _markVideoTombstoned(
      videoId: videoId,
      operationLabel: 'move_to_device',
    );
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
        '[CloudService] purgeCurrentUserCloudData 중복 호출 감지: '
        'uid=${_maskUid(uid)}, 기존 작업 완료 대기',
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
                'uid=${_maskUid(uid)} '
                'videoId=${_maskId(doc.id, label: 'video-id')} '
                'path=<redacted-path> code=${e.code} message=<redacted-error>',
              );
            } else {
              failedStorageDeletes++;
              print(
                '[CloudService] Storage 삭제 실패(비차단, 계속 진행): '
                'uid=${_maskUid(uid)} '
                'videoId=${_maskId(doc.id, label: 'video-id')} '
                'path=<redacted-path> code=${e.code} message=<redacted-error>',
              );
            }
          } catch (e) {
            failedStorageDeletes++;
            print(
              '[CloudService] Storage 삭제 실패(비차단, 계속 진행): '
              'uid=${_maskUid(uid)} '
              'videoId=${_maskId(doc.id, label: 'video-id')} '
              'path=<redacted-path> errorType=${e.runtimeType}',
            );
          }
        } else if (storagePath != null && storagePath.isNotEmpty) {
          skippedStorageDeletes++;
          print(
            '[CloudService] 업로드 미완료 메타데이터로 Storage 삭제 스킵: '
            'uid=${_maskUid(uid)} '
            'videoId=${_maskId(doc.id, label: 'video-id')} '
            'status=${uploadStatus.isEmpty ? 'unknown' : uploadStatus} '
            'path=<redacted-path>',
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
        message: 'Cloud 데이터 삭제 실패: <redacted-error>',
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
    final hasSessionCachePath = project.clips.any(
      (clip) => _isSessionCachePath(clip.path),
    );
    if (hasSessionCachePath) {
      print(
        '[CloudService][Diag][vlogMeta][upsert][blocked] '
        'reason=session_cache_path_guard localProjectId=${_maskId(project.id, label: 'local-project-id')}',
      );
      return null;
    }

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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'projectDocId=${_maskId(projectDocId, label: 'project-id')} '
        'localProjectId=${_maskId(project.id, label: 'local-project-id')} '
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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'projectDocId=${_maskId(projectDocId, label: 'project-id')} '
        'localProjectId=${_maskId(project.id, label: 'local-project-id')}',
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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'projectDocId=${_maskId(project.cloudProjectId, label: 'project-id')} '
        'localProjectId=${_maskId(project.id, label: 'local-project-id')} '
        'code=${e.code} message=<redacted-error>',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 업서트 실패: '
        'errorType=${e.runtimeType}',
      );
      return null;
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][upsert][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'projectDocId=${_maskId(project.cloudProjectId, label: 'project-id')} '
        'localProjectId=${_maskId(project.id, label: 'local-project-id')} '
        'code=non_firebase_exception errorType=${e.runtimeType}',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 업서트 실패: '
        'errorType=${e.runtimeType}',
      );
      return null;
    }
  }

  bool _isSessionCachePath(String path) {
    return path.contains('edit_session_cache') ||
        path.contains('export_session_cache') ||
        path.contains('cloud_clip_session_cache');
  }

  Future<Map<String, ProjectCloudMetadata>>
  getUserVlogProjectMetadataMap() async {
    if (!_ensureNotGuestForCloud('프로젝트 메타데이터 조회')) {
      return <String, ProjectCloudMetadata>{};
    }

    final uid = _getCurrentUserId();
    if (uid == null) return <String, ProjectCloudMetadata>{};

    try {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][get][start] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'filters=uid==${_maskUid(uid)},deleted==false',
      );

      final snapshot = await _firestore
          .collection(_vlogProjectsCollection)
          .where('uid', isEqualTo: uid)
          .where('deleted', isEqualTo: false)
          .get();

      print(
        '[CloudService][Diag][vlogMeta][get][ok] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'code=${e.code} message=<redacted-error>',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 조회 실패: '
        'errorType=${e.runtimeType}',
      );
      return <String, ProjectCloudMetadata>{};
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][get][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'code=non_firebase_exception errorType=${e.runtimeType}',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 조회 실패: '
        'errorType=${e.runtimeType}',
      );
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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'cloudProjectId=${_maskId(cloudProjectId, label: 'project-id')} '
        'localProjectId=${_maskId(localProjectId, label: 'local-project-id')}',
      );

      if (cloudProjectId != null && cloudProjectId.isNotEmpty) {
        await _firestore
            .collection(_vlogProjectsCollection)
            .doc(cloudProjectId)
            .delete();
        print(
          '[CloudService][Diag][vlogMeta][delete][ok] '
          'collection=$_vlogProjectsCollection '
          'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
          'cloudProjectId=${_maskId(cloudProjectId, label: 'project-id')} '
          'localProjectId=${_maskId(localProjectId, label: 'local-project-id')} '
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
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'cloudProjectId=<lookup> '
        'localProjectId=${_maskId(localProjectId, label: 'local-project-id')} '
        'deletedDocs=${snapshot.docs.length}',
      );
      return true;
    } on FirebaseException catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][delete][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'cloudProjectId=${_maskId(cloudProjectId, label: 'project-id')} '
        'localProjectId=${_maskId(localProjectId, label: 'local-project-id')} '
        'code=${e.code} message=<redacted-error>',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 삭제 실패: '
        'errorType=${e.runtimeType}',
      );
      return false;
    } catch (e) {
      final authUid = _authService.currentUser?.uid;
      print(
        '[CloudService][Diag][vlogMeta][delete][fail] '
        'collection=$_vlogProjectsCollection '
        'authUid=${_maskUid(authUid)} targetUid=${_maskUid(uid)} '
        'cloudProjectId=${_maskId(cloudProjectId, label: 'project-id')} '
        'localProjectId=${_maskId(localProjectId, label: 'local-project-id')} '
        'code=non_firebase_exception errorType=${e.runtimeType}',
      );
      print(
        '[CloudService] ✗ vlog 프로젝트 메타데이터 삭제 실패: '
        'errorType=${e.runtimeType}',
      );
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

    final derivedUsage = await _getCompletedVideoStorageUsage(uid);
    final usage = derivedUsage ?? await _getCurrentStorageUsage(uid);
    return usage / (1024 * 1024 * 1024);
  }

  Future<int?> _getCompletedVideoStorageUsage(String uid) async {
    try {
      final snapshot = await _firestore
          .collection(_videosCollection)
          .where('uid', isEqualTo: uid)
          .where('uploadStatus', isEqualTo: 'completed')
          .get();

      var total = 0;
      var includedCount = 0;
      var skippedDeletedCount = 0;
      var skippedTombstoneCount = 0;
      var skippedMissingCloudRefCount = 0;
      var trashCount = 0;
      var activeCount = 0;
      var missingFileSizeCount = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (_isDeleted(data)) {
          skippedDeletedCount++;
          continue;
        }
        if (_isTombstone(data)) {
          skippedTombstoneCount++;
          continue;
        }
        final hasCloudRef =
            _readString(data['storagePath']).trim().isNotEmpty ||
            _readString(data['downloadUrl']).trim().isNotEmpty;
        if (!hasCloudRef) {
          skippedMissingCloudRefCount++;
          continue;
        }

        includedCount++;
        if (_isTrash(data)) {
          trashCount++;
        } else {
          activeCount++;
        }
        final fileSize = _readInt(data['fileSize']);
        if (fileSize == null || fileSize <= 0) {
          missingFileSizeCount++;
          continue;
        }
        total += fileSize;
      }
      print(
        '[CloudService][StorageUsage] derived '
        'query_count=${snapshot.docs.length} '
        'included_count=$includedCount '
        'active_count=$activeCount '
        'trash_count=$trashCount '
        'skipped_deleted=$skippedDeletedCount '
        'skipped_tombstone=$skippedTombstoneCount '
        'skipped_missing_cloud_ref=$skippedMissingCloudRefCount '
        'missing_file_size=$missingFileSizeCount '
        'derived_bytes=$total',
      );
      return total;
    } catch (e) {
      print(
        '[CloudService] storage usage derive failed: '
        'errorType=${e.runtimeType}',
      );
      return null;
    }
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
      print('[CloudService] ✗ 용량 체크 실패: errorType=${e.runtimeType}');
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
  final String albumName;
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
    required this.albumName,
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
      albumName: albumName,
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

class _GeneratedPosterThumbnail {
  final Uint8List bytes;
  final int width;
  final int height;
  final int durationMs;

  const _GeneratedPosterThumbnail({
    required this.bytes,
    required this.width,
    required this.height,
    required this.durationMs,
  });
}

class _ImageSize {
  final int width;
  final int height;

  const _ImageSize({required this.width, required this.height});
}

class _CloudThumbnailPipelineException implements Exception {
  final String code;
  final String copy;
  final String phase;

  const _CloudThumbnailPipelineException({
    required this.code,
    required this.copy,
    required this.phase,
  });

  @override
  String toString() => code;
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

class CloudStatsSnapshot {
  final int cloudClipCount;
  final double storageUsageGB;
  final double storageLimitGB;
  final SyncStatusSummary syncSummary;
  final DateTime refreshedAt;
  final String trigger;

  const CloudStatsSnapshot({
    required this.cloudClipCount,
    required this.storageUsageGB,
    required this.storageLimitGB,
    required this.syncSummary,
    required this.refreshedAt,
    required this.trigger,
  });
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
  final String lifecycleState;
  final String cloudState;
  final bool trashed;
  final bool deleted;
  final String? originalAlbumName;
  final String storageTier;
  final String? thumbnailStoragePath;
  final String? thumbnailStatus;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final int? durationMs;

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
    this.lifecycleState = 'active',
    this.cloudState = 'active',
    this.trashed = false,
    this.deleted = false,
    this.originalAlbumName,
    this.storageTier = 'cloud',
    this.thumbnailStoragePath,
    this.thumbnailStatus,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.durationMs,
  });

  factory VideoMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VideoMetadata.fromMap(doc.id, data);
  }

  factory VideoMetadata.fromMap(String id, Map<String, dynamic> data) {
    return VideoMetadata(
      videoId: id,
      uid: _readString(data['uid']),
      fileName: _readString(data['fileName']),
      storagePath: _readString(data['storagePath']),
      albumName: _readString(data['albumName']),
      isFavorite: data['isFavorite'] ?? false,
      fileSize: _readInt(data['fileSize']) ?? 0,
      uploadStatus: _readString(data['uploadStatus'], fallback: 'unknown'),
      uploadProgress: _readInt(data['uploadProgress']) ?? 0,
      downloadUrl: _readNullableString(data['downloadUrl']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      errorCopy: data['errorCopy'] as String?,
      lifecycleState: _readString(data['lifecycleState'], fallback: 'active'),
      cloudState: _readString(data['cloudState'], fallback: 'active'),
      trashed: data['trashed'] == true,
      deleted:
          data['deleted'] == true ||
          _readString(data['lifecycleState']).toLowerCase() == 'deleted' ||
          _readString(data['cloudState']).toLowerCase() == 'deleted',
      originalAlbumName: data['originalAlbumName'] as String?,
      storageTier:
          data['storageTier'] as String? ??
          data['originalStorageTier'] as String? ??
          'cloud',
      thumbnailStoragePath: _readNullableString(data['thumbnailStoragePath']),
      thumbnailStatus: _readNullableString(data['thumbnailStatus']),
      thumbnailWidth: _readInt(data['thumbnailWidth']),
      thumbnailHeight: _readInt(data['thumbnailHeight']),
      durationMs: _readInt(data['durationMs']),
    );
  }

  String get fileSizeText =>
      '${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB';

  bool get hasCompletedThumbnail {
    final status = thumbnailStatus?.trim().toLowerCase();
    return status == 'completed' &&
        (thumbnailStoragePath?.trim().isNotEmpty ?? false);
  }

  bool get hasFailedThumbnail =>
      thumbnailStatus?.trim().toLowerCase() == 'failed';

  bool get isTrashOrTombstone => isTrash || isTombstone;

  bool get isTrash =>
      trashed ||
      lifecycleState.toLowerCase() == 'trash' ||
      cloudState.toLowerCase() == 'trash';

  bool get isTombstone =>
      lifecycleState.toLowerCase() == 'tombstone' ||
      cloudState.toLowerCase() == 'tombstone';

  bool get isDeleted =>
      deleted ||
      lifecycleState.toLowerCase() == 'deleted' ||
      cloudState.toLowerCase() == 'deleted';
}

String _readString(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return '$value';
}

String? _readNullableString(Object? value) {
  if (value == null) return null;
  final text = _readString(value).trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
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
