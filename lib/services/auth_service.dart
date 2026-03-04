import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';

typedef CloudPurgeCallback =
    Future<({bool success, String message, String? failedPhase})> Function();

class AccountDeletionResult {
  final bool success;
  final bool requiresRecentLogin;
  final String message;
  final String? failedPhase;

  const AccountDeletionResult({
    required this.success,
    required this.message,
    this.requiresRecentLogin = false,
    this.failedPhase,
  });
}

class AccountDeletionEligibilityResult {
  final bool canDelete;
  final bool hasActiveSubscription;
  final bool requiresCancellationReservation;
  final UserTier currentTier;
  final UserTier? nextTier;
  final DateTime? nextTierEffectiveAt;
  final String message;

  const AccountDeletionEligibilityResult({
    required this.canDelete,
    required this.hasActiveSubscription,
    required this.requiresCancellationReservation,
    required this.currentTier,
    required this.message,
    this.nextTier,
    this.nextTierEffectiveAt,
  });
}

/// Firebase Auth 기반 소셜 로그인 서비스
///
/// 지원 로그인 방식:
/// - Google (구현 완료)
/// - Apple (구현 완료)
/// - Kakao (추후 확장용 placeholder)
/// - Naver (추후 확장용 placeholder)
///
/// 주요 기능:
/// - 소셜 로그인/로그아웃
/// - Firebase uid 관리
/// - Firestore 구독 등급 동기화
/// - 회원 탈퇴 (계정 삭제)
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _cloudSyncedKey = 'cloud_synced_paths';
  Future<AccountDeletionResult>? _accountDeletionInFlight;
  final ValueNotifier<bool> _sessionBootstrapInProgress = ValueNotifier(false);

  /// 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  /// 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 현재 사용자 UID
  String? get uid => currentUser?.uid;

  /// 로그인 여부
  bool get isSignedIn => currentUser != null;

  /// 로그인 직후 세션/구독 동기화 진행 여부
  ValueListenable<bool> get sessionBootstrapInProgress =>
      _sessionBootstrapInProgress;

  // ============================================================
  // Google 로그인
  // ============================================================

  /// Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print('[AuthService] Google 로그인 시작');
      _sessionBootstrapInProgress.value = true;

      // 1. Google 로그인 플로우 시작
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        print('[AuthService] Google 로그인 취소됨');
        _sessionBootstrapInProgress.value = false;
        return null; // 사용자가 취소함
      }

      // 2. 인증 정보 획득
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 3. Firebase 인증 자격증명 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Firebase에 로그인
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      print('[AuthService] ✓ Google 로그인 성공: ${userCredential.user?.email}');

      // 5. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Google 로그인 실패: $e');
      print(stackTrace);
      _sessionBootstrapInProgress.value = false;
      return null;
    }
  }

  // ============================================================
  // Apple 로그인
  // ============================================================

  /// Apple 로그인
  Future<UserCredential?> signInWithApple() async {
    try {
      print('[AuthService] Apple 로그인 시작');
      _sessionBootstrapInProgress.value = true;

      // 1. Apple 로그인 플로우 시작
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // 2. Firebase 인증 자격증명 생성
      final oAuthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // 3. Firebase에 로그인
      final UserCredential userCredential = await _auth.signInWithCredential(
        oAuthCredential,
      );

      print(
        '[AuthService] ✓ Apple 로그인 성공: ${userCredential.user?.email ?? "이메일 없음"}',
      );

      // 4. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Apple 로그인 실패: $e');
      print(stackTrace);
      _sessionBootstrapInProgress.value = false;
      return null;
    }
  }

  // ============================================================
  // Kakao 로그인 (추후 확장용 placeholder)
  // ============================================================

  /// Kakao 로그인 (추후 구현)
  Future<UserCredential?> signInWithKakao() async {
    print('[AuthService] Kakao 로그인은 추후 구현 예정');
    // TODO: kakao_flutter_sdk 패키지 사용
    // 1. KakaoSDK 초기화
    // 2. 카카오 로그인 요청
    // 3. 카카오 토큰으로 Firebase Custom Token 발급 (백엔드 필요)
    // 4. Firebase에 로그인
    return null;
  }

  // ============================================================
  // Naver 로그인 (추후 확장용 placeholder)
  // ============================================================

  /// Naver 로그인 (추후 구현)
  Future<UserCredential?> signInWithNaver() async {
    print('[AuthService] Naver 로그인은 추후 구현 예정');
    // TODO: flutter_naver_login 패키지 사용
    // 1. NaverSDK 초기화
    // 2. 네이버 로그인 요청
    // 3. 네이버 토큰으로 Firebase Custom Token 발급 (백엔드 필요)
    // 4. Firebase에 로그인
    return null;
  }

  // ============================================================
  // 로그인 후처리
  // ============================================================

  /// 로그인 성공 시 후처리
  ///
  /// 1. UserStatusManager에 uid 저장
  /// 2. Firestore에서 구독 등급 동기화
  /// 3. 사용자 프로필 초기화
  Future<void> _onSignInSuccess(User user) async {
    try {
      final uid = user.uid;
      print('[AuthService] 로그인 후처리 시작: $uid');
      print(
        '[AuthService][Diag][Session] sign-in bootstrap '
        'uid=$uid localTier(beforeReset)=${UserStatusManager().currentTier} '
        'localProduct(beforeReset)=${UserStatusManager().productId} '
        'localNextTier(beforeReset)=${UserStatusManager().nextTier}',
      );

      // 1. 사용자 전환 잔여 상태 방지: 로컬 구독 상태 선초기화
      final userManager = UserStatusManager();
      await userManager.resetToFree();
      print(
        '[AuthService][Diag][Session] after resetToFree '
        'uid=$uid localTier=${userManager.currentTier} '
        'localProduct=${userManager.productId} localNextTier=${userManager.nextTier}',
      );

      // 2. UserStatusManager에 uid 저장
      await userManager.setUserId(uid);
      print(
        '[AuthService][Session] setUserId done: uid=$uid, currentTier=${userManager.currentTier}',
      );

      // 3. Firestore에서 구독 등급 동기화
      await _syncSubscriptionFromFirestore(uid);
      print(
        '[AuthService][Session] subscription sync done: uid=$uid, currentTier=${userManager.currentTier}, productId=${userManager.productId}',
      );
      print(
        '[AuthService][Diag][Session] post firestore sync '
        'uid=$uid localTier=${userManager.currentTier} '
        'localProduct=${userManager.productId} '
        'localNextTier=${userManager.nextTier} '
        'localNextTierEffectiveAt=${userManager.nextTierEffectiveAt}',
      );

      // 4. 사용자 프로필 Firestore에 저장/업데이트
      await _updateUserProfile(user);

      print('[AuthService] ✓ 로그인 후처리 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 로그인 후처리 실패: $e');
      print(stackTrace);
    } finally {
      _sessionBootstrapInProgress.value = false;
    }
  }

  /// Firestore에서 구독 등급 동기화
  Future<void> _syncSubscriptionFromFirestore(String uid) async {
    try {
      final userManager = UserStatusManager();
      print(
        '[AuthService][Diag][TierSync] start '
        'uid=$uid localTier(beforeFetch)=${userManager.currentTier} '
        'localProduct(beforeFetch)=${userManager.productId} '
        'localNextTier(beforeFetch)=${userManager.nextTier}',
      );
      final docSnapshot = await _firestore.collection('users').doc(uid).get();

      if (!docSnapshot.exists) {
        await userManager.resetToFree();
        print('[AuthService] Firestore에 사용자 데이터 없음 (신규 사용자)');
        return;
      }

      final data = docSnapshot.data();
      final tierString =
          (data?['subscriptionTier'] as String?) ??
          (data?['subscription_tier'] as String?);
      final productId =
          (data?['productId'] as String?) ?? (data?['product_id'] as String?);
      final nextTierString =
          (data?['nextTier'] as String?) ?? (data?['next_tier'] as String?);

      int? purchaseDateMillis;
      final purchaseDateRaw = data?['purchaseDate'] ?? data?['purchase_date'];
      if (purchaseDateRaw is int) {
        purchaseDateMillis = purchaseDateRaw;
      } else if (purchaseDateRaw is Timestamp) {
        purchaseDateMillis = purchaseDateRaw.millisecondsSinceEpoch;
      }

      int? nextTierEffectiveAtMillis;
      final nextTierEffectiveAtRaw =
          data?['nextTierEffectiveAt'] ?? data?['next_tier_effective_at'];
      if (nextTierEffectiveAtRaw is int) {
        nextTierEffectiveAtMillis = nextTierEffectiveAtRaw;
      } else if (nextTierEffectiveAtRaw is Timestamp) {
        nextTierEffectiveAtMillis =
            nextTierEffectiveAtRaw.millisecondsSinceEpoch;
      }

      print(
        '[AuthService][TierSync] raw firestore data: '
        'uid=$uid, tierString=$tierString, productId=$productId, purchaseDateMillis=$purchaseDateMillis, '
        'nextTierString=$nextTierString, nextTierEffectiveAtMillis=$nextTierEffectiveAtMillis',
      );

      UserTier? tier;
      if (tierString != null) {
        try {
          tier = UserTier.values.firstWhere(
            (t) => t.name == tierString || t.toString() == tierString,
          );
        } catch (_) {
          tier = null;
        }
      }

      UserTier? nextTier;
      if (nextTierString != null) {
        try {
          nextTier = UserTier.values.firstWhere(
            (t) => t.name == nextTierString || t.toString() == nextTierString,
          );
        } catch (_) {
          nextTier = null;
        }
      }

      // 서버 구독 정보가 없거나 비정상이면 로컬 상태 강제 초기화
      if (tier == null || tier == UserTier.free) {
        await userManager.resetToFree();
        print('[AuthService] Firestore 구독 정보 없음/비정상 → 로컬 free로 정합화');
        print(
          '[AuthService][Diag][TierSync] normalized to free '
          'uid=$uid tierFromFirestore=$tier nextTierFromFirestore=$nextTier',
        );
        return;
      }

      await userManager.setTier(
        tier,
        productId: productId ?? 'synced_from_firestore',
        purchaseDate: purchaseDateMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(purchaseDateMillis)
            : null,
      );

      final now = DateTime.now();
      final hasValidPendingChange =
          nextTier != null &&
          nextTierEffectiveAtMillis != null &&
          nextTier != tier &&
          DateTime.fromMillisecondsSinceEpoch(
            nextTierEffectiveAtMillis,
          ).isAfter(now);

      if (hasValidPendingChange) {
        final pendingNextTier = nextTier;
        final pendingEffectiveAtMillis = nextTierEffectiveAtMillis;
        await userManager.setPendingTierChange(
          nextTier: pendingNextTier,
          effectiveAt: DateTime.fromMillisecondsSinceEpoch(
            pendingEffectiveAtMillis,
          ),
        );
      } else {
        await userManager.clearPendingTierChange();
      }

      print(
        '[AuthService][Diag][TierSync] pending-evaluation '
        'uid=$uid hasValidPendingChange=$hasValidPendingChange '
        'nextTierFromFirestore=$nextTier '
        'nextTierEffectiveAtFromFirestore=$nextTierEffectiveAtMillis '
        'localNextTier=${userManager.nextTier} '
        'localNextTierEffectiveAt=${userManager.nextTierEffectiveAt}',
      );

      final canonicalNextTier = hasValidPendingChange ? nextTier.name : null;
      final canonicalNextTierEffectiveAt = hasValidPendingChange
          ? nextTierEffectiveAtMillis
          : null;

      // snake_case → camelCase 정합성 보정
      await _firestore.collection('users').doc(uid).set({
        'subscriptionTier': tier.name,
        'productId': productId,
        if (purchaseDateMillis != null) 'purchaseDate': purchaseDateMillis,
        'nextTier': canonicalNextTier,
        'nextTierEffectiveAt': canonicalNextTierEffectiveAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print(
        '[AuthService][TierSync] canonicalized fields: '
        'subscriptionTier=${tier.name}, productId=$productId',
      );

      final downgraded = await userManager.evaluateAndAutoDowngradeIfExpired(
        reason: 'firestore_sync',
      );
      if (downgraded) {
        await syncFreeTierToFirestore(reason: 'firestore_sync_auto_downgrade');
      }

      print('[AuthService] ✓ Firestore에서 등급 동기화: $tier');
      print(
        '[AuthService][Diag][TierSync] done '
        'uid=$uid localTier=${userManager.currentTier} '
        'localProduct=${userManager.productId} '
        'localNextTier=${userManager.nextTier} '
        'localNextTierEffectiveAt=${userManager.nextTierEffectiveAt}',
      );
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore 동기화 실패: $e');
      print(stackTrace);
      await UserStatusManager().resetToFree();
      print('[AuthService] Firestore 동기화 예외 → 로컬 free로 정합화');
    }
  }

  /// 사용자 프로필 Firestore에 저장/업데이트
  Future<void> _updateUserProfile(User user) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);

      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'display_name': user.displayName,
        'photo_url': user.photoURL,
        'last_sign_in': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // merge: 기존 데이터 유지

      print('[AuthService] ✓ 사용자 프로필 업데이트 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 프로필 업데이트 실패: $e');
      print(stackTrace);
    }
  }

  /// 현재 로그인 사용자의 프로필(닉네임/이미지) 업데이트
  ///
  /// - Firebase Auth `displayName`, `photoURL` 반영
  /// - Firestore `users/{uid}` 문서 동기화
  Future<({bool success, String message})> updateCurrentUserProfile({
    required String displayName,
    File? profileImageFile,
  }) async {
    final user = currentUser;
    if (user == null) {
      return (success: false, message: '로그인이 필요합니다.');
    }

    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return (success: false, message: '닉네임을 입력해 주세요.');
    }

    if (trimmedName.length > 30) {
      return (success: false, message: '닉네임은 30자 이하로 입력해 주세요.');
    }

    try {
      String? photoUrl = user.photoURL;

      print(
        '[AuthService][Diag][ProfileEdit] start '
        'uid=${user.uid} email=${user.email} '
        'hasImage=${profileImageFile != null} '
        'displayNameLen=${trimmedName.length} '
        'bucket=${_storage.bucket}',
      );

      if (profileImageFile != null) {
        final uploadPath =
            'users/${user.uid}/profile/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final fileSize = await profileImageFile.length();
        print(
          '[AuthService][Diag][ProfileEdit] upload prepare '
          'uid=${user.uid} path=$uploadPath size=$fileSize contentType=image/jpeg',
        );

        final ref = _storage
            .ref()
            .child(uploadPath);
        final taskSnapshot = await ref.putFile(
          profileImageFile,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await taskSnapshot.ref.getDownloadURL();
        print(
          '[AuthService][Diag][ProfileEdit] upload success '
          'uid=${user.uid} path=${ref.fullPath} photoUrl=$photoUrl',
        );
      }

      await user.updateDisplayName(trimmedName);
      await user.updatePhotoURL(photoUrl);
      await user.reload();
      print(
        '[AuthService][Diag][ProfileEdit] auth profile updated '
        'uid=${user.uid} displayName=$trimmedName photoUrl=$photoUrl',
      );

      await _firestore.collection('users').doc(user.uid).set({
        'displayName': trimmedName,
        'photoURL': photoUrl,
        'display_name': trimmedName,
        'photo_url': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('[AuthService][Diag][ProfileEdit] firestore sync done uid=${user.uid}');

      print('[AuthService] ✓ 사용자 편집 프로필 업데이트 완료');
      return (success: true, message: '프로필이 저장되었습니다.');
    } on FirebaseException catch (e, stackTrace) {
      print(
        '[AuthService][Diag][ProfileEdit] firebase exception '
        'plugin=${e.plugin} code=${e.code} message=${e.message}',
      );
      print('[AuthService] ✗ 프로필 업데이트 실패(Firebase): ${e.code} ${e.message}');
      print(stackTrace);
      return (success: false, message: '프로필 저장에 실패했습니다. 네트워크 상태를 확인해 주세요.');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 프로필 업데이트 실패: $e');
      print(stackTrace);
      return (success: false, message: '프로필 저장 중 오류가 발생했습니다.');
    }
  }

  // ============================================================
  // 구독 등급을 Firestore에 동기화 (IAP 구매 후 호출)
  // ============================================================

  /// 구독 등급을 Firestore에 저장
  ///
  /// IAPService에서 구매 완료 후 호출하여 서버와 동기화
  Future<bool> syncSubscriptionToFirestore({
    required UserTier tier,
    required String productId,
    DateTime? purchaseDate,
  }) async {
    if (!isSignedIn) {
      print('[AuthService] 로그인되지 않음. Firestore 동기화 불가');
      return false;
    }

    try {
      final userRef = _firestore.collection('users').doc(uid!);
      final purchaseDateMillis =
          (purchaseDate ?? DateTime.now()).millisecondsSinceEpoch;

      await userRef.set({
        // canonical (rules 호환)
        'subscriptionTier': tier.name,
        'productId': productId,
        'purchaseDate': purchaseDateMillis,
        'nextTier': null,
        'nextProductId': null,
        'nextTierEffectiveAt': null,
        'updatedAt': FieldValue.serverTimestamp(),

        // legacy 호환
        'subscription_tier': tier.toString(),
        'product_id': productId,
        'purchase_date': purchaseDateMillis,
        'next_tier': null,
        'next_product_id': null,
        'next_tier_effective_at': null,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print(
        '[AuthService] ✓ Firestore에 구독 등급 저장: '
        'tier=${tier.name}, productId=$productId, purchaseDate=$purchaseDateMillis',
      );
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore 저장 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  /// 다운그레이드 예약(다음 갱신일 적용) 정보를 Firestore에 저장
  Future<bool> syncPendingSubscriptionChangeToFirestore({
    required UserTier nextTier,
    required String nextProductId,
    required DateTime effectiveAt,
    String reason = 'scheduled_change',
  }) async {
    if (!isSignedIn) {
      print('[AuthService] 로그인되지 않음. 예약 구독 변경 동기화 스킵');
      return false;
    }

    try {
      final userRef = _firestore.collection('users').doc(uid!);
      final effectiveAtMillis = effectiveAt.millisecondsSinceEpoch;

      await userRef.set({
        // canonical
        'nextTier': nextTier.name,
        'nextProductId': nextProductId,
        'nextTierEffectiveAt': effectiveAtMillis,
        'subscriptionChangeReason': reason,
        if (nextTier == UserTier.free) 'subscriptionDowngradeReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),

        // legacy
        'next_tier': nextTier.toString(),
        'next_product_id': nextProductId,
        'next_tier_effective_at': effectiveAtMillis,
        'subscription_change_reason': reason,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print(
        '[AuthService] ✓ 예약 구독 변경 저장: '
        'nextTier=${nextTier.name}, nextProductId=$nextProductId, effectiveAt=$effectiveAtMillis',
      );
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 예약 구독 변경 저장 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  /// 자동 만료 강등 시 Free 상태를 Firestore에 정합화
  Future<bool> syncFreeTierToFirestore({
    String reason = 'auto_downgrade',
  }) async {
    if (!isSignedIn) {
      print('[AuthService] 로그인되지 않음. Free 정합화 스킵');
      return false;
    }

    try {
      final userRef = _firestore.collection('users').doc(uid!);
      await userRef.set({
        // canonical
        'subscriptionTier': UserTier.free.name,
        'productId': null,
        'purchaseDate': null,
        'updatedAt': FieldValue.serverTimestamp(),

        // legacy
        'subscription_tier': UserTier.free.toString(),
        'product_id': null,
        'purchase_date': null,
        'updated_at': FieldValue.serverTimestamp(),

        'subscriptionDowngradeReason': reason,
      }, SetOptions(merge: true));

      print('[AuthService] ✓ Firestore Free 정합화 완료: reason=$reason');
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore Free 정합화 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  // ============================================================
  // 로그아웃
  // ============================================================

  /// 로그아웃
  Future<void> signOut({String localDataPolicy = 'retain'}) async {
    try {
      print('[AuthService] 로그아웃 시작');
      final previousUid = currentUser?.uid;
      print(
        '[AuthService][Session] signOut context: previousUid=$previousUid policy=$localDataPolicy',
      );

      // Google 로그아웃
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Firebase 로그아웃
      await _auth.signOut();

      await _resetLocalStateAfterSessionEnd(
        previousUid: previousUid,
        localDataPolicy: localDataPolicy,
      );

      print('[AuthService] ✓ 로그아웃 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 로그아웃 실패: $e');
      print(stackTrace);
    }
  }

  Future<void> _clearUserScopedLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cloudSyncedKey);
    print('[AuthService] 사용자 종속 로컬 캐시 초기화 완료');
  }

  Future<void> _resetLocalStateAfterSessionEnd({
    required String? previousUid,
    required String localDataPolicy,
  }) async {
    // 정책 A: 사용자 종속 로컬 상태 전체 초기화
    final userManager = UserStatusManager();
    await userManager.resetToFree();
    await userManager.clearUserId();
    print(
      '[AuthService][Session] user status reset done: tier=${userManager.currentTier}, userId=${userManager.userId}',
    );

    // 세션 종료 시 로컬 처리 정책 적용
    await VideoManager().handleLogoutLocalData(
      ownerAccountId: previousUid,
      policy: localDataPolicy,
    );
    print('[AuthService][Session] handleLogoutLocalData done');

    // 사용자 종속 캐시 정리
    await _clearUserScopedLocalState();
  }

  // ============================================================
  // 회원 탈퇴 (계정 삭제)
  // ============================================================

  /// 계정 삭제 사전 검증
  ///
  /// 정책(A안):
  /// - 활성 구독이 있으면 기본적으로 계정 삭제 차단
  /// - 단, nextTier=free 예약(해지 예약) + 적용예정시각이 미래인 경우에만 삭제 허용
  Future<AccountDeletionEligibilityResult> checkAccountDeletionEligibility() async {
    if (!isSignedIn) {
      return const AccountDeletionEligibilityResult(
        canDelete: false,
        hasActiveSubscription: false,
        requiresCancellationReservation: false,
        currentTier: UserTier.free,
        message: '로그인 상태가 아니어서 계정을 삭제할 수 없습니다.',
      );
    }

    final userManager = UserStatusManager();
    await userManager.initialize();

    final downgraded = await userManager.evaluateAndAutoDowngradeIfExpired(
      reason: 'delete_preflight',
    );
    if (downgraded) {
      await syncFreeTierToFirestore(reason: 'delete_preflight_auto_downgrade');
    }

    final hasActiveSubscription = userManager.currentTier != UserTier.free;
    if (!hasActiveSubscription) {
      return AccountDeletionEligibilityResult(
        canDelete: true,
        hasActiveSubscription: false,
        requiresCancellationReservation: false,
        currentTier: userManager.currentTier,
        nextTier: userManager.nextTier,
        nextTierEffectiveAt: userManager.nextTierEffectiveAt,
        message: '계정 삭제 가능 상태입니다.',
      );
    }

    final nextTier = userManager.nextTier;
    final nextTierEffectiveAt = userManager.nextTierEffectiveAt;
    final hasValidCancellationReservation =
        nextTier == UserTier.free &&
        nextTierEffectiveAt != null &&
        nextTierEffectiveAt.isAfter(DateTime.now());

    if (!hasValidCancellationReservation) {
      return AccountDeletionEligibilityResult(
        canDelete: false,
        hasActiveSubscription: true,
        requiresCancellationReservation: true,
        currentTier: userManager.currentTier,
        nextTier: nextTier,
        nextTierEffectiveAt: nextTierEffectiveAt,
        message: '활성 구독이 확인되어 계정 삭제를 진행할 수 없습니다. '
            '먼저 구독 해지 후(Free 전환 예약 상태) 다시 시도해주세요.',
      );
    }

    return AccountDeletionEligibilityResult(
      canDelete: true,
      hasActiveSubscription: true,
      requiresCancellationReservation: false,
      currentTier: userManager.currentTier,
      nextTier: nextTier,
      nextTierEffectiveAt: nextTierEffectiveAt,
      message: '해지 예약이 확인되어 계정 삭제를 진행할 수 있습니다.',
    );
  }

  /// 회원 탈퇴 (계정 삭제)
  ///
  /// GDPR 및 개인정보보호법 준수:
  /// 1. Firebase Auth 계정 삭제
  /// 2. Firestore 사용자 데이터 삭제
  /// 3. 로컬 데이터 초기화
  Future<AccountDeletionResult> deleteAccount({
    required CloudPurgeCallback purgeCloud,
    String localDataPolicy = 'delete',
  }) async {
    final inFlight = _accountDeletionInFlight;
    if (inFlight != null) {
      print('[AuthService] 회원 탈퇴 중복 호출 감지: 기존 작업 완료를 대기합니다.');
      return inFlight;
    }

    final future = _performDeleteAccount(
      purgeCloud: purgeCloud,
      localDataPolicy: localDataPolicy,
    );
    _accountDeletionInFlight = future;

    try {
      return await future;
    } finally {
      if (identical(_accountDeletionInFlight, future)) {
        _accountDeletionInFlight = null;
      }
    }
  }

  Future<AccountDeletionResult> _performDeleteAccount({
    required CloudPurgeCallback purgeCloud,
    required String localDataPolicy,
  }) async {
    if (!isSignedIn) {
      print('[AuthService] 로그인되지 않음. 계정 삭제 불가');
      return const AccountDeletionResult(
        success: false,
        message: '로그인 상태가 아니어서 계정을 삭제할 수 없습니다.',
        failedPhase: 'auth',
      );
    }

    try {
      final eligibility = await checkAccountDeletionEligibility();
      if (!eligibility.canDelete) {
        print('[AuthService] 계정 삭제 사전검증 차단: ${eligibility.message}');
        return AccountDeletionResult(
          success: false,
          message: eligibility.message,
          failedPhase: 'subscription_guard',
        );
      }

      final deletingUser = currentUser;
      if (deletingUser == null) {
        return const AccountDeletionResult(
          success: false,
          message: '사용자 세션을 찾지 못했습니다.',
          failedPhase: 'auth',
        );
      }

      final uid = deletingUser.uid;
      print('[AuthService] 회원 탈퇴 시작: $uid');

      // 1. Cloud 데이터 전체 제거
      final purgeResult = await purgeCloud();
      if (!purgeResult.success) {
        print(
          '[AuthService] ✗ Cloud 데이터 삭제 실패 '
          '(phase=${purgeResult.failedPhase}): ${purgeResult.message}',
        );
        return AccountDeletionResult(
          success: false,
          message: purgeResult.message,
          failedPhase: purgeResult.failedPhase ?? 'cloud',
        );
      }
      print('[AuthService] ✓ Cloud 데이터 전체 삭제 완료');

      // 2. Firebase Auth 계정 삭제
      await deletingUser.delete();
      print('[AuthService] ✓ Firebase 계정 삭제');

      // 3. Google 세션 로그아웃 (provider 세션 정리)
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // 4. 로컬 세션/데이터 정리
      await _resetLocalStateAfterSessionEnd(
        previousUid: uid,
        localDataPolicy: localDataPolicy,
      );

      print('[AuthService] ✓ 회원 탈퇴 완료');
      return const AccountDeletionResult(
        success: true,
        message: '계정 삭제가 완료되었습니다.',
      );
    } on FirebaseAuthException catch (e, stackTrace) {
      print('[AuthService] ✗ 회원 탈퇴 실패(FirebaseAuth): ${e.code} ${e.message}');
      print(stackTrace);

      if (e.code == 'requires-recent-login') {
        print('[AuthService] 재인증 필요: 다시 로그인 후 탈퇴해야 함');
        return const AccountDeletionResult(
          success: false,
          requiresRecentLogin: true,
          message: '보안을 위해 최근 로그인 이력이 필요합니다. 다시 로그인 후 계정 삭제를 시도해주세요.',
          failedPhase: 'auth_delete',
        );
      }

      return AccountDeletionResult(
        success: false,
        message: e.message ?? '계정 삭제에 실패했습니다.',
        failedPhase: 'auth_delete',
      );
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 회원 탈퇴 실패: $e');
      print(stackTrace);

      return AccountDeletionResult(
        success: false,
        message: '계정 삭제 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
        failedPhase: 'unknown',
      );
    }
  }
}
