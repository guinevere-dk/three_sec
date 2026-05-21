import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import 'review_fallback_metrics.dart';
import 'cloud_service.dart';

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

class AuthServiceException implements Exception {
  final String code;
  final String message;
  final String? provider;
  final int? httpStatus;
  final String? requestId;
  final Map<String, dynamic>? details;
  final Object? cause;

  const AuthServiceException({
    required this.code,
    required this.message,
    this.provider,
    this.httpStatus,
    this.requestId,
    this.details,
    this.cause,
  });

  String get userMessage {
    switch (code) {
      case 'SOCIAL_AUTH_EXCHANGE_URL_MISSING':
        return '로그인 설정이 누락되었습니다. 앱 실행 옵션을 확인해주세요.';
      case 'EXCHANGE_NETWORK_ERROR':
        return '네트워크 연결이 불안정합니다. 연결 상태를 확인 후 다시 시도해주세요.';
      case 'EXCHANGE_TIMEOUT':
        return '로그인 요청이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';
      case 'INVALID_PROVIDER':
      case 'MISSING_ACCESS_TOKEN':
      case 'INVALID_REQUEST':
        return '로그인 요청 형식이 올바르지 않습니다. 앱을 다시 실행해주세요.';
      case 'INVALID_SOCIAL_TOKEN':
      case 'SOCIAL_USER_NOT_FOUND':
        return '소셜 인증이 만료되었거나 유효하지 않습니다. 다시 로그인해주세요.';
      case 'FIREBASE_TOKEN_ERROR':
      case 'INTERNAL_SERVER_ERROR':
        return '로그인 서버 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
      default:
        return message;
    }
  }

  @override
  String toString() {
    return 'AuthServiceException(code=$code, provider=<redacted-provider>, '
        'httpStatus=$httpStatus, requestId=$requestId)';
  }
}

enum AuthMode { guest, signedIn }

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
  AuthService._internal() {
    // 앱 시작 시 Firebase 세션과 로컬 게스트 상태를 정합화.
    unawaited(_initializeAuthMode());
  }

  static String _maskUid(String? value) {
    final uid = value?.trim();
    if (uid == null || uid.isEmpty) return '<no-uid>';
    if (uid.length <= 8) return '<masked-uid>';
    return '${uid.substring(0, 4)}...${uid.substring(uid.length - 4)}';
  }

  static String _redactedEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return '<no-email>';
    final at = email.indexOf('@');
    if (at <= 0) return '<redacted-email>';
    return '${email[0]}***@***';
  }

  static String _redactedUrl(String? value) {
    final url = value?.trim();
    if (url == null || url.isEmpty) return '<no-url>';
    return '<redacted-url>';
  }

  static String _entitlementTierName(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return 'free';
      case UserTier.standard:
        return 'standard';
      case UserTier.premium:
        return 'premium';
    }
  }

  static String _entitlementTrigger(String reason) {
    switch (reason) {
      case 'startup_warmup':
      case 'app_resumed':
      case 'return_from_paywall':
        return reason;
      case 'profile_initialize':
        return 'profile_init';
      case 'profile_refresh':
        return 'profile_refresh';
      case 'screen_init':
      case 'return_from_play_cancel':
      case 'manual_refresh':
        return 'subscription_management_init';
      default:
        return 'startup_warmup';
    }
  }

  static void _logEntitlementRefresh({
    required String trigger,
    required String source,
    required UserTier beforeTier,
    required UserTier afterTier,
    required String result,
    required String reasonCode,
    required int durationMs,
  }) {
    print(
      '[EntitlementRefresh] '
      'trigger=${_entitlementTrigger(trigger)} '
      'source=$source '
      'before_tier=${_entitlementTierName(beforeTier)} '
      'after_tier=${_entitlementTierName(afterTier)} '
      'result=$result '
      'reason_code=$reasonCode '
      'candidate_count=0 '
      'verified_active_count=0 '
      'verified_inactive_count=0 '
      'verification_failed_count=0 '
      'duration_ms=$durationMs',
    );
  }

  static String _redactedAuthError(Object error) {
    if (error is FirebaseAuthException) {
      return 'FirebaseAuthException(code=${error.code})';
    }
    if (error is AuthServiceException) {
      return 'AuthServiceException(code=${error.code}, '
          'httpStatus=${error.httpStatus}, requestId=${error.requestId})';
    }
    return error.runtimeType.toString();
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ReviewFallbackMetrics _reviewFallbackMetrics = ReviewFallbackMetrics();
  final ValueNotifier<AuthMode> _authMode = ValueNotifier<AuthMode>(
    AuthMode.signedIn,
  );
  static const bool guestLoginEnabledDefault = bool.fromEnvironment(
    'GUEST_LOGIN_ENABLED',
    defaultValue: true,
  );
  static const bool r3QaSubscriptionLockRequested = bool.fromEnvironment(
    'R3_QA_SUBSCRIPTION_LOCK',
    defaultValue: false,
  );
  static const String _guestLoginEnabledKey = '3s_guest_login_enabled';
  static const String _socialAuthExchangeUrl = String.fromEnvironment(
    'SOCIAL_AUTH_EXCHANGE_URL',
    defaultValue: '',
  );
  static const String _oidcProviderAudience = String.fromEnvironment(
    'OIDC_PROVIDER_AUDIENCE',
    defaultValue: '',
  );
  static const String _oidcKakaoClientId = String.fromEnvironment(
    'OIDC_KAKAO_CLIENT_ID',
    defaultValue: '',
  );
  static const String _oidcNaverClientId = String.fromEnvironment(
    'OIDC_NAVER_CLIENT_ID',
    defaultValue: '',
  );
  static const String _cloudSyncedKey = 'cloud_synced_paths';
  static const String _guestAuthModeKey = '3s_auth_mode_guest';
  static const int _socialAuthExchangeTimeoutSec = 12;
  Future<AccountDeletionResult>? _accountDeletionInFlight;
  final ValueNotifier<bool> _sessionBootstrapInProgress = ValueNotifier(false);
  String? _cachedAppVersion;

  Future<void> _initializeAuthMode() async {
    if (_auth.currentUser != null) {
      await _setAuthMode(AuthMode.signedIn);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool(_guestAuthModeKey) ?? false;
    await _setAuthMode(isGuest ? AuthMode.guest : AuthMode.signedIn);
  }

  Future<void> _setAuthMode(AuthMode mode) async {
    if (_authMode.value == mode) {
      return;
    }
    _authMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestAuthModeKey, mode == AuthMode.guest);
    print('[AuthService] authMode 변경: $mode');
  }

  static bool get isR3QaSubscriptionLockEnabled {
    return !kReleaseMode && r3QaSubscriptionLockRequested;
  }

  @visibleForTesting
  static bool shouldSkipFirestorePaidForQaLock({
    required bool qaLockRequested,
    required bool isReleaseMode,
    required bool isSignedInUser,
    required UserTier localTier,
    required bool localGraceHistoryPresent,
    required UserTier? firestoreCandidateTier,
  }) {
    final lockEnabled = !isReleaseMode && qaLockRequested;
    final firestoreCandidatePaid =
        firestoreCandidateTier == UserTier.standard ||
        firestoreCandidateTier == UserTier.premium;

    return lockEnabled &&
        isSignedInUser &&
        localTier == UserTier.free &&
        localGraceHistoryPresent &&
        firestoreCandidatePaid;
  }

  Future<bool> isGuestLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final override = prefs.getBool(_guestLoginEnabledKey);
      return override ?? guestLoginEnabledDefault;
    } catch (_) {
      return guestLoginEnabledDefault;
    }
  }

  Future<void> setGuestLoginEnabledOverride({required bool enabled}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_guestLoginEnabledKey, enabled);
      print('[AuthService] 게스트 모드 플래그 변경: enabled=$enabled');
    } catch (e) {
      print('[AuthService] 게스트 모드 플래그 변경 실패: $e');
    }
  }

  Future<void> clearGuestLoginEnabledOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestLoginEnabledKey);
      print('[AuthService] 게스트 모드 플래그 오버라이드 초기화');
    } catch (e) {
      print('[AuthService] 게스트 모드 플래그 초기화 실패: $e');
    }
  }

  String _generateGuestUserId() {
    final randomId = Random.secure().nextInt(1 << 31);
    return 'guest_${DateTime.now().millisecondsSinceEpoch}_$randomId';
  }

  void _logRequestHeaders(String label, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      print('[AuthService][Diag][$label] headers=<empty>');
      return;
    }
    final filtered = Map<String, String>.from(headers)
      ..removeWhere(
        (key, _) =>
            key.toLowerCase() == 'authorization' ||
            key.toLowerCase() == 'cookie',
      );
    print('[AuthService][Diag][$label] headers=${filtered.toString()}');
  }

  void _logProfileDocSnapshot(String uid, String phase) {
    unawaited(
      _firestore
          .collection('users')
          .doc(uid)
          .get()
          .then((snapshot) {
            final data = snapshot.data();
            final displayName = data?['displayName'];
            final displayNameLegacy = data?['display_name'];
            final photoURL = data?['photoURL'];
            final photoUrlLegacy = data?['photo_url'];
            print(
              '[AuthService][Diag][ProfileSnapshot] phase=$phase uid=${_maskUid(uid)} '
              'exists=${snapshot.exists} '
              'hasDisplayName=${displayName != null} hasDisplayNameLegacy=${displayNameLegacy != null} '
              'photoURL=${_redactedUrl(_extractStringValue(photoURL, trim: true))} '
              'photo_url=${_redactedUrl(_extractStringValue(photoUrlLegacy, trim: true))} '
              'rawKeys=${data?.keys.toList()} ',
            );
          })
          .catchError((e, stackTrace) {
            print(
              '[AuthService][Diag][ProfileSnapshot] phase=$phase uid=${_maskUid(uid)} read failed: $e',
            );
            print(stackTrace);
          }),
    );
  }

  String? _extractStringValue(dynamic rawValue, {bool trim = true}) {
    if (rawValue == null) return null;
    if (rawValue is String) {
      final v = trim ? rawValue.trim() : rawValue;
      return v.isEmpty ? null : v;
    }
    return null;
  }

  Map<String, dynamic> _compactJsonMap(Map<String, dynamic> payload) {
    final compacted = <String, dynamic>{};
    payload.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      compacted[key] = value;
    });
    return compacted;
  }

  bool _isLikelyUserCancelled(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('cancel') ||
        text.contains('cancelled') ||
        text.contains('canceled') ||
        text.contains('user cancelled') ||
        text.contains('user canceled');
  }

  String _generateNonce() {
    final seed =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 31)}';
    return base64UrlEncode(utf8.encode(seed)).replaceAll('=', '');
  }

  String? _resolveProviderAudience(String provider) {
    final audience = _extractStringValue(_oidcProviderAudience, trim: true);
    return audience;
  }

  String? _resolveProviderClientId(String provider) {
    final normalized = provider.toLowerCase().trim();
    if (normalized == 'kakao') {
      return _extractStringValue(_oidcKakaoClientId, trim: true);
    }
    if (normalized == 'naver') {
      return _extractStringValue(_oidcNaverClientId, trim: true);
    }
    return null;
  }

  Future<String?> _resolveAppVersion() async {
    if (_cachedAppVersion != null && _cachedAppVersion!.trim().isNotEmpty) {
      return _cachedAppVersion;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final version = _extractStringValue(info.version, trim: true);
      final buildNumber = _extractStringValue(info.buildNumber, trim: true);
      final resolved = [
        version,
        buildNumber,
      ].whereType<String>().where((v) => v.isNotEmpty).join('+');
      _cachedAppVersion = resolved.isEmpty ? null : resolved;
      return _cachedAppVersion;
    } catch (_) {
      return null;
    }
  }

  String? _extractNestedStringValue(
    Map<String, dynamic> payload,
    List<String> keys, {
    bool trim = true,
  }) {
    dynamic current = payload;
    for (final key in keys) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }
    return _extractStringValue(current, trim: trim);
  }

  Map<String, dynamic>? _toStringMap(dynamic rawValue) {
    if (rawValue is Map) {
      return Map<String, dynamic>.from(
        rawValue.map((key, value) => MapEntry(key?.toString() ?? '', value)),
      );
    }
    return null;
  }

  bool? _extractBool(dynamic rawValue) {
    if (rawValue is bool) {
      return rawValue;
    }
    if (rawValue is num) {
      if (rawValue == 1) return true;
      if (rawValue == 0) return false;
    }
    if (rawValue is String) {
      final normalized = rawValue.trim().toLowerCase();
      if (['true', '1', 'yes', 'y', 'on'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'no', 'n', 'off', 'disabled'].contains(normalized)) {
        return false;
      }
    }
    return null;
  }

  String? _resolvePrimaryProviderLabel(String provider) {
    final normalized = provider.toLowerCase();
    if (normalized == 'kakao') return 'kakao';
    if (normalized == 'naver') return 'naver';
    if (normalized == 'google') return 'google';
    if (normalized == 'apple') return 'apple';
    return normalized;
  }

  String? _resolveProviderUidForFirestore(User user, String provider) {
    final normalizedProvider = provider.toLowerCase();
    String? fallbackProviderUid;

    for (final entry in user.providerData) {
      final providerId =
          _extractStringValue(entry.providerId, trim: true)?.toLowerCase() ??
          '';
      final candidateUid = _extractStringValue(entry.uid, trim: true);
      if (candidateUid == null || candidateUid.isEmpty) {
        continue;
      }

      if (fallbackProviderUid == null) {
        fallbackProviderUid = candidateUid;
      }

      final matchesProvider =
          providerId == normalizedProvider ||
          providerId == '$normalizedProvider.com' ||
          (providerId.contains(normalizedProvider) && providerId.isNotEmpty);
      if (matchesProvider) {
        return candidateUid;
      }
    }

    return fallbackProviderUid;
  }

  /// 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  /// 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 현재 사용자 UID
  String? get uid => currentUser?.uid;

  /// 로그인 여부
  bool get isSignedIn => currentUser != null;

  /// 게스트 모드 여부
  bool get isGuest => _authMode.value == AuthMode.guest;

  /// 유료 구독/복원/구독 관리에 사용할 수 있는 계정 로그인 여부
  bool get isAuthenticatedAccount => isSignedIn && !isGuest;

  /// 인증 모드 변경 스트림
  ValueListenable<AuthMode> get authMode => _authMode;

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
        unawaited(
          _reviewFallbackMetrics.recordSocialLoginFailure(
            provider: 'google',
            reason: 'user_cancelled',
          ),
        );
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

      print(
        '[AuthService] ✓ Google 로그인 성공: '
        'uid=${_maskUid(userCredential.user?.uid)} '
        'email=${_redactedEmail(userCredential.user?.email)}',
      );

      // 5. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Google 로그인 실패: ${_redactedAuthError(e)}');
      print(stackTrace);
      unawaited(
        _reviewFallbackMetrics.recordSocialLoginFailure(
          provider: 'google',
          reason: e is AuthServiceException
              ? e.code
              : (_isLikelyUserCancelled(e) ? 'user_cancelled' : 'exception'),
        ),
      );
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
        '[AuthService] ✓ Apple 로그인 성공: '
        'uid=${_maskUid(userCredential.user?.uid)} '
        'email=${_redactedEmail(userCredential.user?.email)}',
      );

      // 4. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Apple 로그인 실패: ${_redactedAuthError(e)}');
      print(stackTrace);
      unawaited(
        _reviewFallbackMetrics.recordSocialLoginFailure(
          provider: 'apple',
          reason: e is AuthServiceException
              ? e.code
              : (_isLikelyUserCancelled(e) ? 'user_cancelled' : 'exception'),
        ),
      );
      _sessionBootstrapInProgress.value = false;
      return null;
    }
  }

  // ============================================================
  // Kakao 로그인
  // ============================================================

  /// Kakao 로그인
  Future<UserCredential?> signInWithKakao() async {
    try {
      print('[AuthService] Kakao 로그인 시작');
      _sessionBootstrapInProgress.value = true;

      // [Diag][Kakao] 런타임 환경/초기화 상태 점검 로그
      const kakaoNativeAppKey = String.fromEnvironment(
        'KAKAO_NATIVE_APP_KEY',
        defaultValue: '',
      );
      print(
        '[AuthService][Diag][Kakao] KAKAO_NATIVE_APP_KEY '
        'isEmpty=${kakaoNativeAppKey.isEmpty} length=${kakaoNativeAppKey.length}',
      );

      try {
        final platforms = kakao.KakaoSdk.platforms;
        print('[AuthService][Diag][Kakao] KakaoSdk.platforms=$platforms');
      } catch (e, stackTrace) {
        print(
          '[AuthService][Diag][Kakao] KakaoSdk.platforms 접근 실패 '
          '(초기화 누락 가능): $e',
        );
        print(stackTrace);
      }

      // 네이티브 앱 설정/환경 진단
      print(
        '[AuthService][Diag][Kakao] runMode=${bool.fromEnvironment('dart.vm.product')}',
      );
      print(
        '[AuthService][Diag][Kakao] isKakaoNativeAppKeyInitialized='
        '${kakaoNativeAppKey.isNotEmpty}',
      );

      final isTalkInstalled = await kakao.isKakaoTalkInstalled();
      print('[AuthService][Diag][Kakao] isKakaoTalkInstalled=$isTalkInstalled');

      final kakao.OAuthToken token = await (isTalkInstalled
          ? kakao.UserApi.instance.loginWithKakaoTalk()
          : kakao.UserApi.instance.loginWithKakaoAccount());

      print(
        '[AuthService][Diag][Kakao] loginWithKakao* 완료: '
        'hasAccessToken=${token.accessToken.isNotEmpty}, '
        'hasIdToken=${token.idToken?.isNotEmpty ?? false}',
      );

      final userCredential = await _signInWithSocialProviderCustomToken(
        provider: 'kakao',
        socialAccessToken: token.accessToken,
        socialIdToken: token.idToken,
        socialNonce: _generateNonce(),
        providerAudience: _resolveProviderAudience('kakao'),
        clientId: _resolveProviderClientId('kakao'),
        appVersion: await _resolveAppVersion(),
      );

      print(
        '[AuthService] ✓ Kakao 로그인 성공: '
        'uid=${_maskUid(userCredential.user?.uid)} '
        'email=${_redactedEmail(userCredential.user?.email)} '
        'hasDisplayName=${userCredential.user?.displayName?.trim().isNotEmpty ?? false} '
        'photoUrl=${_redactedUrl(userCredential.user?.photoURL)}',
      );

      await _onSignInSuccess(userCredential.user!);
      return userCredential;
    } catch (e, stackTrace) {
      if (_isLikelyUserCancelled(e)) {
        print('[AuthService] Kakao 로그인 사용자 취소');
        unawaited(
          _reviewFallbackMetrics.recordSocialLoginFailure(
            provider: 'kakao',
            reason: 'user_cancelled',
          ),
        );
        _sessionBootstrapInProgress.value = false;
        return null;
      }
      print('[AuthService] ✗ Kakao 로그인 실패: ${_redactedAuthError(e)}');
      print(stackTrace);
      unawaited(
        _reviewFallbackMetrics.recordSocialLoginFailure(
          provider: 'kakao',
          reason: e is AuthServiceException
              ? e.code
              : (_isLikelyUserCancelled(e) ? 'user_cancelled' : 'exception'),
        ),
      );
      _sessionBootstrapInProgress.value = false;
      if (e is AuthServiceException) {
        rethrow;
      }
      throw AuthServiceException(
        code: 'PROVIDER_LOGIN_FAILED',
        message: '카카오 로그인 처리 중 오류가 발생했습니다.',
        provider: 'kakao',
        cause: e,
      );
    }
  }

  // ============================================================
  // Naver 로그인
  // ============================================================

  /// Naver 로그인
  Future<UserCredential?> signInWithNaver() async {
    try {
      print('[AuthService] Naver 로그인 시작');
      _sessionBootstrapInProgress.value = true;

      final result = await FlutterNaverLogin.logIn();
      if (result.status != NaverLoginStatus.loggedIn) {
        print('[AuthService] Naver 로그인 취소 또는 실패: ${result.status}');
        unawaited(
          _reviewFallbackMetrics.recordSocialLoginFailure(
            provider: 'naver',
            reason: _isLikelyUserCancelled(result.status)
                ? 'user_cancelled'
                : 'status_${result.status.toString().toLowerCase()}',
          ),
        );
        _sessionBootstrapInProgress.value = false;
        return null;
      }

      final accessToken = result.accessToken?.accessToken ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Naver access token is empty.');
      }

      final userCredential = await _signInWithSocialProviderCustomToken(
        provider: 'naver',
        socialAccessToken: accessToken,
        socialNonce: _generateNonce(),
        providerAudience: _resolveProviderAudience('naver'),
        clientId: _resolveProviderClientId('naver'),
        appVersion: await _resolveAppVersion(),
      );

      print(
        '[AuthService] ✓ Naver 로그인 성공: '
        'uid=${_maskUid(userCredential.user?.uid)} '
        'email=${_redactedEmail(userCredential.user?.email)}',
      );

      await _onSignInSuccess(userCredential.user!);
      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Naver 로그인 실패: ${_redactedAuthError(e)}');
      print(stackTrace);
      unawaited(
        _reviewFallbackMetrics.recordSocialLoginFailure(
          provider: 'naver',
          reason: e is AuthServiceException
              ? e.code
              : (_isLikelyUserCancelled(e) ? 'user_cancelled' : 'exception'),
        ),
      );
      _sessionBootstrapInProgress.value = false;
      if (e is AuthServiceException) {
        rethrow;
      }
      throw AuthServiceException(
        code: 'PROVIDER_LOGIN_FAILED',
        message: '네이버 로그인 처리 중 오류가 발생했습니다.',
        provider: 'naver',
        cause: e,
      );
    }
  }

  Future<UserCredential> _signInWithSocialProviderCustomToken({
    required String provider,
    required String socialAccessToken,
    String? socialIdToken,
    String? socialNonce,
    String? providerAudience,
    String? clientId,
    String? appVersion,
    String? rawProviderUserId,
  }) async {
    print('[AuthService][Diag][Exchange] provider=<redacted-provider>');
    print(
      '[AuthService][Diag][Exchange] hasSocialAccessToken=${socialAccessToken.isNotEmpty}',
    );
    print(
      '[AuthService][Diag][Exchange] hasSocialIdToken=${socialIdToken?.isNotEmpty ?? false}',
    );
    _logRequestHeaders('Exchange', const {'Content-Type': 'application/json'});

    if (_socialAuthExchangeUrl.isEmpty) {
      throw const AuthServiceException(
        code: 'SOCIAL_AUTH_EXCHANGE_URL_MISSING',
        message: 'SOCIAL_AUTH_EXCHANGE_URL이 설정되지 않았습니다.',
      );
    }

    Uri exchangeUri;
    try {
      exchangeUri = Uri.parse(_socialAuthExchangeUrl);
    } catch (e, stackTrace) {
      print(
        '[AuthService][Diag][Exchange] invalid exchange uri: $_socialAuthExchangeUrl',
      );
      print(stackTrace);
      throw AuthServiceException(
        code: 'SOCIAL_AUTH_EXCHANGE_URL_INVALID',
        message: 'SOCIAL_AUTH_EXCHANGE_URL 값이 유효한 URL이 아닙니다.',
        provider: provider,
        cause: e,
      );
    }

    print(
      '[AuthService][Diag][Exchange] url=${exchangeUri.scheme}://${exchangeUri.host}${exchangeUri.path.isEmpty ? '' : exchangeUri.path}',
    );
    print(
      '[AuthService][Diag][Exchange] query=${exchangeUri.query.isEmpty ? '<empty>' : exchangeUri.query}',
    );

    final requestBodyMap = _compactJsonMap({
      'provider': provider,
      'accessToken': socialAccessToken,
      'idToken': socialIdToken,
      'nonce': socialNonce,
      'providerAudience': providerAudience,
      'clientId': clientId,
      'rawProviderUserId': rawProviderUserId,
      'appVersion': appVersion,
    });
    final requestBody = jsonEncode(requestBodyMap);
    print(
      '[AuthService][Diag][Exchange] requestBody='
      '${requestBody.length > 1500 ? '${requestBody.substring(0, 1500)}...' : requestBody}',
    );

    final http.Response response;
    try {
      response = await http
          .post(
            exchangeUri,
            headers: const {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: _socialAuthExchangeTimeoutSec));
    } catch (e, stackTrace) {
      print(
        '[AuthService][Diag][Exchange] post request failed: ${_redactedAuthError(e)}',
      );
      print(stackTrace);
      if (e is SocketException) {
        throw AuthServiceException(
          code: 'EXCHANGE_NETWORK_ERROR',
          message: '토큰 교환 API 네트워크 연결 실패: ${e.message}',
          provider: provider,
          cause: e,
        );
      }
      if (e is TimeoutException) {
        throw AuthServiceException(
          code: 'EXCHANGE_TIMEOUT',
          message: '토큰 교환 API 요청 시간 초과',
          provider: provider,
          cause: e,
        );
      }
      throw AuthServiceException(
        code: 'EXCHANGE_HTTP_ERROR',
        message: '토큰 교환 API 요청 중 오류가 발생했습니다.',
        provider: provider,
        cause: e,
      );
    }

    print(
      '[AuthService][Diag][Exchange] responseStatus=${response.statusCode} '
      'contentType=${response.headers['content-type'] ?? '<unknown>'}',
    );
    print(
      '[AuthService][Diag][Exchange] responseBody=${response.body.length > 1500 ? '${response.body.substring(0, 1500)}...' : response.body}',
    );

    if (response.statusCode != 200) {
      final contentType = (response.headers['content-type'] ?? '')
          .toLowerCase()
          .trim();
      final bodyTrimmed = response.body.trim();
      final bodyPreview = response.body.isEmpty
          ? '<empty>'
          : (response.body.length > 300
                ? '${response.body.substring(0, 300)}...'
                : response.body);

      final looksLikeHtml404 =
          contentType.contains('text/html') &&
          bodyTrimmed.isNotEmpty &&
          (bodyTrimmed.toLowerCase().contains('page not found') ||
              bodyTrimmed.toLowerCase().contains('404'));

      final endpointHint = looksLikeHtml404
          ? '요청 URL이 현재 배포된 Cloud Functions 경로/리전과 불일치 가능성이 높습니다.'
          : '서버 응답이 성공(200) 형태가 아닙니다.';

      Map<String, dynamic>? responsePayload;
      Map<String, dynamic>? responseError;
      if (bodyTrimmed.startsWith('{') ||
          contentType.contains('application/json')) {
        try {
          final decoded = jsonDecode(bodyTrimmed);
          if (decoded is Map<String, dynamic>) {
            responsePayload = decoded;
            responseError = _toStringMap(decoded['error']);
          }
        } catch (_) {}
      }

      final serverCode =
          _extractStringValue(responseError?['code'], trim: true) ??
          _extractStringValue(responsePayload?['code'], trim: true) ??
          'EXCHANGE_HTTP_${response.statusCode}';
      final serverMessage =
          _extractStringValue(responseError?['message'], trim: true) ??
          'Firebase 커스텀 토큰 획득 실패 (HTTP ${response.statusCode}). $endpointHint';

      final responseDetails =
          _toStringMap(responseError?['details']) ??
          _toStringMap(responsePayload?['details']) ??
          <String, dynamic>{};
      final requestId =
          _extractStringValue(response.headers['x-request-id'], trim: true) ??
          _extractStringValue(responseDetails['requestId'], trim: true);

      throw AuthServiceException(
        code: serverCode,
        message: '$serverMessage body=$bodyPreview',
        provider: provider,
        httpStatus: response.statusCode,
        requestId: requestId,
        details: {
          ...responseDetails,
          'httpStatus': response.statusCode,
          'endpointHint': endpointHint,
        },
      );
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AuthServiceException(
          code: 'EXCHANGE_RESPONSE_INVALID',
          message: '커스텀 토큰 응답 형식이 유효하지 않습니다.',
        );
      }
      payload = decoded;
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        code: 'EXCHANGE_RESPONSE_INVALID',
        message: '커스텀 토큰 응답(JSON 파싱 실패).',
        provider: provider,
        cause: e,
      );
    }
    print('[AuthService][Diag][Exchange] payloadKeys=${payload.keys.toList()}');

    final firebaseToken =
        (payload['firebaseToken'] ?? payload['customToken'] ?? payload['token'])
            as String?;

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw AuthServiceException(
        code: 'FIREBASE_TOKEN_MISSING',
        message: 'Firebase 커스텀 토큰이 응답에 없습니다.',
        provider: provider,
        details: {'payloadKeys': payload.keys.toList()},
      );
    }

    final socialDisplayName =
        _extractStringValue(payload['displayName'], trim: true) ??
        _extractStringValue(payload['display_name'], trim: true) ??
        _extractStringValue(payload['profileDisplayName'], trim: true) ??
        _extractStringValue(payload['nickname'], trim: true) ??
        _extractStringValue(payload['name'], trim: true) ??
        _extractNestedStringValue(payload, ['kakao', 'profile', 'nickname']) ??
        _extractNestedStringValue(payload, ['kakao', 'profile', 'name']) ??
        _extractNestedStringValue(payload, ['kakao_profile', 'nickname']) ??
        _extractNestedStringValue(payload, ['profile', 'nickname']) ??
        _extractNestedStringValue(payload, ['profile', 'name']);

    final socialEmail =
        _extractStringValue(payload['email'], trim: true) ??
        _extractStringValue(payload['emailAddress'], trim: true) ??
        _extractNestedStringValue(payload, [
          'kakao_account',
          'email',
        ], trim: true) ??
        _extractNestedStringValue(payload, ['response', 'email'], trim: true);

    final socialProfileStatus = _toStringMap(payload['profileStatus']);
    final socialProviderInfo = _toStringMap(payload['providerInfo']);
    final exchangeEmailSource = _extractStringValue(
      payload['emailSource'],
      trim: true,
    );

    final socialPhotoUrl =
        _extractStringValue(payload['photoUrl'], trim: true) ??
        _extractStringValue(payload['photo_url'], trim: true) ??
        _extractStringValue(payload['profilePhotoUrl'], trim: true) ??
        _extractStringValue(payload['photo'], trim: true) ??
        _extractStringValue(payload['avatarUrl'], trim: true) ??
        _extractStringValue(payload['avatar_url'], trim: true) ??
        _extractNestedStringValue(payload, [
          'kakao',
          'profile',
          'profile_image_url',
        ]) ??
        _extractNestedStringValue(payload, [
          'kakao_account',
          'profile',
          'thumbnail_image_url',
        ]) ??
        _extractNestedStringValue(payload, [
          'kakao_account',
          'profile',
          'profile_image_url',
        ]) ??
        _extractNestedStringValue(payload, ['profile', 'photoUrl']) ??
        _extractNestedStringValue(payload, ['profile', 'photo_url']);

    print(
      '[AuthService][Diag][Exchange] extractedProfile '
      'provider=<redacted-provider> '
      'hasDisplayName=${socialDisplayName != null && socialDisplayName.isNotEmpty} '
      'photoUrl=${_redactedUrl(socialPhotoUrl)} '
      'email=${_redactedEmail(socialEmail)} emailSource=$exchangeEmailSource '
      'profileStatus=$socialProfileStatus '
      'providerInfo=<redacted-provider-info>',
    );

    final userCredential = await _auth.signInWithCustomToken(firebaseToken);

    await _applySocialProfileFromExchange(
      userCredential.user,
      provider: provider,
      socialDisplayName: socialDisplayName,
      socialPhotoUrl: socialPhotoUrl,
      socialEmail: socialEmail,
      profileStatus: socialProfileStatus,
      providerInfo: socialProviderInfo,
    );

    return userCredential;
  }

  Future<void> _applySocialProfileFromExchange(
    User? user, {
    required String provider,
    required String? socialDisplayName,
    required String? socialPhotoUrl,
    String? socialEmail,
    Map<String, dynamic>? profileStatus,
    Map<String, dynamic>? providerInfo,
  }) async {
    if (user == null) return;

    final providerLabel = _resolvePrimaryProviderLabel(provider);
    final String? providerPhotoUrl = user.providerData
        .map((entry) => _extractStringValue(entry.photoURL, trim: true))
        .firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => null,
        );

    final normalizedProfileStatus = <String, dynamic>{
      'hasDisplayName':
          _extractBool(profileStatus?['hasDisplayName']) ??
          socialDisplayName != null && socialDisplayName.isNotEmpty,
      'hasPhotoUrl':
          _extractBool(profileStatus?['hasPhotoUrl']) ??
          socialPhotoUrl != null && socialPhotoUrl.isNotEmpty,
      'hasEmail':
          _extractBool(profileStatus?['hasEmail']) ??
          socialEmail != null && socialEmail.trim().isNotEmpty,
      'source':
          _extractStringValue(profileStatus?['source'], trim: true) ??
          'client_resolved',
      'displayNameSource':
          _extractStringValue(
            profileStatus?['displayNameSource'],
            trim: true,
          ) ??
          (socialDisplayName == null ? null : 'exchange'),
      'photoUrlSource':
          _extractStringValue(profileStatus?['photoUrlSource'], trim: true) ??
          (socialPhotoUrl == null ? null : 'exchange'),
      'emailSource':
          _extractStringValue(profileStatus?['emailSource'], trim: true) ??
          (socialEmail == null ? null : 'exchange'),
      'requestAttemptCount': (profileStatus?['requestAttemptCount'] is int)
          ? profileStatus!['requestAttemptCount'] as int
          : (profileStatus?['requestAttemptCount'] is num)
          ? (profileStatus!['requestAttemptCount'] as num).toInt()
          : null,
      'usedFallbackUserMe':
          _extractBool(profileStatus?['usedFallbackUserMe']) ?? false,
    };

    final resolvedDisplayName = socialDisplayName;
    final resolvedPhotoUrl = socialPhotoUrl ?? providerPhotoUrl;

    final hasProfileName =
        resolvedDisplayName != null && resolvedDisplayName.isNotEmpty;
    final hasProfilePhoto =
        resolvedPhotoUrl != null && resolvedPhotoUrl.isNotEmpty;
    final hasEmail = socialEmail != null && socialEmail.trim().isNotEmpty;

    try {
      print(
        '[AuthService][Diag][Exchange] applyProfile start '
        'uid=${_maskUid(user.uid)} '
        'hasName=$hasProfileName hasPhoto=$hasProfilePhoto '
        'hasEmail=$hasEmail '
        'exchangeNamePresent=${socialDisplayName != null && socialDisplayName.isNotEmpty} '
        'exchangePhoto=${_redactedUrl(socialPhotoUrl)} '
        'provider=<redacted-provider> resolvedProvider=<redacted-provider> '
        'providerPhoto=${_redactedUrl(providerPhotoUrl)} '
        'providerStatus=$normalizedProfileStatus',
      );

      if (hasProfileName) {
        await user.updateDisplayName(resolvedDisplayName);
      }
      if (hasProfilePhoto) {
        await user.updatePhotoURL(resolvedPhotoUrl);
      }
      if (hasEmail) {
        try {
          final normalizedSocialEmail = socialEmail.trim();
          if (normalizedSocialEmail.isNotEmpty &&
              normalizedSocialEmail != user.email) {
            await user.updateEmail(normalizedSocialEmail);
          }
        } on FirebaseAuthException catch (error) {
          print(
            '[AuthService][Diag][Exchange] updateEmail skipped uid=${_maskUid(user.uid)} '
            'code=${error.code} message=${error.message}',
          );
        }
      }

      await user.reload();
      _logProfileDocSnapshot(user.uid, 'beforeExchangeApply');

      final updatePayload = <String, dynamic>{
        'uid': user.uid,
        'email': socialEmail ?? user.email,
        'last_sign_in': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (hasProfileName) {
        updatePayload['displayName'] = resolvedDisplayName;
        updatePayload['display_name'] = resolvedDisplayName;
      }
      if (hasProfilePhoto) {
        updatePayload['photoURL'] = resolvedPhotoUrl;
        updatePayload['photo_url'] = resolvedPhotoUrl;
      }
      updatePayload['provider'] = providerLabel;
      updatePayload['providerUserId'] = _resolveProviderUidForFirestore(
        user,
        provider,
      );
      updatePayload['profileFlags'] = {
        ...normalizedProfileStatus,
        'hasDisplayName':
            _extractBool(normalizedProfileStatus['hasDisplayName']) ??
            hasProfileName,
        'hasPhotoUrl':
            _extractBool(normalizedProfileStatus['hasPhotoUrl']) ??
            hasProfilePhoto,
        'hasEmail':
            _extractBool(normalizedProfileStatus['hasEmail']) ?? hasEmail,
      };
      updatePayload['exchangeSuccess'] = true;
      updatePayload['updatedAt'] = FieldValue.serverTimestamp();
      updatePayload['lastLoginAt'] = FieldValue.serverTimestamp();

      if (providerInfo != null && providerInfo.isNotEmpty) {
        updatePayload['providerInfo'] = providerInfo;
      }
      if (profileStatus != null && profileStatus.isNotEmpty) {
        updatePayload['profileStatus'] = profileStatus;
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(updatePayload, SetOptions(merge: true));

      _logProfileDocSnapshot(user.uid, 'afterExchangeApply');

      print(
        '[AuthService][Diag][Exchange] applyProfile done '
        'uid=${_maskUid(user.uid)} '
        'hasDisplayName=${resolvedDisplayName != null && resolvedDisplayName.isNotEmpty} '
        'photoUrl=${_redactedUrl(resolvedPhotoUrl)} '
        'email=${_redactedEmail(socialEmail)}',
      );
    } catch (e, stackTrace) {
      print(
        '[AuthService][Diag][Exchange] applyProfile failed: ${_redactedAuthError(e)}',
      );
      print(stackTrace);
    }
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
      final maskedUid = _maskUid(uid);
      await _setAuthMode(AuthMode.signedIn);
      final userManager = UserStatusManager();
      final previousLocalUid = userManager.userId;
      final maskedPreviousLocalUid = _maskUid(previousLocalUid);
      final canPreserveLocalTierOnSyncFailure =
          previousLocalUid == uid && userManager.currentTier != UserTier.free;
      print('[AuthService] 로그인 후처리 시작: $maskedUid');
      print(
        '[AuthService][Diag][Session] sign-in bootstrap '
        'uid=$maskedUid localTier(beforeReset)=${UserStatusManager().currentTier} '
        'localProduct(beforeReset)=${UserStatusManager().productId} '
        'localNextTier(beforeReset)=${UserStatusManager().nextTier}',
      );
      print(
        '[AuthService][Diag][Session] tier_preserve_guard '
        'uid=$maskedUid previousLocalUid=$maskedPreviousLocalUid '
        'canPreserveLocalTierOnSyncFailure=$canPreserveLocalTierOnSyncFailure',
      );

      // 1. 사용자 전환 잔여 상태 방지: 로컬 구독 상태 선초기화
      // 동일 uid 재로그인의 경우 동기화 실패 시 즉시 강등을 피하기 위해
      // 기존 로컬 티어를 임시 보존(SYNCING_PENDING)한다.
      if (!canPreserveLocalTierOnSyncFailure) {
        await userManager.resetToFree();
        print(
          '[AuthService][Diag][Session] after resetToFree '
          'uid=$maskedUid localTier=${userManager.currentTier} '
          'localProduct=${userManager.productId} localNextTier=${userManager.nextTier}',
        );
      } else {
        print(
          '[AuthService][Diag][TierSync][SYNCING_PENDING] '
          'preserve local tier before firestore sync '
          'uid=$maskedUid tier=${userManager.currentTier} productId=${userManager.productId}',
        );
      }

      // 2. UserStatusManager에 uid 저장
      await userManager.setUserId(uid);
      print(
        '[AuthService][Session] setUserId done: uid=$maskedUid, currentTier=${userManager.currentTier}',
      );

      // 3. Firestore에서 구독 등급 동기화
      final syncSuccess = await _syncSubscriptionFromFirestoreWithRetry(
        uid,
        preserveLocalOnFailure: canPreserveLocalTierOnSyncFailure,
      );
      if (!syncSuccess && canPreserveLocalTierOnSyncFailure) {
        print(
          '[AuthService][Diag][TierSync][SYNCING_PENDING] '
          'sync failed after retry but local tier is preserved '
          'uid=$maskedUid tier=${userManager.currentTier} productId=${userManager.productId}',
        );
      }
      print(
        '[AuthService][Session] subscription sync done: uid=$maskedUid, currentTier=${userManager.currentTier}, productId=${userManager.productId}',
      );
      print(
        '[AuthService][Diag][Session] post firestore sync '
        'uid=$maskedUid localTier=${userManager.currentTier} '
        'localProduct=${userManager.productId} '
        'localNextTier=${userManager.nextTier} '
        'localNextTierEffectiveAt=${userManager.nextTierEffectiveAt}',
      );

      // 4. 사용자 프로필 Firestore에 저장/업데이트
      await _updateUserProfile(user);

      // 로그인 복귀/앱 재시작 시 저장된 업로드 큐 복구 트리거
      await CloudService().restoreUploadQueueFromStore();
      await VideoManager().syncCloudMetadataToLibrary(
        trigger: 'auth_post_login',
      );

      print('[AuthService] ✓ 로그인 후처리 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 로그인 후처리 실패: $e');
      print(stackTrace);
    } finally {
      _sessionBootstrapInProgress.value = false;
    }
  }

  Future<bool> _syncSubscriptionFromFirestoreWithRetry(
    String uid, {
    required bool preserveLocalOnFailure,
    bool preserveLocalPaidTier = false,
    String reason = 'startup_warmup',
  }) async {
    // [AndroidRelease][Checklist-1]
    // 로그인 직후 Firestore 일시 장애를 고려해 최소 1회 재시도 후,
    // preserveLocalOnFailure=true면 로컬 티어를 즉시 free로 강등하지 않는다.
    final first = await _syncSubscriptionFromFirestore(
      uid,
      preserveLocalOnFailure: preserveLocalOnFailure,
      preserveLocalPaidTier: preserveLocalPaidTier,
      attempt: 1,
      reason: reason,
    );
    if (first) return true;

    print(
      '[AuthService][Diag][TierSync] retry once after sync failure: '
      'uid=${_maskUid(uid)}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));

    return _syncSubscriptionFromFirestore(
      uid,
      preserveLocalOnFailure: preserveLocalOnFailure,
      preserveLocalPaidTier: preserveLocalPaidTier,
      attempt: 2,
      reason: reason,
    );
  }

  Future<bool> syncCurrentUserSubscriptionFromFirestore({
    bool preserveLocalPaidTier = true,
    String reason = 'manual_refresh',
  }) async {
    final currentUid = uid;
    if (currentUid == null || !isAuthenticatedAccount) {
      print(
        '[AuthService][TierSync] current user sync skipped: '
        'reason=$reason signedIn=$isSignedIn guest=$isGuest',
      );
      return false;
    }

    return _syncSubscriptionFromFirestoreWithRetry(
      currentUid,
      preserveLocalOnFailure: true,
      preserveLocalPaidTier: preserveLocalPaidTier,
      reason: reason,
    );
  }

  Future<bool> reconcileCurrentUserEntitlement({required String reason}) async {
    if (!isAuthenticatedAccount) {
      print(
        '[AuthService][EntitlementRefresh] reconcile skipped: '
        'reason=$reason signedIn=$isSignedIn guest=$isGuest',
      );
      return false;
    }

    final synced = await syncCurrentUserSubscriptionFromFirestore(
      preserveLocalPaidTier: true,
      reason: reason,
    );
    await UserStatusManager().initialize();
    return synced;
  }

  /// Firestore에서 구독 등급 동기화
  Future<bool> _syncSubscriptionFromFirestore(
    String uid, {
    required bool preserveLocalOnFailure,
    bool preserveLocalPaidTier = false,
    int attempt = 1,
    String reason = 'startup_warmup',
  }) async {
    final maskedUid = _maskUid(uid);
    final stopwatch = Stopwatch()..start();
    try {
      final userManager = UserStatusManager();
      final beforeTier = userManager.currentTier;
      print(
        '[AuthService][Diag][TierSync] start '
        'attempt=$attempt preserveLocalOnFailure=$preserveLocalOnFailure '
        'uid=$maskedUid localTier(beforeFetch)=${userManager.currentTier} '
        'localProduct(beforeFetch)=${userManager.productId} '
        'localNextTier(beforeFetch)=${userManager.nextTier}',
      );
      final docSnapshot = await _firestore.collection('users').doc(uid).get();

      if (!docSnapshot.exists) {
        if (preserveLocalOnFailure) {
          print(
            '[AuthService][Diag][TierSync][SYNCING_PENDING] '
            'Firestore user doc missing. keep local tier temporarily '
            'uid=$maskedUid attempt=$attempt',
          );
          _logEntitlementRefresh(
            trigger: reason,
            source: 'firestore_cache',
            beforeTier: beforeTier,
            afterTier: userManager.currentTier,
            result: 'preserved',
            reasonCode: 'no_candidate',
            durationMs: stopwatch.elapsedMilliseconds,
          );
          return false;
        }
        await userManager.resetToFree();
        _logEntitlementRefresh(
          trigger: reason,
          source: 'firestore_cache',
          beforeTier: beforeTier,
          afterTier: userManager.currentTier,
          result: 'applied',
          reasonCode: 'firestore_free',
          durationMs: stopwatch.elapsedMilliseconds,
        );
        print('[AuthService] Firestore에 사용자 데이터 없음 (신규 사용자)');
        return true;
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
        'uid=$maskedUid, tierString=$tierString, productId=$productId, purchaseDateMillis=$purchaseDateMillis, '
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

      // 서버 응답이 free인 경우는 정상 정합화로 간주하되,
      // 결제 직후 로컬 유료 권한이 먼저 반영된 상태에서는 Firestore 반영 지연으로
      // 즉시 free 강등되는 것을 피한다.
      if (tier == UserTier.free) {
        if (userManager.currentTier == UserTier.free &&
            userManager.canReadExistingCloudClips()) {
          print(
            '[AuthService][Diag][TierSync][LOCAL_GRACE_PRESERVED] '
            'Firestore free but keep local R3 cloud read grace '
            'uid=$maskedUid attempt=$attempt graceEnds=${userManager.cloudReadGraceEndsAt}',
          );
          _logEntitlementRefresh(
            trigger: reason,
            source: 'firestore_cache',
            beforeTier: beforeTier,
            afterTier: userManager.currentTier,
            result: 'preserved',
            reasonCode: 'local_grace_preserved',
            durationMs: stopwatch.elapsedMilliseconds,
          );
          return true;
        }
        if (preserveLocalPaidTier && userManager.currentTier != UserTier.free) {
          print(
            '[AuthService][Diag][TierSync][LOCAL_PAID_PRESERVED] '
            'Firestore free but keep local paid tier temporarily '
            'uid=$maskedUid attempt=$attempt localTier=${userManager.currentTier} '
            'localProduct=${userManager.productId}',
          );
          _logEntitlementRefresh(
            trigger: reason,
            source: 'firestore_cache',
            beforeTier: beforeTier,
            afterTier: userManager.currentTier,
            result: 'preserved',
            reasonCode: 'local_paid_preserved',
            durationMs: stopwatch.elapsedMilliseconds,
          );
          return false;
        }
        await userManager.resetToFree();
        print('[AuthService] Firestore 구독 정보 없음/비정상 → 로컬 free로 정합화');
        print(
          '[AuthService][Diag][TierSync] normalized to free '
          'uid=$maskedUid tierFromFirestore=$tier nextTierFromFirestore=$nextTier',
        );
        _logEntitlementRefresh(
          trigger: reason,
          source: 'firestore_cache',
          beforeTier: beforeTier,
          afterTier: userManager.currentTier,
          result: 'applied',
          reasonCode: 'firestore_free',
          durationMs: stopwatch.elapsedMilliseconds,
        );
        return true;
      }

      // 비정상 값(null)은 preserve 옵션에서 재시도 대상으로 유지.
      if (tier == null) {
        if (preserveLocalOnFailure) {
          print(
            '[AuthService][Diag][TierSync][SYNCING_PENDING] '
            'invalid tier payload -> keep local tier '
            'uid=$maskedUid attempt=$attempt',
          );
          _logEntitlementRefresh(
            trigger: reason,
            source: 'firestore_cache',
            beforeTier: beforeTier,
            afterTier: userManager.currentTier,
            result: 'preserved',
            reasonCode: 'no_candidate',
            durationMs: stopwatch.elapsedMilliseconds,
          );
          return false;
        }
        await userManager.resetToFree();
        _logEntitlementRefresh(
          trigger: reason,
          source: 'firestore_cache',
          beforeTier: beforeTier,
          afterTier: userManager.currentTier,
          result: 'applied',
          reasonCode: 'firestore_free',
          durationMs: stopwatch.elapsedMilliseconds,
        );
        print('[AuthService] Firestore 구독 정보 비정상(null) → 로컬 free로 정합화');
        return true;
      }

      if (shouldSkipFirestorePaidForQaLock(
        qaLockRequested: r3QaSubscriptionLockRequested,
        isReleaseMode: kReleaseMode,
        isSignedInUser: isAuthenticatedAccount,
        localTier: userManager.currentTier,
        localGraceHistoryPresent: userManager.isInCloudReadGrace(),
        firestoreCandidateTier: tier,
      )) {
        _logEntitlementRefresh(
          trigger: reason,
          source: 'firestore_cache',
          beforeTier: beforeTier,
          afterTier: userManager.currentTier,
          result: 'skipped',
          reasonCode: 'qa_lock_applied',
          durationMs: stopwatch.elapsedMilliseconds,
        );
        return true;
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
        'uid=$maskedUid hasValidPendingChange=$hasValidPendingChange '
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
        'uid=$maskedUid localTier=${userManager.currentTier} '
        'localProduct=${userManager.productId} '
        'localNextTier=${userManager.nextTier} '
        'localNextTierEffectiveAt=${userManager.nextTierEffectiveAt}',
      );
      _logEntitlementRefresh(
        trigger: reason,
        source: 'firestore_cache',
        beforeTier: beforeTier,
        afterTier: userManager.currentTier,
        result: 'applied',
        reasonCode: downgraded ? 'expired_downgrade' : 'firestore_paid',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore 동기화 실패: $e');
      print(stackTrace);
      if (preserveLocalOnFailure) {
        final userManager = UserStatusManager();
        print(
          '[AuthService][Diag][TierSync][SYNCING_PENDING] '
          'sync exception but keep local tier '
          'uid=$maskedUid attempt=$attempt',
        );
        _logEntitlementRefresh(
          trigger: reason,
          source: 'firestore_cache',
          beforeTier: userManager.currentTier,
          afterTier: userManager.currentTier,
          result: 'failed',
          reasonCode: 'no_candidate',
          durationMs: stopwatch.elapsedMilliseconds,
        );
        return false;
      }
      final beforeResetTier = UserStatusManager().currentTier;
      await UserStatusManager().resetToFree();
      _logEntitlementRefresh(
        trigger: reason,
        source: 'firestore_cache',
        beforeTier: beforeResetTier,
        afterTier: UserStatusManager().currentTier,
        result: 'failed',
        reasonCode: 'firestore_free',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      print('[AuthService] Firestore 동기화 예외 → 로컬 free로 정합화');
      return false;
    }
  }

  /// 사용자 프로필 Firestore에 저장/업데이트
  Future<void> _updateUserProfile(User user) async {
    try {
      print(
        '[AuthService][Diag][ProfileUpdate] beforeSet '
        'uid=${_maskUid(user.uid)} email=${_redactedEmail(user.email)} '
        'hasDisplayName=${user.displayName?.trim().isNotEmpty ?? false} '
        'photoUrl=${_redactedUrl(user.photoURL)}',
      );
      _logProfileDocSnapshot(user.uid, 'beforeSet');

      final userRef = _firestore.collection('users').doc(user.uid);

      final profilePayload = <String, dynamic>{
        'uid': user.uid,
        'last_sign_in': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      };

      if (user.email != null && user.email!.trim().isNotEmpty) {
        profilePayload['email'] = user.email;
      }

      final displayName = user.displayName?.trim();
      final photoUrl = user.photoURL?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        profilePayload['displayName'] = displayName;
        profilePayload['display_name'] = displayName;
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        profilePayload['photoURL'] = photoUrl;
        profilePayload['photo_url'] = photoUrl;
      }

      await userRef.set(
        profilePayload,
        SetOptions(merge: true),
      ); // merge: 기존 데이터 유지

      _logProfileDocSnapshot(user.uid, 'afterSet');

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
        'uid=${_maskUid(user.uid)} email=${_redactedEmail(user.email)} '
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
          'uid=${_maskUid(user.uid)} path=<redacted-storage-path> '
          'size=$fileSize contentType=image/jpeg',
        );

        final ref = _storage.ref().child(uploadPath);
        final taskSnapshot = await ref.putFile(
          profileImageFile,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await taskSnapshot.ref.getDownloadURL();
        print(
          '[AuthService][Diag][ProfileEdit] upload success '
          'uid=${_maskUid(user.uid)} path=<redacted-storage-path> '
          'photoUrl=${_redactedUrl(photoUrl)}',
        );
      }

      await user.updateDisplayName(trimmedName);
      await user.updatePhotoURL(photoUrl);
      await user.reload();
      print(
        '[AuthService][Diag][ProfileEdit] auth profile updated '
        'uid=${_maskUid(user.uid)} displayNameLen=${trimmedName.length} '
        'photoUrl=${_redactedUrl(photoUrl)}',
      );

      await _firestore.collection('users').doc(user.uid).set({
        'displayName': trimmedName,
        'photoURL': photoUrl,
        'display_name': trimmedName,
        'photo_url': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print(
        '[AuthService][Diag][ProfileEdit] firestore sync done '
        'uid=${_maskUid(user.uid)}',
      );

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

      // Kakao/Naver 로그아웃
      try {
        await kakao.UserApi.instance.logout();
      } catch (e) {
        print('[AuthService] Kakao 로그아웃 건너뜀: $e');
      }
      try {
        await FlutterNaverLogin.logOut();
      } catch (e) {
        print('[AuthService] Naver 로그아웃 건너뜀: $e');
      }

      // Firebase 로그아웃
      await _auth.signOut();

      await _resetLocalStateAfterSessionEnd(
        previousUid: previousUid,
        localDataPolicy: localDataPolicy,
      );

      await _setAuthMode(AuthMode.signedIn);

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
      '[AuthService][Session] user status reset done: tier=${userManager.currentTier}, userId=${_maskUid(userManager.userId)}',
    );

    // 세션 종료 시 로컬 처리 정책 적용
    await VideoManager().handleLogoutLocalData(
      ownerAccountId: previousUid,
      policy: localDataPolicy,
    );
    print('[AuthService][Session] handleLogoutLocalData done');

    await VideoManager().clearUserScopedLocalCache(trigger: 'session_end');

    // 사용자 종속 캐시 정리
    await _clearUserScopedLocalState();
  }

  /// 게스트 모드 시작
  Future<void> signInAsGuest() async {
    try {
      print('[AuthService] 게스트 모드 시작');
      final userManager = UserStatusManager();

      await userManager.resetToFree();
      await userManager.setUserId(_generateGuestUserId());
      await VideoManager().clearUserScopedLocalCache(trigger: 'guest_sign_in');
      await _clearUserScopedLocalState();
      await _setAuthMode(AuthMode.guest);
      print('[AuthService] ✓ 게스트 모드 시작 완료');
      unawaited(_reviewFallbackMetrics.recordGuestEntry(success: true));
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 게스트 모드 시작 실패: $e');
      print(stackTrace);
      unawaited(
        _reviewFallbackMetrics.recordGuestEntry(
          success: false,
          reason: e is AuthServiceException ? e.code : 'exception',
        ),
      );
    }
  }

  /// 게스트 모드 종료(로컬 세션만 해제)
  Future<void> signOutGuest() async {
    if (!isGuest) {
      return;
    }

    try {
      print('[AuthService] 게스트 모드 종료');
      final userManager = UserStatusManager();
      await userManager.resetToFree();
      await userManager.clearUserId();
      await VideoManager().clearUserScopedLocalCache(trigger: 'guest_sign_out');
      await _clearUserScopedLocalState();
      await _setAuthMode(AuthMode.signedIn);
      print('[AuthService] ✓ 게스트 모드 종료 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 게스트 모드 종료 실패: $e');
      print(stackTrace);
    }
  }

  // ============================================================
  // 회원 탈퇴 (계정 삭제)
  // ============================================================

  /// 계정 삭제 사전 검증
  ///
  /// 정책(A안):
  /// - 활성 구독이 있으면 기본적으로 계정 삭제 차단
  /// - 단, nextTier=free 예약(해지 예약) + 적용예정시각이 미래인 경우에만 삭제 허용
  Future<AccountDeletionEligibilityResult>
  checkAccountDeletionEligibility() async {
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
        message:
            '활성 구독이 확인되어 계정 삭제를 진행할 수 없습니다. '
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
      final maskedUid = _maskUid(uid);
      print('[AuthService] 회원 탈퇴 시작: $maskedUid');

      // Firebase delete는 최근 인증이 필수이므로, 삭제 실패/부분삭제를 막기 위해
      // 사전으로 최근 로그인 여부를 점검한다.
      if (!_isSignInRecentEnoughForDeletion(deletingUser)) {
        print(
          '[AuthService] 재인증 필요: 삭제 전 최근 로그인 이력이 부족함. '
          'requiresReauth guard triggered uid=$maskedUid lastSignIn=${deletingUser.metadata.lastSignInTime}',
        );
        return const AccountDeletionResult(
          success: false,
          requiresRecentLogin: true,
          message: '보안을 위해 최근 로그인 이력이 필요합니다. 로그아웃 후 재로그인한 뒤 삭제를 다시 시도해 주세요.',
          failedPhase: 'auth_delete',
        );
      }

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

  /// 삭제 요청 전에 최근 로그인 이력을 점검하여 requires-recent-login 선제 실패를 유도한다.
  /// NOTE: Firebase delete는 보안 정책상 최근 인증이 필요한 경우가 있어
  /// 사전 점검으로 cloud 데이터까지 삭제된 뒤 Auth delete 실패하는 부작용을 줄임.
  bool _isSignInRecentEnoughForDeletion(
    User user, {
    Duration freshnessWindow = const Duration(minutes: 5),
  }) {
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null) {
      print('[AuthService] 삭제 재인증 점검 skipped: lastSignInTime이 없습니다.');
      return true;
    }

    final elapsed = DateTime.now().difference(lastSignIn);
    print(
      '[AuthService][Diag][DeleteAuth] lastSignIn=$lastSignIn elapsed=${elapsed.inSeconds}s '
      'maxAllowed=${freshnessWindow.inSeconds}s uid=${_maskUid(user.uid)}',
    );
    return elapsed <= freshnessWindow;
  }
}
