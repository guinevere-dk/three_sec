import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../managers/user_status_manager.dart';

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

  /// 현재 로그인된 사용자
  User? get currentUser => _auth.currentUser;

  /// 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 현재 사용자 UID
  String? get uid => currentUser?.uid;

  /// 로그인 여부
  bool get isSignedIn => currentUser != null;

  // ============================================================
  // Google 로그인
  // ============================================================

  /// Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print('[AuthService] Google 로그인 시작');

      // 1. Google 로그인 플로우 시작
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        print('[AuthService] Google 로그인 취소됨');
        return null; // 사용자가 취소함
      }

      // 2. 인증 정보 획득
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Firebase 인증 자격증명 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Firebase에 로그인
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      print('[AuthService] ✓ Google 로그인 성공: ${userCredential.user?.email}');

      // 5. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Google 로그인 실패: $e');
      print(stackTrace);
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
      final UserCredential userCredential = await _auth.signInWithCredential(oAuthCredential);

      print('[AuthService] ✓ Apple 로그인 성공: ${userCredential.user?.email ?? "이메일 없음"}');

      // 4. 로그인 후 후처리
      await _onSignInSuccess(userCredential.user!);

      return userCredential;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Apple 로그인 실패: $e');
      print(stackTrace);
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

      // 1. UserStatusManager에 uid 저장
      final userManager = UserStatusManager();
      await userManager.setUserId(uid);

      // 2. Firestore에서 구독 등급 동기화
      await _syncSubscriptionFromFirestore(uid);

      // 3. 사용자 프로필 Firestore에 저장/업데이트
      await _updateUserProfile(user);

      print('[AuthService] ✓ 로그인 후처리 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 로그인 후처리 실패: $e');
      print(stackTrace);
    }
  }

  /// Firestore에서 구독 등급 동기화
  Future<void> _syncSubscriptionFromFirestore(String uid) async {
    try {
      final docSnapshot = await _firestore.collection('users').doc(uid).get();
      
      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null) {
          final tierString = data['subscription_tier'] as String?;
          final productId = data['product_id'] as String?;
          final purchaseDateMillis = data['purchase_date'] as int?;

          if (tierString != null) {
            // Firestore의 등급을 UserStatusManager에 반영
            final tier = UserTier.values.firstWhere(
              (t) => t.toString() == tierString,
              orElse: () => UserTier.free,
            );

            final userManager = UserStatusManager();
            await userManager.setTier(
              tier,
              productId: productId ?? 'synced_from_firestore',
              purchaseDate: purchaseDateMillis != null 
                ? DateTime.fromMillisecondsSinceEpoch(purchaseDateMillis)
                : null,
            );

            print('[AuthService] ✓ Firestore에서 등급 동기화: $tier');
          }
        }
      } else {
        print('[AuthService] Firestore에 사용자 데이터 없음 (신규 사용자)');
      }
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore 동기화 실패: $e');
      print(stackTrace);
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
      
      await userRef.set({
        'subscription_tier': tier.toString(),
        'product_id': productId,
        'purchase_date': (purchaseDate ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('[AuthService] ✓ Firestore에 구독 등급 저장: $tier');
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ Firestore 저장 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  // ============================================================
  // 로그아웃
  // ============================================================

  /// 로그아웃
  Future<void> signOut() async {
    try {
      print('[AuthService] 로그아웃 시작');

      // Google 로그아웃
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Firebase 로그아웃
      await _auth.signOut();

      // UserStatusManager 초기화
      final userManager = UserStatusManager();
      await userManager.clearUserId();

      print('[AuthService] ✓ 로그아웃 완료');
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 로그아웃 실패: $e');
      print(stackTrace);
    }
  }

  // ============================================================
  // 회원 탈퇴 (계정 삭제)
  // ============================================================

  /// 회원 탈퇴 (계정 삭제)
  /// 
  /// GDPR 및 개인정보보호법 준수:
  /// 1. Firebase Auth 계정 삭제
  /// 2. Firestore 사용자 데이터 삭제
  /// 3. 로컬 데이터 초기화
  Future<bool> deleteAccount() async {
    if (!isSignedIn) {
      print('[AuthService] 로그인되지 않음. 계정 삭제 불가');
      return false;
    }

    try {
      final uid = currentUser!.uid;
      print('[AuthService] 회원 탈퇴 시작: $uid');

      // 1. Firestore 사용자 데이터 삭제
      await _firestore.collection('users').doc(uid).delete();
      print('[AuthService] ✓ Firestore 데이터 삭제');

      // 2. 로컬 데이터 초기화
      final userManager = UserStatusManager();
      await userManager.resetToFree();
      await userManager.clearUserId();
      print('[AuthService] ✓ 로컬 데이터 초기화');

      // 3. Firebase Auth 계정 삭제 (마지막)
      await currentUser!.delete();
      print('[AuthService] ✓ Firebase 계정 삭제');

      print('[AuthService] ✓ 회원 탈퇴 완료');
      return true;
    } catch (e, stackTrace) {
      print('[AuthService] ✗ 회원 탈퇴 실패: $e');
      print(stackTrace);

      // 재인증이 필요한 경우 (최근 로그인하지 않음)
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        print('[AuthService] 재인증 필요: 다시 로그인 후 탈퇴해야 함');
      }

      return false;
    }
  }
}
