import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import '../managers/user_status_manager.dart';
import 'auth_service.dart';

/// 인앱 결제 서비스
///
/// in_app_purchase 패키지를 사용하여 Google Play Store / Apple App Store와 연동
///
/// 주요 기능:
/// - 스토어 연결 초기화
/// - 상품 목록 로드
/// - 구매 처리 및 검증
/// - 구매 복원
/// - 구매 성공 시 UserStatusManager.setTier() 호출
enum IAPSubscriptionCycle { monthly, annual }

enum IAPSubscriptionTier { standard, premium }

enum IAPPlanChangeType { newPurchase, upgrade, downgrade, noChange }

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  /// 상품 ID 정의
  // Requested Product IDs
  static const String standardMonthly = '3s_standard_monthly';
  static const String standardAnnual = '3s_standard_annual';
  static const String premiumMonthly = '3s_premium_monthly';
  static const String premiumAnnual = '3s_premium_annual';

  /// 상품 ID 맵 (사이클 ↔ 등급)
  static const Map<IAPSubscriptionCycle, Map<IAPSubscriptionTier, String>>
  _productIdMap = {
    IAPSubscriptionCycle.monthly: {
      IAPSubscriptionTier.standard: standardMonthly,
      IAPSubscriptionTier.premium: premiumMonthly,
    },
    IAPSubscriptionCycle.annual: {
      IAPSubscriptionTier.standard: standardAnnual,
      IAPSubscriptionTier.premium: premiumAnnual,
    },
  };

  /// 💡 [업데이트] 상품 ID 리스트 (Map 기반)
  static const List<String> _productIds = [
    standardMonthly,
    standardAnnual,
    premiumMonthly,
    premiumAnnual,
  ];

  /// 상품 ID 조회 헬퍼
  static String? productIdFor({
    required IAPSubscriptionCycle cycle,
    required IAPSubscriptionTier tier,
  }) => _productIdMap[cycle]?[tier];

  bool _isInitialized = false;
  bool _isAvailable = false;

  /// 로드된 상품 목록
  List<ProductDetails> _products = [];

  /// 진행 중인 구매 (중복 구매 방지)
  bool _isPurchasing = false;

  DateTime? _lastProductQueryAt;

  /// 초기화 여부
  bool get isInitialized => _isInitialized;

  /// 스토어 사용 가능 여부
  bool get isAvailable => _isAvailable;

  /// 로드된 상품 목록
  List<ProductDetails> get products => _products;

  /// 서비스 초기화
  ///
  /// 앱 시작 시 호출하여:
  /// 1. 스토어 연결 확인
  /// 2. 상품 정보 로드
  /// 3. 구매 이벤트 리스너 등록
  Future<bool> initialize() async {
    if (_isInitialized) {
      print('[IAPService] 이미 초기화됨');
      return true;
    }

    try {
      print(
        '[IAPService][Diag] initialize() 시작 | platform=${Platform.operatingSystem}',
      );
      print('[IAPService][Diag] 요청 상품 ID 목록: $_productIds');

      // 1. 스토어 연결 확인
      _isAvailable = await _iap.isAvailable();
      print('[IAPService][Diag] _iap.isAvailable() = $_isAvailable');
      if (!_isAvailable) {
        print('[IAPService] 스토어를 사용할 수 없습니다');
        return false;
      }

      // 2. 플랫폼별 설정 (Android)
      // 3. 구매 이벤트 리스너 등록
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => print('[IAPService] 구매 스트림 종료'),
        onError: (error) => print('[IAPService] 구매 스트림 에러: $error'),
      );

      // 4. 상품 정보 로드
      final bool productsLoaded = await _loadProducts();
      if (!productsLoaded) {
        print('[IAPService] 상품 로드 실패');
        return false;
      }

      _isInitialized = true;
      print('[IAPService] 초기화 완료 (상품 ${_products.length}개)');
      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 초기화 실패: $e');
      print(stackTrace);
      _isAvailable = false;
      _isInitialized = false;
      return false;
    }
  }

  /// 상품 정보 로드
  Future<bool> _loadProducts() async {
    try {
      _lastProductQueryAt = DateTime.now();
      final stopwatch = Stopwatch()..start();

      print(
        '[IAPService][Diag] queryProductDetails() 호출 시작 @ ${_lastProductQueryAt!.toIso8601String()}',
      );
      print(
        '[IAPService][Diag] query set size=${_productIds.length}, ids=$_productIds',
      );

      // 스토어에서 상품 정보 조회
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        _productIds.toSet(),
      );

      stopwatch.stop();
      print(
        '[IAPService][Diag] queryProductDetails() 완료 | elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      print(
        '[IAPService][Diag] 응답 요약 | found=${response.productDetails.length}, notFound=${response.notFoundIDs.length}, hasError=${response.error != null}',
      );

      // 조회 실패 처리
      if (response.error != null) {
        print(
          '[IAPService] 상품 조회 에러: source=${response.error!.source}, code=${response.error!.code}, message=${response.error!.message}, details=${response.error!.details}',
        );
        return false;
      }

      // 찾을 수 없는 상품 ID 로깅
      if (response.notFoundIDs.isNotEmpty) {
        print('[IAPService] 찾을 수 없는 상품 ID: ${response.notFoundIDs}');

        final missing = response.notFoundIDs.toSet();
        final requested = _productIds.toSet();
        final matched = requested.difference(missing);
        print(
          '[IAPService][Diag] notFound 분석 | matched=$matched, missing=$missing',
        );
      }

      // 상품이 하나도 없으면 실패
      if (response.productDetails.isEmpty) {
        print('[IAPService] 로드된 상품이 없습니다');
        return false;
      }

      _products = response.productDetails;

      // 상품 정보 로깅
      for (var product in _products) {
        print(
          '[IAPService] 상품: ${product.id} | ${product.title} | ${product.price} | currency=${product.currencyCode}',
        );
      }

      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 상품 로드 실패: $e');
      print(
        '[IAPService][Diag] 예외 발생 시점 | lastQueryAt=${_lastProductQueryAt?.toIso8601String()} | platform=${Platform.operatingSystem}',
      );
      print(stackTrace);
      return false;
    }
  }

  /// 구매 시작
  ///
  /// [productId] 구매할 상품 ID
  /// 반환: 구매 요청 성공 여부 (실제 구매 완료는 _onPurchaseUpdate에서 처리)
  Future<bool> purchase(String productId) async {
    // 초기화 확인
    if (!_isInitialized || !_isAvailable) {
      print('[IAPService] 서비스가 초기화되지 않았습니다');
      return false;
    }

    // 중복 구매 방지
    if (_isPurchasing) {
      print('[IAPService] 이미 구매가 진행 중입니다');
      return false;
    }

    // 상품 찾기
    ProductDetails? product;
    try {
      product = _products.firstWhere((p) => p.id == productId);
    } catch (e) {
      print('[IAPService] 상품을 찾을 수 없습니다: $productId');
      return false;
    }

    try {
      _isPurchasing = true;

      final userManager = UserStatusManager();
      final currentTier = userManager.currentTier;
      final currentProductId = userManager.productId;
      final targetTier = _tierFromProductId(productId);
      final changeType = _resolvePlanChangeType(
        currentTier: currentTier,
        targetTier: targetTier,
      );

      print(
        '[IAPService][PlanChange] request '
        'currentTier=$currentTier currentProductId=$currentProductId '
        'targetTier=$targetTier targetProductId=$productId changeType=$changeType',
      );

      // 구매 파라미터 생성
      PurchaseParam purchaseParam;
      if (Platform.isAndroid) {
        purchaseParam = await _buildAndroidPurchaseParam(
          product: product,
          currentProductId: currentProductId,
          changeType: changeType,
        );
      } else {
        purchaseParam = PurchaseParam(productDetails: product);
      }

      // 구매 요청
      final success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

      if (!success) {
        print('[IAPService] 구매 요청 실패: $productId');
        _isPurchasing = false;
        return false;
      }

      if (changeType == IAPPlanChangeType.downgrade) {
        await _reservePendingDowngrade(
          targetTier: targetTier,
          targetProductId: productId,
        );
      }

      print('[IAPService] 구매 요청 성공: $productId');
      // _isPurchasing은 _onPurchaseUpdate에서 false로 변경됨
      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 구매 중 예외 발생: $e');
      print(stackTrace);
      _isPurchasing = false;
      return false;
    }
  }

  /// 구매 이벤트 핸들러
  ///
  /// 구매 상태 변화를 감지하고 처리:
  /// - pending: 구매 대기 중
  /// - purchased: 구매 완료 → 검증 후 UserStatusManager 업데이트
  /// - error: 구매 실패
  /// - canceled: 사용자 취소
  Future<void> _onPurchaseUpdate(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final PurchaseDetails purchase in purchaseDetailsList) {
      print(
        '[IAPService] 구매 상태 업데이트: ${purchase.productID} → ${purchase.status}',
      );

      try {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            // 구매 대기 중 (사용자가 결제 진행 중)
            print('[IAPService] 구매 진행 중: ${purchase.productID}');
            break;

          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            // 구매 완료 또는 복원됨
            final bool valid = await _verifyPurchase(purchase);

            if (valid) {
              // 구매 검증 성공 → 등급 업데이트
              await _deliverProduct(purchase);
              print('[IAPService] ✓ 구매 완료 및 적용: ${purchase.productID}');
            } else {
              // 구매 검증 실패
              print('[IAPService] ✗ 구매 검증 실패: ${purchase.productID}');
            }

            // 구매 처리 완료 표시 (중요!)
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;

          case PurchaseStatus.error:
            // 구매 실패
            final errorCode = purchase.error?.code ?? 'UNKNOWN';
            final errorMessage = purchase.error?.message ?? '알 수 없는 오류';
            print('[IAPService] ✗ 구매 실패: $errorCode - $errorMessage');

            // 구매 처리 완료 표시
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;

          case PurchaseStatus.canceled:
            // 사용자가 구매 취소
            print('[IAPService] 구매 취소: ${purchase.productID}');
            break;
        }
      } catch (e, stackTrace) {
        print('[IAPService] 구매 처리 중 예외: $e');
        print(stackTrace);
      } finally {
        // 구매 플래그 해제
        _isPurchasing = false;
      }
    }
  }

  /// 구매 검증
  ///
  /// 실제 프로덕션에서는 백엔드 서버에서 영수증을 검증해야 함
  /// 현재는 기본 검증만 수행
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    try {
      // 1. 기본 검증: productID가 유효한지 확인
      if (!_productIds.contains(purchase.productID)) {
        print('[IAPService] 검증 실패: 유효하지 않은 상품 ID');
        return false;
      }

      // 2. 플랫폼별 추가 검증
      if (Platform.isAndroid) {
        // Android: verificationData에 서명 정보 포함
        final androidPurchase = purchase as GooglePlayPurchaseDetails;
        if (androidPurchase.verificationData.source != 'google_play') {
          print('[IAPService] 검증 실패: 잘못된 구매 소스');
          return false;
        }

        // TODO: 백엔드 서버로 구매 토큰 전송 및 검증
        // final token = androidPurchase.billingClientPurchase.purchaseToken;
        // await _verifyWithServer(token);
      } else if (Platform.isIOS) {
        // iOS: App Store 영수증 검증
        purchase as AppStorePurchaseDetails;

        // TODO: 백엔드 서버로 영수증 전송 및 검증
        // final receipt = iosPurchase.verificationData.serverVerificationData;
        // await _verifyWithServer(receipt);
      }

      print('[IAPService] 구매 검증 성공: ${purchase.productID}');
      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 구매 검증 중 예외: $e');
      print(stackTrace);
      return false;
    }
  }

  /// 구매한 상품 제공 (등급 업데이트)
  Future<void> _deliverProduct(PurchaseDetails purchase) async {
    try {
      final productId = purchase.productID;
      final userManager = UserStatusManager();

      final targetPlanTier = _tierFromProductId(productId);
      final currentPlanChangeType = _resolvePlanChangeType(
        currentTier: userManager.currentTier,
        targetTier: targetPlanTier,
      );

      // Google Play deferred 다운그레이드의 경우
      // 현재 entitlement를 유지하고 예약 정보만 유지/갱신한다.
      if (currentPlanChangeType == IAPPlanChangeType.downgrade) {
        await _reservePendingDowngrade(
          targetTier: targetPlanTier,
          targetProductId: productId,
        );
        print(
          '[IAPService][PlanChange] deferred downgrade purchase delivered '
          '-> keep current tier, preserve pending change',
        );
        return;
      }

      // 상품 ID에 따라 등급 결정
      UserTier tier;
      if (productId == standardMonthly || productId == standardAnnual) {
        tier = UserTier.standard;
      } else if (productId == premiumMonthly || productId == premiumAnnual) {
        tier = UserTier.premium;
      } else {
        // Fallback or Unknown
        print('[IAPService] 알 수 없는 상품 ID (기본 처리): $productId');
        tier = UserTier
            .premium; // Assume premium for now since we only sell premium
      }

      // UserStatusManager를 통해 등급 업데이트
      final success = await userManager.setTier(
        tier,
        productId: productId,
        purchaseDate: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(purchase.transactionDate ?? '0') ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );

      if (success) {
        print('[IAPService] ✓ 사용자 등급 업데이트 완료: $tier');

        await userManager.clearPendingTierChange();

        // Firestore에 동기화
        final authService = AuthService();
        final purchaseDateTime = DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(purchase.transactionDate ?? '0') ??
              DateTime.now().millisecondsSinceEpoch,
        );

        await authService.syncSubscriptionToFirestore(
          tier: tier,
          productId: productId,
          purchaseDate: purchaseDateTime,
        );
      } else {
        print('[IAPService] ✗ 사용자 등급 업데이트 실패');
      }
    } catch (e, stackTrace) {
      print('[IAPService] 상품 제공 중 예외: $e');
      print(stackTrace);
    }
  }

  /// 구매 복원 (이전에 구매한 항목 복원)
  ///
  /// - iOS: 필수 기능 (App Store 정책)
  /// - Android: 구독 및 비소모성 상품 복원
  Future<bool> restorePurchases() async {
    if (!_isInitialized || !_isAvailable) {
      print('[IAPService] 서비스가 초기화되지 않았습니다');
      return false;
    }

    try {
      print('[IAPService] 구매 복원 시작');
      await _iap.restorePurchases();
      // 복원된 구매는 _onPurchaseUpdate에서 자동 처리됨
      print('[IAPService] 구매 복원 요청 완료');
      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 구매 복원 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  /// Google Play 복귀 시 구독 해지(auto-renew off) 상태를 로컬/Firestore에 반영
  ///
  /// 정책:
  /// - 해지 직후 즉시 Free 강등은 하지 않음
  /// - 현재 플랜은 만료 시점까지 유지
  /// - `nextTier=free` 예약을 저장해 UI에 `현재 → Free`를 노출
  Future<void> syncCancellationStateFromStore({
    String reason = 'manual_refresh',
  }) async {
    if (!Platform.isAndroid) return;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      final userManager = UserStatusManager();
      await userManager.initialize();
      if (userManager.currentTier == UserTier.free) {
        return;
      }

      final currentProductId = userManager.productId;
      final purchase = await _findGooglePlayPurchaseDetails(currentProductId);
      if (purchase == null) {
        print(
          '[IAPService][CancelSync] skip: no matching purchase found '
          '(reason=$reason, currentProductId=$currentProductId)',
        );
        return;
      }

      final autoRenewing = purchase.billingClientPurchase.isAutoRenewing;
      print(
        '[IAPService][CancelSync] queried purchase '
        'productId=${purchase.productID} autoRenewing=$autoRenewing reason=$reason',
      );

      if (autoRenewing) {
        if (userManager.nextTier == UserTier.free) {
          await userManager.clearPendingTierChange();
          await AuthService().syncSubscriptionToFirestore(
            tier: userManager.currentTier,
            productId: userManager.productId ?? purchase.productID,
            purchaseDate: userManager.purchaseDate,
          );
        }
        return;
      }

      final effectiveAt =
          userManager.estimatedExpiryAt ??
          DateTime.now().add(const Duration(days: 30));

      await userManager.setPendingTierChange(
        nextTier: UserTier.free,
        effectiveAt: effectiveAt,
      );

      await AuthService().syncPendingSubscriptionChangeToFirestore(
        nextTier: UserTier.free,
        nextProductId: userManager.productId ?? purchase.productID,
        effectiveAt: effectiveAt,
        reason: 'user_cancelled_in_play_$reason',
      );

      print(
        '[IAPService][CancelSync] cancellation reserved '
        'currentTier=${userManager.currentTier} -> free at=$effectiveAt',
      );
    } catch (e, stackTrace) {
      print('[IAPService][CancelSync] failed: $e');
      print(stackTrace);
    }
  }

  /// 특정 상품 정보 조회
  ProductDetails? getProduct(String productId) {
    try {
      return _products.firstWhere((p) => p.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// 특정 사이클/등급에 맞는 상품 정보 조회
  ProductDetails? getProductFor({
    required IAPSubscriptionCycle cycle,
    required IAPSubscriptionTier tier,
  }) {
    final productId = productIdFor(cycle: cycle, tier: tier);
    if (productId == null) return null;
    return getProduct(productId);
  }

  /// 특정 사이클에 해당하는 상품 목록 조회
  List<ProductDetails> getProductsForCycle(IAPSubscriptionCycle cycle) {
    final ids = _productIdMap[cycle]?.values.toSet() ?? {};
    return _products.where((p) => ids.contains(p.id)).toList();
  }

  /// 서비스 종료 (앱 종료 시 호출)
  void dispose() {
    _subscription.cancel();
    print('[IAPService] 서비스 종료');
  }

  IAPSubscriptionTier _tierFromProductId(String productId) {
    if (productId == standardMonthly || productId == standardAnnual) {
      return IAPSubscriptionTier.standard;
    }
    return IAPSubscriptionTier.premium;
  }

  IAPPlanChangeType _resolvePlanChangeType({
    required UserTier currentTier,
    required IAPSubscriptionTier targetTier,
  }) {
    final current = switch (currentTier) {
      UserTier.free => null,
      UserTier.standard => IAPSubscriptionTier.standard,
      UserTier.premium => IAPSubscriptionTier.premium,
    };

    if (current == null) return IAPPlanChangeType.newPurchase;
    if (current == targetTier) return IAPPlanChangeType.noChange;
    if (current == IAPSubscriptionTier.standard &&
        targetTier == IAPSubscriptionTier.premium) {
      return IAPPlanChangeType.upgrade;
    }
    return IAPPlanChangeType.downgrade;
  }

  Future<PurchaseParam> _buildAndroidPurchaseParam({
    required ProductDetails product,
    required String? currentProductId,
    required IAPPlanChangeType changeType,
  }) async {
    if (changeType == IAPPlanChangeType.newPurchase ||
        changeType == IAPPlanChangeType.noChange) {
      return GooglePlayPurchaseParam(productDetails: product);
    }

    final previous = await _findGooglePlayPurchaseDetails(currentProductId);
    if (previous == null) {
      print(
        '[IAPService][PlanChange] Android old purchase not found, fallback normal purchase',
      );
      return GooglePlayPurchaseParam(productDetails: product);
    }

    final replacementMode = changeType == IAPPlanChangeType.upgrade
        ? ReplacementMode.chargeProratedPrice
        : ReplacementMode.deferred;

    return GooglePlayPurchaseParam(
      productDetails: product,
      changeSubscriptionParam: ChangeSubscriptionParam(
        oldPurchaseDetails: previous,
        replacementMode: replacementMode,
      ),
    );
  }

  Future<GooglePlayPurchaseDetails?> _findGooglePlayPurchaseDetails(
    String? currentProductId,
  ) async {
    if (!Platform.isAndroid) return null;

    try {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();

      if (response.error != null) {
        print(
          '[IAPService][PlanChange] queryPastPurchases error: ${response.error}',
        );
      }

      for (final purchase in response.pastPurchases) {
        if (currentProductId != null &&
            purchase.productID == currentProductId) {
          return purchase;
        }
      }

      for (final purchase in response.pastPurchases) {
        if (_productIds.contains(purchase.productID)) {
          return purchase;
        }
      }
    } catch (e, stackTrace) {
      print('[IAPService][PlanChange] failed to load past purchases: $e');
      print(stackTrace);
    }
    return null;
  }

  Future<void> _reservePendingDowngrade({
    required IAPSubscriptionTier targetTier,
    required String targetProductId,
  }) async {
    final userManager = UserStatusManager();
    final authService = AuthService();

    final effectiveAt =
        userManager.estimatedExpiryAt ??
        DateTime.now().add(const Duration(days: 30));
    final nextTier = targetTier == IAPSubscriptionTier.premium
        ? UserTier.premium
        : UserTier.standard;

    await userManager.setPendingTierChange(
      nextTier: nextTier,
      effectiveAt: effectiveAt,
    );

    await authService.syncPendingSubscriptionChangeToFirestore(
      nextTier: nextTier,
      nextProductId: targetProductId,
      effectiveAt: effectiveAt,
      reason: 'user_requested_downgrade',
    );

    print(
      '[IAPService][PlanChange] downgrade scheduled '
      'nextTier=$nextTier effectiveAt=$effectiveAt targetProductId=$targetProductId',
    );
  }
}
