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
  static const String _nextTierKey = '3s_next_user_tier';
  static const String _nextTierEffectiveAtKey = '3s_next_tier_effective_at';

  UserTier _currentTier = UserTier.free;
  DateTime? _purchaseDate;
  String? _productId;
  String? _userId; // Firebase uid
  UserTier? _nextTier;
  DateTime? _nextTierEffectiveAt;
  bool _isEvaluatingExpiry = false;

  /// 현재 사용자 등급 조회
  UserTier get currentTier => _currentTier;
  
  /// 구매 날짜 조회
  DateTime? get purchaseDate => _purchaseDate;
  
  /// 구매한 상품 ID 조회
  String? get productId => _productId;

  /// Firebase 사용자 ID 조회
  String? get userId => _userId;

  /// 예약된 다음 구독 티어 (다운그레이드 예약 등)
  UserTier? get nextTier => _nextTier;

  /// 예약된 티어 적용 시각
  DateTime? get nextTierEffectiveAt => _nextTierEffectiveAt;

  /// 현재 로컬 구독의 추정 만료 시각
  ///
  /// - annual/year 포함 상품: 구매시각 + 1년
  /// - monthly/month 포함 상품: 구매시각 + 1개월
  /// - 미식별 상품: 월간으로 간주(보수적 만료 처리)
  DateTime? get estimatedExpiryAt {
    if (_currentTier == UserTier.free || _purchaseDate == null) {
      return null;
    }

    final cycle = _inferCycle(_productId);
    if (cycle == _SubscriptionCycle.annual) {
      return DateTime(
        _purchaseDate!.year + 1,
        _purchaseDate!.month,
        _purchaseDate!.day,
        _purchaseDate!.hour,
        _purchaseDate!.minute,
        _purchaseDate!.second,
        _purchaseDate!.millisecond,
        _purchaseDate!.microsecond,
      );
    }

    return DateTime(
      _purchaseDate!.year,
      _purchaseDate!.month + 1,
      _purchaseDate!.day,
      _purchaseDate!.hour,
      _purchaseDate!.minute,
      _purchaseDate!.second,
      _purchaseDate!.millisecond,
      _purchaseDate!.microsecond,
    );
  }

  /// 자동 강등 기준 시각 (만료 "다음날 00:00")
  ///
  /// 반환값은 KST 기준 자정 시각(타임존 미지정 DateTime 로컬 표현)이다.
  DateTime? get autoDowngradeAt {
    final expiryAt = estimatedExpiryAt;
    if (expiryAt == null) return null;
    final expiryKst = _toKst(expiryAt);
    return DateTime(expiryKst.year, expiryKst.month, expiryKst.day + 1);
  }

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

      // 예약 티어 로드
      final nextTierString = prefs.getString(_nextTierKey);
      if (nextTierString != null) {
        _nextTier = UserTier.values.firstWhere(
          (e) => e.toString() == nextTierString || e.name == nextTierString,
          orElse: () => _currentTier,
        );
      }

      // 예약 티어 적용 시각 로드
      final nextTierEffectiveAtMillis = prefs.getInt(_nextTierEffectiveAtKey);
      if (nextTierEffectiveAtMillis != null) {
        _nextTierEffectiveAt =
            DateTime.fromMillisecondsSinceEpoch(nextTierEffectiveAtMillis);
      }

      print(
        '[UserStatusManager] 초기화 완료: '
        'tier=$_currentTier, productId=$_productId, userId=$_userId, '
        'nextTier=$_nextTier, nextTierEffectiveAt=$_nextTierEffectiveAt',
      );
    } catch (e) {
      print('[UserStatusManager] 초기화 실패: $e');
      _currentTier = UserTier.free;
      _purchaseDate = null;
      _productId = null;
      _nextTier = null;
      _nextTierEffectiveAt = null;
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

      // 현재 티어가 갱신되면 예약 티어는 정리
      await prefs.remove(_nextTierKey);
      await prefs.remove(_nextTierEffectiveAtKey);
      _nextTier = null;
      _nextTierEffectiveAt = null;

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
      await prefs.remove(_nextTierKey);
      await prefs.remove(_nextTierEffectiveAtKey);

      _currentTier = UserTier.free;
      _purchaseDate = null;
      _productId = null;
      _nextTier = null;
      _nextTierEffectiveAt = null;

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

  /// 만료 기반 자동 Free 강등 평가
  ///
  /// 정책: 혼합 기준 중 로컬 만료 기준
  /// - 만료 시각 이후 즉시 강등하지 않음
  /// - 만료 "다음날 00:00" 이후 강등
  ///
  /// 반환값
  /// - true: 이번 호출에서 Free로 강등됨
  /// - false: 강등 없음(유효/미대상/평가중/실패)
  Future<bool> evaluateAndAutoDowngradeIfExpired({
    DateTime? now,
    String reason = 'unspecified',
  }) async {
    if (_isEvaluatingExpiry) {
      print('[UserStatusManager][Expiry] skip: evaluation already running');
      return false;
    }

    _isEvaluatingExpiry = true;
    try {
      if (_currentTier == UserTier.free) {
        print('[UserStatusManager][Expiry] skip: already free (reason=$reason)');
        return false;
      }

      final boundaryKst = autoDowngradeAt;
      final nowLocal = now ?? DateTime.now();
      if (boundaryKst == null) {
        print(
          '[UserStatusManager][Expiry] skip: boundary unavailable '
          '(reason=$reason, tier=$_currentTier, productId=$_productId, purchaseDate=$_purchaseDate)',
        );
        return false;
      }

      // 정책 기준은 KST(UTC+9) 자정 경계
      final nowKst = _toKst(nowLocal);
      final shouldDowngrade = nowKst.isAfter(boundaryKst) ||
          nowKst.isAtSameMomentAs(boundaryKst);

      print(
        '[UserStatusManager][Expiry] evaluate '
        'reason=$reason nowLocal=$nowLocal nowKst=$nowKst '
        'boundaryKst=$boundaryKst shouldDowngrade=$shouldDowngrade '
        'tier=$_currentTier productId=$_productId purchaseDate=$_purchaseDate expiry=$estimatedExpiryAt',
      );

      if (!shouldDowngrade) {
        return false;
      }

      final downgraded = await resetToFree();
      if (downgraded) {
        print('[UserStatusManager][Expiry] auto downgrade applied -> free');
      }
      return downgraded;
    } catch (e) {
      print('[UserStatusManager][Expiry] evaluation failed: $e');
      return false;
    } finally {
      _isEvaluatingExpiry = false;
    }
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

  /// 다음 갱신일에 적용될 티어를 예약
  Future<bool> setPendingTierChange({
    required UserTier nextTier,
    required DateTime effectiveAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nextTierKey, nextTier.name);
      await prefs.setInt(
        _nextTierEffectiveAtKey,
        effectiveAt.millisecondsSinceEpoch,
      );

      _nextTier = nextTier;
      _nextTierEffectiveAt = effectiveAt;

      print(
        '[UserStatusManager] 예약 티어 저장: '
        'nextTier=$nextTier, effectiveAt=$effectiveAt',
      );
      return true;
    } catch (e) {
      print('[UserStatusManager] 예약 티어 저장 실패: $e');
      return false;
    }
  }

  /// 예약된 티어 변경 정보 제거
  Future<bool> clearPendingTierChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nextTierKey);
      await prefs.remove(_nextTierEffectiveAtKey);
      _nextTier = null;
      _nextTierEffectiveAt = null;
      print('[UserStatusManager] 예약 티어 제거 완료');
      return true;
    } catch (e) {
      print('[UserStatusManager] 예약 티어 제거 실패: $e');
      return false;
    }
  }

  _SubscriptionCycle _inferCycle(String? productId) {
    final normalized = (productId ?? '').toLowerCase();
    if (normalized.contains('annual') || normalized.contains('year')) {
      return _SubscriptionCycle.annual;
    }
    if (normalized.contains('monthly') || normalized.contains('month')) {
      return _SubscriptionCycle.monthly;
    }

    // 상품 ID 미식별 시 월간으로 간주(과도한 권한 잔존 방지)
    print(
      '[UserStatusManager][Expiry] unknown productId cycle -> fallback monthly: productId=$productId',
    );
    return _SubscriptionCycle.monthly;
  }

  DateTime _toKst(DateTime t) {
    final utc = t.isUtc ? t : t.toUtc();
    return utc.add(const Duration(hours: 9));
  }
}

enum _SubscriptionCycle { monthly, annual }
