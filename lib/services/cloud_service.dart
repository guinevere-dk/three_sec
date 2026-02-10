import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import 'auth_service.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// 🌩️ 클라우드 백업 서비스 (Firebase Storage + Firestore)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///
/// Standard 등급 이상의 핵심 혜택
/// - Standard: 10GB 저장 용량
/// - Premium: 50GB 저장 용량
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📦 상수 정의
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 등급별 저장 용량 제한 (바이트)
  static const int _standardStorageLimit = 10 * 1024 * 1024 * 1024; // 10GB
  static const int _premiumStorageLimit = 50 * 1024 * 1024 * 1024;  // 50GB

  /// Firestore 컬렉션 경로
  static const String _videosCollection = 'videos';
  static const String _usersCollection = 'users';

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📤 업로드 큐 관리
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  final List<UploadTask> _uploadQueue = [];
  final StreamController<UploadProgress> _progressController = 
      StreamController<UploadProgress>.broadcast();

  bool _isProcessingQueue = false;

  /// 업로드 진행률 스트림
  Stream<UploadProgress> get uploadProgressStream => _progressController.stream;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🔐 보안 검증
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 사용자 인증 확인
  String? _getCurrentUserId() {
    final user = _authService.currentUser;
    if (user == null) {
      print('[CloudService] ✗ 로그인 필요');
      return null;
    }
    return user.uid;
  }

  /// Standard 등급 이상 확인
  bool _checkStandardOrAbove() {
    if (!_userStatusManager.isStandardOrAbove()) {
      print('[CloudService] ✗ Standard 등급 이상 필요 (현재: ${_userStatusManager.currentTier})');
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
    final limit = _userStatusManager.currentTier == UserTier.premium
        ? _premiumStorageLimit
        : _standardStorageLimit;

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
      print('[CloudService] ✗ 사용량 조회 실패: $e');
      return 0;
    }
  }

  /// 저장 용량 사용량 업데이트
  Future<void> _updateStorageUsage(String uid, int delta) async {
    try {
      await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .set({
            'storageUsage': FieldValue.increment(delta),
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      
      print('[CloudService] ✓ 사용량 업데이트: ${delta > 0 ? '+' : ''}${(delta / (1024 * 1024)).toStringAsFixed(2)}MB');
    } catch (e) {
      print('[CloudService] ✗ 사용량 업데이트 실패: $e');
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
  }) async {
    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[CloudService] 📤 업로드 요청');
    print('[CloudService]   - 파일: ${p.basename(videoFile.path)}');
    print('[CloudService]   - 앨범: $albumName');
    print('[CloudService]   - 즐겨찾기: $isFavorite');

    // 1. 보안 검증
    final uid = _getCurrentUserId();
    if (uid == null) return null;

    if (!_checkStandardOrAbove()) {
      return null;
    }

    // 2. 파일 크기 확인
    final fileSize = await videoFile.length();
    print('[CloudService]   - 파일 크기: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)}MB');

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
      await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .set({
            'uid': uid,
            'videoId': videoId,
            'fileName': fileName,
            'storagePath': storagePath,
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
      );

      return videoId;
    } catch (e) {
      print('[CloudService] ✗ 업로드 준비 실패: $e');
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
  }) async {
    final uploadTask = UploadTask(
      videoFile: videoFile,
      videoId: videoId,
      storagePath: storagePath,
      fileSize: fileSize,
      uid: uid,
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
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    print('[CloudService] 🔄 큐 처리 시작');

    while (_uploadQueue.isNotEmpty) {
      final task = _uploadQueue.first;
      await _executeUpload(task);
      _uploadQueue.removeAt(0);
    }

    _isProcessingQueue = false;
    print('[CloudService] ✓ 큐 처리 완료');
  }

  /// 실제 업로드 실행
  Future<void> _executeUpload(UploadTask task) async {
    print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('[CloudService] ⚡ 업로드 시작: ${task.videoId}');

    try {
      // Firebase Storage 업로드
      final ref = _storage.ref().child(task.storagePath);
      final uploadTask = ref.putFile(task.videoFile);

      // 진행률 모니터링
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        final progressPercent = (progress * 100).toInt();

        // Firestore 진행률 업데이트
        _firestore
            .collection(_videosCollection)
            .doc(task.videoId)
            .update({
              'uploadProgress': progressPercent,
              'uploadStatus': 'uploading',
            });

        // 스트림 발행
        _progressController.add(UploadProgress(
          videoId: task.videoId,
          progress: progress,
          bytesTransferred: snapshot.bytesTransferred,
          totalBytes: snapshot.totalBytes,
        ));

        if (progressPercent % 20 == 0) {
          print('[CloudService] 📊 진행률: $progressPercent%');
        }
      });

      // 업로드 완료 대기
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Firestore 업데이트 (완료)
      await _firestore
          .collection(_videosCollection)
          .doc(task.videoId)
          .update({
            'uploadStatus': 'completed',
            'uploadProgress': 100,
            'downloadUrl': downloadUrl,
            'completedAt': FieldValue.serverTimestamp(),
          });

      // 사용량 업데이트
      await _updateStorageUsage(task.uid, task.fileSize);

      print('[CloudService] ✓ 업로드 완료: ${task.videoId}');
      print('[CloudService]   - URL: $downloadUrl');

    } catch (e) {
      print('[CloudService] ✗ 업로드 실패: $e');

      // Firestore 업데이트 (실패)
      await _firestore
          .collection(_videosCollection)
          .doc(task.videoId)
          .update({
            'uploadStatus': 'failed',
            'errorMessage': e.toString(),
          });
    }
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
      await _firestore
          .collection(_videosCollection)
          .doc(videoId)
          .delete();

      // 5. 사용량 업데이트 (마이너스)
      await _updateStorageUsage(uid, -fileSize);

      print('[CloudService] ✓ 삭제 완료: $videoId');
      return true;

    } catch (e) {
      print('[CloudService] ✗ 삭제 실패: $e');
      return false;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 📊 사용량 조회
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 현재 저장 용량 사용량 조회 (GB)
  Future<double> getStorageUsageGB() async {
    final uid = _getCurrentUserId();
    if (uid == null) return 0.0;

    final usage = await _getCurrentStorageUsage(uid);
    return usage / (1024 * 1024 * 1024);
  }

  /// 저장 용량 제한 조회 (GB)
  double getStorageLimitGB() {
    final limit = _userStatusManager.currentTier == UserTier.premium
        ? _premiumStorageLimit
        : _standardStorageLimit;
    return limit / (1024 * 1024 * 1024);
  }

  /// 사용률 조회 (0.0 ~ 1.0)
  Future<double> getStorageUsageRatio() async {
    final usage = await getStorageUsageGB();
    final limit = getStorageLimitGB();
    return usage / limit;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 🔔 용량 알림 (Premium 전환 유도)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 용량 사용률 체크 및 알림
  /// 
  /// [manager] VideoManager 인스턴스
  /// 
  /// 90% 이상 도달 시 Premium 전환 알림 트리거
  Future<void> checkUsageAndAlert(VideoManager manager) async {
    try {
      final usage = await manager.getCloudUsage();
      
      if (usage.ratio >= 0.9) {
        // 90% 도달 시 알림 트리거
        print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('[CloudService] ⚠️ 용량 90% 도달!');
        print('[CloudService]   - 현재 사용량: ${(usage.ratio * 100).toStringAsFixed(1)}%');
        print('[CloudService]   - 사용량: ${usage.usedBytes / (1024 * 1024 * 1024)} GB');
        print('[CloudService]   - 제한: ${usage.limitBytes / (1024 * 1024 * 1024)} GB');
        print('[CloudService] 📢 Premium 전환 알림 발송 준비');
        print('[CloudService] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
        // TODO: FCM 푸시 알림 전송
        // await _sendHighUsageNotification();
        
        // TODO: 인앱 다이얼로그 표시
        // - "클라우드 저장 공간이 거의 찼습니다!"
        // - "Premium으로 업그레이드하여 50GB를 확보하세요"
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

  UploadTask({
    required this.videoFile,
    required this.videoId,
    required this.storagePath,
    required this.fileSize,
    required this.uid,
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
    );
  }

  String get fileSizeText => 
      (fileSize / (1024 * 1024)).toStringAsFixed(2) + 'MB';
}
