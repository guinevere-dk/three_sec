import 'package:shared_preferences/shared_preferences.dart';

/// 사용자 등급 타입
enum UserTier {
  free,
  standard,
  premium,
}

/// 사용자 상태 및 등급 관리 매니저
/// 
/// - 사용자의 구독 등급(Free, Standard, Premium)을 관리
/// - SharedPreferences를 통해 로컬에 저장
/// - 결제 완료 시 IAPService에서 setTier() 호출
class UserStatusManager {
  static final UserStatusManager _instance = UserStatusManager._internal();
  factory UserStatusManager() => _instance;
  UserStatusManager._internal();

  static const String _tierKey = '3s_user_tier';
  static const String _purchaseDateKey = '3s_purchase_date';
  static const String _productIdKey = '3s_product_id';
  static const String _userIdKey = '3s_user_id'; // Firebase uid

  UserTier _currentTier = UserTier.free;
  DateTime? _purchaseDate;
  String? _productId;
  String? _userId; // Firebase uid

  /// 현재 사용자 등급 조회
  UserTier get currentTier => _currentTier;
  
  /// 구매 날짜 조회
  DateTime? get purchaseDate => _purchaseDate;
  
  /// 구매한 상품 ID 조회
  String? get productId => _productId;

  /// Firebase 사용자 ID 조회
  String? get userId => _userId;

  /// 초기화 - 앱 시작 시 호출하여 저장된 등급 로드
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 저장된 등급 로드
      final tierString = prefs.getString(_tierKey);
      if (tierString != null) {
        _currentTier = UserTier.values.firstWhere(
          (e) => e.toString() == tierString,
          orElse: () => UserTier.free,
        );
      }

      // 구매 날짜 로드
      final purchaseDateMillis = prefs.getInt(_purchaseDateKey);
      if (purchaseDateMillis != null) {
        _purchaseDate = DateTime.fromMillisecondsSinceEpoch(purchaseDateMillis);
      }

      // 상품 ID 로드
      _productId = prefs.getString(_productIdKey);

      // 사용자 ID 로드
      _userId = prefs.getString(_userIdKey);

      print('[UserStatusManager] 초기화 완료: tier=$_currentTier, productId=$_productId, userId=$_userId');
    } catch (e) {
      print('[UserStatusManager] 초기화 실패: $e');
      _currentTier = UserTier.free;
      _purchaseDate = null;
      _productId = null;
    }
  }

  /// 사용자 등급 설정 (결제 성공 시 호출)
  /// 
  /// [tier] 설정할 등급
  /// [productId] 구매한 상품 ID
  /// [purchaseDate] 구매 날짜 (기본값: 현재 시각)
  Future<bool> setTier(
    UserTier tier, {
    required String productId,
    DateTime? purchaseDate,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 등급 저장
      await prefs.setString(_tierKey, tier.toString());
      
      // 구매 정보 저장
      final date = purchaseDate ?? DateTime.now();
      await prefs.setInt(_purchaseDateKey, date.millisecondsSinceEpoch);
      await prefs.setString(_productIdKey, productId);

      // 메모리 업데이트
      _currentTier = tier;
      _purchaseDate = date;
      _productId = productId;

      print('[UserStatusManager] 등급 업데이트 성공: $tier (상품: $productId)');
      return true;
    } catch (e) {
      print('[UserStatusManager] 등급 업데이트 실패: $e');
      return false;
    }
  }

  /// 무료 등급으로 복원 (구독 취소, 환불 등)
  Future<bool> resetToFree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_tierKey);
      await prefs.remove(_purchaseDateKey);
      await prefs.remove(_productIdKey);

      _currentTier = UserTier.free;
      _purchaseDate = null;
      _productId = null;

      print('[UserStatusManager] 무료 등급으로 복원');
      return true;
    } catch (e) {
      print('[UserStatusManager] 복원 실패: $e');
      return false;
    }
  }

  /// Standard 등급 이상인지 확인
  bool isStandardOrAbove() {
    return _currentTier == UserTier.standard || _currentTier == UserTier.premium;
  }

  /// Premium 등급인지 확인
  bool isPremium() {
    return _currentTier == UserTier.premium;
  }

  /// 등급별 기능 제한 확인용 헬퍼 메서드
  /// 
  /// Free: 기본 기능만
  /// Standard: 광고 제거, 무제한 클립
  /// Premium: Standard + 고급 편집 기능
  bool canUseFeature(String featureName) {
    switch (featureName) {
      case 'unlimited_clips':
        return isStandardOrAbove();
      case 'advanced_editing':
        return isPremium();
      case 'remove_ads':
        return isStandardOrAbove();
      default:
        return true; // 기본 기능은 모두 사용 가능
    }
  }

  /// Firebase 사용자 ID 저장 (로그인 시 호출)
  Future<bool> setUserId(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, uid);
      _userId = uid;
      print('[UserStatusManager] 사용자 ID 저장: $uid');
      return true;
    } catch (e) {
      print('[UserStatusManager] 사용자 ID 저장 실패: $e');
      return false;
    }
  }

  /// Firebase 사용자 ID 삭제 (로그아웃/탈퇴 시 호출)
  Future<bool> clearUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userIdKey);
      _userId = null;
      print('[UserStatusManager] 사용자 ID 삭제');
      return true;
    } catch (e) {
      print('[UserStatusManager] 사용자 ID 삭제 실패: $e');
      return false;
    }
  }
}
