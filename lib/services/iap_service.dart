import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:http/http.dart' as http;
import '../managers/user_status_manager.dart';
import 'auth_service.dart';

class IapServerVerificationResult {
  const IapServerVerificationResult({
    required this.valid,
    required this.active,
    required this.productId,
    required this.platform,
    required this.status,
    required this.requestedTransactionDateMillis,
    required this.transactionId,
    this.acknowledged,
    this.consumed,
    this.expiryTimeMillis,
    this.errorCode,
    this.errorMessage,
    required this.recoverable,
  });

  final bool valid;
  final bool active;
  final String productId;
  final String platform;
  final String status;
  final int? expiryTimeMillis;
  final bool? acknowledged;
  final bool? consumed;
  final int requestedTransactionDateMillis;
  final String? transactionId;
  final String? errorCode;
  final String? errorMessage;
  final bool recoverable;
}

class IapVerificationException implements Exception {
  const IapVerificationException({
    required this.code,
    required this.message,
    this.recoverable = false,
  });

  final String code;
  final String message;
  final bool recoverable;

  @override
  String toString() => 'IapVerificationException(code=$code, message=$message)';
}

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
  static const String _socialExchangeUrl = String.fromEnvironment(
    'SOCIAL_AUTH_EXCHANGE_URL',
    defaultValue: '',
  );
  static const int _iapVerifyTimeoutSec = 12;

  final Set<String> _verifiedPurchaseKeySet = <String>{};
  final Set<String> _pendingVerificationKeySet = <String>{};
  final Map<String, IapServerVerificationResult> _latestVerificationResultByKey =
      <String, IapServerVerificationResult>{};
  final Map<String, Map<String, dynamic>> _pendingVerificationPayloadByKey =
      <String, Map<String, dynamic>>{};
  bool _isRetryingPendingVerification = false;

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
      final String orderId = _safePurchaseOrderId(purchase);
      print(
        '[IAPService] 구매 상태 업데이트: productId=${purchase.productID} orderId=$orderId status=${purchase.status}',
      );

      try {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            // 구매 대기 중 (사용자가 결제 진행 중)
            print(
              '[IAPService] 구매 진행 중: '
              'productId=${purchase.productID} orderId=$orderId',
            );
            break;

          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            // 구매 완료 또는 복원됨
            final verificationResult = await _verifyPurchase(purchase);

            if (verificationResult.valid) {
              // 구매 검증 결과 기반으로 상태 반영
              await _deliverProduct(
                purchase,
                verificationResult: verificationResult,
                orderId: orderId,
              );
              print(
                '[IAPService] ✓ 구매 완료 및 검증 적용: '
                'productId=${purchase.productID} orderId=$orderId',
              );
            } else {
              // 구매 검증 실패
              print(
                '[IAPService] ✗ 구매 검증 실패: '
                'productId=${purchase.productID} orderId=$orderId',
              );
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
            print(
              '[IAPService] ✗ 구매 실패: productId=${purchase.productID} orderId=$orderId '
              'code=$errorCode message=$errorMessage',
            );

            // 구매 처리 완료 표시
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
            break;

          case PurchaseStatus.canceled:
            // 사용자가 구매 취소
            print(
              '[IAPService] 구매 취소: productId=${purchase.productID} orderId=$orderId',
            );
            break;
        }
      } catch (e, stackTrace) {
        final String orderId = _safePurchaseOrderId(purchase);
        print(
          '[IAPService] 구매 처리 중 예외: productId=${purchase.productID} '
          'orderId=$orderId code=UNHANDLED error=$e',
        );
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
  Future<IapServerVerificationResult> _verifyPurchase(
    PurchaseDetails purchase,
  ) async {
    try {
      // 1. 기본 검증: productID가 유효한지 확인
      if (!_productIds.contains(purchase.productID)) {
        final orderId = _safePurchaseOrderId(purchase);
        print(
          '[IAPService] 검증 실패: 유효하지 않은 상품 ID '
          'productId=${purchase.productID} orderId=$orderId',
        );
        return IapServerVerificationResult(
          valid: false,
          active: false,
          productId: purchase.productID,
          platform: Platform.isAndroid ? 'android' : 'ios',
          status: 'INVALID_PRODUCT',
          requestedTransactionDateMillis:
              int.tryParse(purchase.transactionDate ?? '') ??
                  DateTime.now().millisecondsSinceEpoch,
          transactionId: purchase.purchaseID,
          errorCode: 'INVALID_PRODUCT',
          errorMessage: '지원되지 않는 상품 ID입니다.',
          recoverable: false,
        );
      }

      final payload = _buildVerificationPayload(purchase);
      final key = _buildPurchaseVerificationKey(payload);
      final orderId = payload['orderId'] ?? payload['purchaseId'];

      print(
        '[IAPService][IAPVerify] 검증 시작: '
        'productId=${purchase.productID} orderId=$orderId '
        'platform=${payload['platform']} requestStatus=${payload['status']} ',
      );

      final missingFields = _validateRequiredVerificationFields(payload);
      if (missingFields.isNotEmpty) {
        print(
          '[IAPService][IAPVerify] 필수값 검증 실패: productId=${purchase.productID} '
          'orderId=$orderId missing=$missingFields',
        );
        _pendingVerificationKeySet.remove(key);
        _pendingVerificationPayloadByKey.remove(key);
        return IapServerVerificationResult(
          valid: false,
          active: false,
          productId: '${payload['productId'] ?? ''}',
          platform: '${payload['platform'] ?? ''}',
          status: 'INVALID_REQUEST',
          requestedTransactionDateMillis:
              _coerceInt(payload['transactionDateMillis']) ??
                  DateTime.now().millisecondsSinceEpoch,
          transactionId: '${payload['purchaseId'] ?? payload['orderId'] ?? ''}',
          errorCode: 'INVALID_REQUEST',
          errorMessage: '필수 검증 항목이 누락되었습니다: ${missingFields.join(',')}',
          recoverable: false,
        );
      }

      final result = await _safeVerifyWithServer(payload);
      _latestVerificationResultByKey[key] = result;

      if (!result.valid) {
        print(
          '[IAPService][IAPVerify] 서버 검증 실패: '
          'key=$key productId=${purchase.productID} status=${result.status} '
          'errorCode=${result.errorCode} errorMessage=${result.errorMessage} '
          'transactionId=${result.transactionId}',
        );

        if (result.recoverable) {
          _pendingVerificationKeySet.add(key);
          _pendingVerificationPayloadByKey[key] = payload;
        } else {
          _pendingVerificationKeySet.remove(key);
          _pendingVerificationPayloadByKey.remove(key);
        }
        return result;
      }

      if (!result.active) {
        print(
          '[IAPService][IAPVerify] 정산 상태 비활성: '
          'key=$key productId=${purchase.productID} status=${result.status} '
          'orderId=$orderId '
          'transactionId=${result.transactionId} '
          'expiry=${result.expiryTimeMillis}',
        );

        if (_isTerminalInactiveStatus(result.status.toUpperCase())) {
          _pendingVerificationKeySet.remove(key);
          _pendingVerificationPayloadByKey.remove(key);
        } else {
          _pendingVerificationKeySet.add(key);
          _pendingVerificationPayloadByKey[key] = payload;
        }

        return result;
      }

      print(
        '[IAPService][IAPVerify] 서버 검증 성공: '
        'key=$key productId=${purchase.productID} orderId=$orderId '
        'status=${result.status} ack=${result.acknowledged} '
        'consumed=${result.consumed} expiry=${result.expiryTimeMillis} '
        'transactionId=${result.transactionId}',
      );

      _verifiedPurchaseKeySet.add(key);
      _pendingVerificationKeySet.remove(key);
      _pendingVerificationPayloadByKey.remove(key);
      print(
        '[IAPService] 구매 검증 성공: productId=${purchase.productID} orderId=$orderId',
      );
      return result;
    } catch (e, stackTrace) {
      final String orderId = _safePurchaseOrderId(purchase);
      if (e is IapVerificationException) {
        final fallbackPayload = _buildVerificationPayload(purchase);
        final key = _buildPurchaseVerificationKey(fallbackPayload);

        if (e.recoverable) {
          print(
            '[IAPService][IAPVerify] 네트워크/일시 장애: '
            'productId=${purchase.productID} orderId=$orderId '
            'code=${e.code} message=${e.message}',
          );
          _pendingVerificationKeySet.add(key);
          _pendingVerificationPayloadByKey[key] = fallbackPayload;
        } else {
          print(
            '[IAPService][IAPVerify] 검증 예외(재시도 제외): '
            'productId=${purchase.productID} orderId=$orderId '
            'code=${e.code} message=${e.message}',
          );
          _pendingVerificationKeySet.remove(key);
          _pendingVerificationPayloadByKey.remove(key);
        }
        print(stackTrace);
        return IapServerVerificationResult(
          valid: false,
          active: false,
          productId: '${fallbackPayload['productId'] ?? purchase.productID}',
          platform: '${fallbackPayload['platform'] ?? 'unknown'}',
          status: '${fallbackPayload['status'] ?? 'UNHANDLED'}',
          requestedTransactionDateMillis:
              _coerceInt(fallbackPayload['transactionDateMillis']) ??
                  DateTime.now().millisecondsSinceEpoch,
          transactionId:
              '${fallbackPayload['purchaseId'] ?? fallbackPayload['orderId'] ?? ''}',
          errorCode: e.code,
          errorMessage: e.message,
          recoverable: e.recoverable,
        );
      }

      print(
        '[IAPService] 구매 검증 중 예외: '
        'productId=${purchase.productID} orderId=$orderId code=UNHANDLED error=$e',
      );
      print(stackTrace);
      return IapServerVerificationResult(
        valid: false,
        active: false,
        productId: purchase.productID,
        platform: Platform.isAndroid ? 'android' : 'ios',
        status: 'UNHANDLED_EXCEPTION',
        requestedTransactionDateMillis:
            int.tryParse(purchase.transactionDate ?? '') ??
                DateTime.now().millisecondsSinceEpoch,
        transactionId: purchase.purchaseID,
        errorCode: 'UNHANDLED_EXCEPTION',
        errorMessage: e.toString(),
        recoverable: false,
      );
    }
  }

  String _safePurchaseOrderId(PurchaseDetails purchase) {
    try {
      if (Platform.isAndroid) {
        final androidPurchase = purchase as GooglePlayPurchaseDetails;
        final orderId = androidPurchase.billingClientPurchase.orderId;
        final purchaseId = androidPurchase.purchaseID;
        final transactionDate = androidPurchase.transactionDate;

        print(
          '[IAPService][OrderId] android 후보 상태: '
          'orderIdNull=${orderId == null} orderIdEmpty=${orderId?.isEmpty ?? true} '
          'purchaseIdNull=${purchaseId == null} purchaseIdEmpty=${purchaseId?.isEmpty ?? true} '
          'transactionDateNull=${transactionDate == null} '
          'transactionDateEmpty=${transactionDate?.isEmpty ?? true}',
        );

        if (orderId != null && orderId.isNotEmpty) {
          return orderId;
        }

        if (purchaseId != null && purchaseId.isNotEmpty) {
          return purchaseId;
        }

        if (transactionDate != null && transactionDate.isNotEmpty) {
          return transactionDate;
        }

        return 'unknown';
      }

      final purchaseId = purchase.purchaseID;
      final transactionDate = purchase.transactionDate;

      print(
        '[IAPService][OrderId] ios/other 후보 상태: '
        'purchaseIdNull=${purchaseId == null} purchaseIdEmpty=${purchaseId?.isEmpty ?? true} '
        'transactionDateNull=${transactionDate == null} '
        'transactionDateEmpty=${transactionDate?.isEmpty ?? true}',
      );

      if (purchaseId != null && purchaseId.isNotEmpty) {
        return purchaseId;
      }

      if (transactionDate != null && transactionDate.isNotEmpty) {
        return transactionDate;
      }

      return 'unknown';
    } catch (_) {
      final purchaseId = purchase.purchaseID;
      final transactionDate = purchase.transactionDate;

      print(
        '[IAPService][OrderId] fallback 후보 상태: '
        'purchaseIdNull=${purchaseId == null} purchaseIdEmpty=${purchaseId?.isEmpty ?? true} '
        'transactionDateNull=${transactionDate == null} '
        'transactionDateEmpty=${transactionDate?.isEmpty ?? true}',
      );

      if (purchaseId != null && purchaseId.isNotEmpty) {
        return purchaseId;
      }

      if (transactionDate != null && transactionDate.isNotEmpty) {
        return transactionDate;
      }

      return purchase.productID;
    }
  }

  Map<String, dynamic> _buildVerificationPayload(PurchaseDetails purchase) {
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : 'unknown';

    final transactionDateMillis = int.tryParse(purchase.transactionDate ?? '');

    if (Platform.isAndroid) {
      final androidPurchase = purchase as GooglePlayPurchaseDetails;
      return {
        'platform': platform,
        'productId': purchase.productID,
        'packageName': androidPurchase.billingClientPurchase.packageName,
        'purchaseToken': androidPurchase.billingClientPurchase.purchaseToken,
        'orderId': androidPurchase.billingClientPurchase.orderId,
        'purchaseId': purchase.purchaseID,
        'status': _toStatusString(purchase),
        'acknowledged': androidPurchase.billingClientPurchase.isAcknowledged,
        'consumed': false,
        'autoRenewing': androidPurchase.billingClientPurchase.isAutoRenewing,
        'transactionDateMillis': transactionDateMillis,
        'transactionDate': purchase.transactionDate,
        'receipt': androidPurchase.verificationData.serverVerificationData,
      };
    }

    final iosPurchase = purchase as AppStorePurchaseDetails;
    return {
      'platform': platform,
      'productId': purchase.productID,
      'purchaseId': iosPurchase.purchaseID,
      'orderId': iosPurchase.transactionDate,
      'transactionDateMillis': transactionDateMillis,
      'transactionDate': iosPurchase.transactionDate,
      'receipt': iosPurchase.verificationData.serverVerificationData,
      'status': _toStatusString(purchase),
      'acknowledged': null,
      'consumed': null,
    };
  }

  String _buildPurchaseVerificationKey(Map<String, dynamic> payload) {
    final productId = payload['productId'] ?? '';
    final orderId = payload['orderId'] ?? payload['purchaseId'] ?? '';
    return '$productId|$orderId';
  }

  List<String> _validateRequiredVerificationFields(Map<String, dynamic> payload) {
    final List<String> missing = <String>[];

    if (!(payload['platform'] == 'android' || payload['platform'] == 'ios')) {
      missing.add('platform');
    }

    if ((payload['productId'] as String?)?.isEmpty ?? true) {
      missing.add('productId');
    }

    final int? transactionDateMillis = payload['transactionDateMillis'] is int
        ? payload['transactionDateMillis'] as int
        : int.tryParse('${payload['transactionDate'] ?? ''}');
    if (transactionDateMillis == null || transactionDateMillis <= 0) {
      missing.add('transactionDateMillis');
    }

    if (payload['platform'] == 'android') {
      if ((payload['purchaseToken'] as String?)?.isEmpty ?? true) {
        missing.add('purchaseToken');
      }
      if ((payload['packageName'] as String?)?.isEmpty ?? true) {
        missing.add('packageName');
      }
    }

    if (payload['platform'] == 'ios') {
      if ((payload['receipt'] as String?)?.isEmpty ?? true) {
        missing.add('receipt');
      }
    }

    return missing;
  }

  Future<IapServerVerificationResult> _verifyWithServer(
    Map<String, dynamic> payload,
  ) async {
    final endpoint = await _resolveIapVerifyUri();
    final verificationKey = _buildPurchaseVerificationKey(payload);
    final requestedProductId = payload['productId'];
    final orderId = payload['orderId'] ?? payload['purchaseId'];

    print(
      '[IAPService][IAPVerify] 요청 시작: '
      'key=$verificationKey platform=${payload['platform']} '
      'productId=$requestedProductId orderId=$orderId ',
    );

    final response = await http
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: _iapVerifyTimeoutSec));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      print(
        '[IAPService][IAPVerify] 응답 상태 오류: key=$verificationKey '
        'productId=$requestedProductId orderId=$orderId code=HTTP_${response.statusCode} '
        'reason=${response.reasonPhrase}',
      );
      throw IapVerificationException(
        code: 'HTTP_${response.statusCode}',
        message:
            '영수증 검증 API 응답 실패: ${response.statusCode} ${response.reasonPhrase}',
        recoverable: true,
      );
    }

    final Object decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error, stackTrace) {
      print(
        '[IAPService][IAPVerify] JSON 파싱 실패: '
        'key=$verificationKey productId=$requestedProductId orderId=$orderId '
        'message=$error',
      );
      print(stackTrace);
      throw IapVerificationException(
        code: 'INVALID_RESPONSE_FORMAT',
        message: '영수증 검증 응답 JSON 파싱에 실패했습니다.',
        recoverable: false,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      print(
        '[IAPService][IAPVerify] 응답 형식 오류: '
        'key=$verificationKey productId=$requestedProductId orderId=$orderId '
        'code=INVALID_RESPONSE_FORMAT',
      );
      throw const IapVerificationException(
        code: 'INVALID_RESPONSE_FORMAT',
        message: '영수증 검증 응답이 올바른 JSON 형식이 아닙니다.',
        recoverable: false,
      );
    }

    if (decoded['success'] != true) {
      final error = decoded['error'];
      final errorCode =
          error is Map<String, dynamic> && error['code'] != null
              ? '${error['code']}'
              : 'VERIFICATION_REJECTED';
      final errorMessage =
          error is Map<String, dynamic> && error['message'] != null
              ? '${error['message']}'
              : '영수증 검증이 거부되었습니다.';
      final Object? errorDetails = error is Map<String, dynamic> ? error['details'] : null;
      final recoverable = _coerceBool(
        error is Map<String, dynamic>
            ? (error['recoverable'] ??
                (errorDetails is Map<String, dynamic>
                    ? errorDetails['recoverable']
                    : null))
            : null,
      );
      print(
        '[IAPService][IAPVerify] 서버 응답 거부: key=$verificationKey '
        'productId=$requestedProductId orderId=$orderId code=$errorCode '
        'message=$errorMessage recoverable=$recoverable',
      );
      return IapServerVerificationResult(
        valid: false,
        active: false,
        productId: '$requestedProductId',
        platform: '${payload['platform']}',
        status: '${payload['status']}',
        requestedTransactionDateMillis:
            _coerceInt(payload['transactionDateMillis']) ??
                DateTime.now().millisecondsSinceEpoch,
        transactionId: payload['purchaseId'] ?? payload['orderId'],
        errorCode: errorCode,
        errorMessage: errorMessage,
        recoverable: recoverable ?? false,
      );
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      print(
        '[IAPService][IAPVerify] data 누락/형식 오류: '
        'key=$verificationKey productId=$requestedProductId orderId=$orderId '
        'code=INVALID_RESPONSE_FORMAT',
      );
      throw const IapVerificationException(
        code: 'INVALID_RESPONSE_FORMAT',
        message: '검증 응답에 data가 없습니다.',
        recoverable: false,
      );
    }

    final responseProductId =
        data['productId']?.toString() ?? '${payload['productId']}';
    final platform = data['platform']?.toString() ?? '${payload['platform']}';
    final status = data['status']?.toString() ?? 'UNKNOWN';
    final bool valid = data['valid'] == true;
    final bool active = data['active'] == true;
    final bool? serverRecoverable = _coerceBool(data['recoverable']);

    return IapServerVerificationResult(
      valid: valid,
      active: active,
      productId: responseProductId,
      platform: platform,
      status: status,
      acknowledged:
          data['acknowledged'] is bool ? data['acknowledged'] as bool : null,
      consumed: data['consumed'] is bool ? data['consumed'] as bool : null,
      expiryTimeMillis: _coerceInt(data['expiryTimeMillis']),
      transactionId: (data['transactionId'] ?? payload['purchaseId'])?.toString(),
      requestedTransactionDateMillis:
          _coerceInt(payload['transactionDateMillis']) ?? DateTime.now().millisecondsSinceEpoch,
      errorCode: data['errorCode']?.toString(),
      errorMessage: data['errorMessage']?.toString(),
      recoverable: serverRecoverable ?? false,
    );
  }

  Future<Uri> _resolveIapVerifyUri() async {
    if (_socialExchangeUrl.isEmpty) {
      throw const IapVerificationException(
        code: 'MISSING_IAP_VERIFY_URL',
        message: 'SOCIAL_AUTH_EXCHANGE_URL 환경변수가 비어 있습니다.',
        recoverable: false,
      );
    }

    try {
      final exchangeUri = Uri.parse(_socialExchangeUrl);
      final normalizedPath =
          (exchangeUri.path.isEmpty ? '' : exchangeUri.path).replaceAll(
            RegExp(r'//+'),
            '/',
          );
      final trimmedPath =
          normalizedPath.endsWith('/') && normalizedPath.length > 1
              ? normalizedPath.substring(0, normalizedPath.length - 1)
              : normalizedPath;

      if (normalizedPath.endsWith('/exchange')) {
        final updatedPath =
          '${normalizedPath.substring(0, normalizedPath.length - '/exchange'.length)}/iap/verify';
        return exchangeUri.replace(path: updatedPath);
      }

      if (trimmedPath.isEmpty || trimmedPath == '/') {
        return exchangeUri.replace(path: '/iap/verify');
      }

      return exchangeUri.replace(
        path:
            trimmedPath.isEmpty || trimmedPath == '/'
                ? '/iap/verify'
                : '$trimmedPath/iap/verify',
      );
    } catch (error) {
      throw IapVerificationException(
        code: 'INVALID_IAP_VERIFY_URL',
        message: 'SOCIAL_AUTH_EXCHANGE_URL 형식이 잘못되었습니다: ${error.toString()}',
        recoverable: false,
      );
    }
  }

  Future<IapServerVerificationResult> _safeVerifyWithServer(
    Map<String, dynamic> payload,
  ) async {
    final productId = payload['productId'];
    final orderId = payload['orderId'] ?? payload['purchaseId'];
    try {
      return await _verifyWithServer(payload);
    } on SocketException catch (error, stackTrace) {
      print(
        '[IAPService][IAPVerify] 소켓 오류: '
        'key=${_buildPurchaseVerificationKey(payload)} '
        'productId=$productId orderId=$orderId '
        'code=IAP_VERIFY_NETWORK_ERROR message=${error.message}',
      );
      print(stackTrace);
      throw IapVerificationException(
        code: 'IAP_VERIFY_NETWORK_ERROR',
        message: '영수증 검증 API 네트워크 오류',
        recoverable: true,
      );
    } on TimeoutException catch (error, stackTrace) {
      print(
        '[IAPService][IAPVerify] 타임아웃: '
        'key=${_buildPurchaseVerificationKey(payload)} '
        'productId=$productId orderId=$orderId '
        'code=IAP_VERIFY_TIMEOUT message=${error.message}',
      );
      print(stackTrace);
      throw const IapVerificationException(
        code: 'IAP_VERIFY_TIMEOUT',
        message: '영수증 검증 응답 지연',
        recoverable: true,
      );
    } on FormatException catch (error, stackTrace) {
      print(
        '[IAPService][IAPVerify] JSON 형식 오류: '
        'key=${_buildPurchaseVerificationKey(payload)} '
        'productId=$productId orderId=$orderId '
        'code=IAP_VERIFY_RESPONSE_FORMAT_ERROR '
        'message=${error.message}',
      );
      print(stackTrace);
      throw IapVerificationException(
        code: 'IAP_VERIFY_RESPONSE_FORMAT_ERROR',
        message: '영수증 검증 응답 형식 오류',
      );
    } catch (error, stackTrace) {
      print(
        '[IAPService][IAPVerify] 알 수 없는 검증 예외: '
        'key=${_buildPurchaseVerificationKey(payload)} '
        'productId=$productId orderId=$orderId '
        'code=IAP_VERIFY_ERROR message=$error',
      );
      print(stackTrace);
      throw IapVerificationException(
        code: 'IAP_VERIFY_ERROR',
        message: '영수증 검증 중 알 수 없는 오류',
        recoverable: false,
      );
    }
  }

  String _toStatusString(PurchaseDetails purchase) {
    return '${purchase.status}'.replaceFirst('PurchaseStatus.', '').toUpperCase();
  }

  int? _coerceInt(dynamic raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  bool? _coerceBool(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    if (raw is num) {
      if (raw == 1) return true;
      if (raw == 0) return false;
    }
    return null;
  }

  /// 구매한 상품 제공 (등급 업데이트)
  Future<void> _deliverProduct(
    PurchaseDetails purchase, {
    IapServerVerificationResult? verificationResult,
    String? orderId,
  }) async {
    try {
      final transactionDateMillis =
          verificationResult?.requestedTransactionDateMillis ??
              int.tryParse(purchase.transactionDate ?? '0') ??
                  DateTime.now().millisecondsSinceEpoch;
      await _applyVerifiedPurchaseFromResult(
        productId: purchase.productID,
        verificationResult: verificationResult,
        transactionDateMillis: transactionDateMillis,
        orderId: orderId,
      );
    } catch (e, stackTrace) {
      print('[IAPService] 상품 제공 중 예외: $e');
      print(stackTrace);
    }
  }

  Future<void> _applyVerifiedPurchaseFromResult({
    required String productId,
    required IapServerVerificationResult? verificationResult,
    required int transactionDateMillis,
    String? orderId,
  }) async {
    if (verificationResult == null) {
      print(
        '[IAPService][Deliver] verificationResult 미확보. skip. '
        'productId=$productId orderId=${orderId ?? 'unknown'}',
      );
      return;
    }

    final userManager = UserStatusManager();

    if (!verificationResult.valid) {
      print(
        '[IAPService][Deliver] 검증 실패로 반영 스킵: '
        'productId=$productId orderId=${orderId ?? 'unknown'} '
        'errorCode=${verificationResult.errorCode} '
        'errorMessage=${verificationResult.errorMessage}',
      );
      return;
    }

    final status = verificationResult.status.toUpperCase();
    if (!verificationResult.active) {
      final previousProductId = userManager.productId;

      if (_isTerminalInactiveStatus(status)) {
        final shouldDowngrade =
            previousProductId == null || previousProductId == productId;
        if (shouldDowngrade) {
          await _applyInactiveSubscriptionToFree(
            productId: productId,
            orderId: orderId,
            status: status,
          );
          return;
        }

        print(
          '[IAPService][Deliver] 비활성 상태이지만 다른 상품 보류: '
          'productId=$productId orderId=${orderId ?? 'unknown'} '
          'status=$status currentProductId=$previousProductId',
        );
        return;
      }

      print(
        '[IAPService][Deliver] 비활성 상태(재시도 대상): '
        'productId=$productId orderId=${orderId ?? 'unknown'} '
        'status=$status',
      );
      return;
    }

    final currentPlanChangeType = _resolvePlanChangeType(
      currentTier: userManager.currentTier,
      targetTier: _tierFromProductId(productId),
    );

    // Google Play deferred 다운그레이드의 경우
    // 현재 entitlement를 유지하고 예약 정보만 유지/갱신한다.
    if (currentPlanChangeType == IAPPlanChangeType.downgrade) {
      await _reservePendingDowngrade(
        targetTier: _tierFromProductId(productId),
        targetProductId: productId,
      );
      print(
        '[IAPService][PlanChange] deferred downgrade purchase delivered '
        '-> keep current tier, preserve pending change',
      );
      return;
    }

    await _applyActiveSubscriptionToUserStatus(
      productId: productId,
      status: status,
      transactionDateMillis: transactionDateMillis,
    );
  }

  Future<void> _applyInactiveSubscriptionToFree({
    required String productId,
    String? orderId,
    required String status,
  }) async {
    final userManager = UserStatusManager();
    await userManager.resetToFree();
    await AuthService().syncFreeTierToFirestore(
      reason: 'iap_inactive_${status.toLowerCase()}',
    );
    print(
      '[IAPService][Deliver] 구독 비활성으로 free 전환: '
      'productId=$productId orderId=${orderId ?? 'unknown'} status=$status',
    );
  }

  Future<void> _applyActiveSubscriptionToUserStatus({
    required String productId,
    required String status,
    required int transactionDateMillis,
  }) async {
    final userManager = UserStatusManager();

    UserTier tier;
    if (productId == standardMonthly || productId == standardAnnual) {
      tier = UserTier.standard;
    } else if (productId == premiumMonthly || productId == premiumAnnual) {
      tier = UserTier.premium;
    } else {
      print('[IAPService] 알 수 없는 상품 ID (기본 처리): $productId');
      tier = UserTier.premium;
    }

    final purchaseDateTime = DateTime.fromMillisecondsSinceEpoch(
      transactionDateMillis > 0
          ? transactionDateMillis
          : DateTime.now().millisecondsSinceEpoch,
    );

    final success = await userManager.setTier(
      tier,
      productId: productId,
      purchaseDate: purchaseDateTime,
    );

    if (success) {
      print('[IAPService] ✓ 사용자 등급 업데이트 완료: $tier');

      await userManager.clearPendingTierChange();

      final authService = AuthService();
      await authService.syncSubscriptionToFirestore(
        tier: tier,
        productId: productId,
        purchaseDate: purchaseDateTime,
      );
    } else {
      print('[IAPService] ✗ 사용자 등급 업데이트 실패');
    }
  }

  bool _isTerminalInactiveStatus(String status) {
    const terminal = {
      'EXPIRED',
      'CANCELLED',
      'REVOKED',
      'REFUNDED',
      'CHARGEBACK',
      'FRAUD',
    };
    return terminal.contains(status);
  }

  Future<void> _retryPendingVerification({String source = 'restore'}) async {
    if (_isRetryingPendingVerification) {
      print('[IAPService][IAPVerifyRetry] already running');
      return;
    }

    if (_pendingVerificationKeySet.isEmpty) {
      print('[IAPService][IAPVerifyRetry] no pending items | source=$source');
      return;
    }

    _isRetryingPendingVerification = true;

    try {
      final candidateKeys = List<String>.from(_pendingVerificationKeySet);
      print(
        '[IAPService][IAPVerifyRetry] 시작: source=$source count=${candidateKeys.length}',
      );

      for (final key in candidateKeys) {
        final payload = _pendingVerificationPayloadByKey[key];
        if (payload == null) {
          _pendingVerificationKeySet.remove(key);
          continue;
        }

        final productId = '${payload['productId'] ?? 'unknown'}';
        final orderId = '${payload['orderId'] ?? payload['purchaseId'] ?? 'unknown'}';

        print(
          '[IAPService][IAPVerifyRetry] 재검증 시작: '
          'source=$source key=$key productId=$productId orderId=$orderId',
        );

        try {
          final result = await _safeVerifyWithServer(payload);
          _latestVerificationResultByKey[key] = result;

          if (result.recoverable && (!result.valid || !result.active)) {
            _pendingVerificationKeySet.add(key);
            _pendingVerificationPayloadByKey[key] = payload;
          } else if (!result.valid || !result.active) {
            if (!result.valid) {
              print(
                '[IAPService][IAPVerifyRetry] 검증 실패: '
                'key=$key productId=$productId orderId=$orderId '
                'code=${result.errorCode} message=${result.errorMessage}',
              );
            }
            _pendingVerificationKeySet.remove(key);
            _pendingVerificationPayloadByKey.remove(key);
          } else {
            _pendingVerificationKeySet.remove(key);
            _pendingVerificationPayloadByKey.remove(key);
            _verifiedPurchaseKeySet.add(key);
            final resolvedProductId =
                (result.productId.isNotEmpty ? result.productId : productId)
                    .toString();
            await _applyVerifiedPurchaseFromResult(
              productId: resolvedProductId,
              verificationResult: result,
              transactionDateMillis: result.requestedTransactionDateMillis,
              orderId: orderId,
            );
          }

          print(
            '[IAPService][IAPVerifyRetry] 재검증 결과: '
            'key=$key productId=$productId orderId=$orderId '
            'status=${result.status} valid=${result.valid} '
            'active=${result.active} recoverable=${result.recoverable}',
          );
        } on IapVerificationException catch (error, stackTrace) {
          print(
            '[IAPService][IAPVerifyRetry] 예외: '
            'source=$source key=$key productId=$productId orderId=$orderId '
            'code=${error.code} message=${error.message}',
          );
          print(stackTrace);

          if (!error.recoverable) {
            _pendingVerificationKeySet.remove(key);
            _pendingVerificationPayloadByKey.remove(key);
          }
        } catch (error, stackTrace) {
          print(
            '[IAPService][IAPVerifyRetry] 알 수 없는 예외: '
            'source=$source key=$key productId=$productId orderId=$orderId '
            'error=$error',
          );
          print(stackTrace);
          _pendingVerificationKeySet.remove(key);
          _pendingVerificationPayloadByKey.remove(key);
        }
      }
    } finally {
      _isRetryingPendingVerification = false;
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
      await _retryRestoreVerificationFromStore(source: 'restore');
      await _retryPendingVerification(source: 'restore');
      // 복원된 구매는 _onPurchaseUpdate에서 자동 처리됨
      print('[IAPService] 구매 복원 요청 완료');
      return true;
    } catch (e, stackTrace) {
      print('[IAPService] 구매 복원 실패: $e');
      print(stackTrace);
      return false;
    }
  }

  Future<void> _retryRestoreVerificationFromStore({String source = 'restore'}) async {
    if (!Platform.isAndroid) {
      print('[IAPService][IAPRestoreVerify] skip: unsupported platform source=$source');
      return;
    }

    try {
      final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();

      if (response.error != null) {
        print(
          '[IAPService][IAPRestoreVerify] queryPastPurchases error: ${response.error}',
        );
      }

      final pastPurchases = response.pastPurchases
          .where((purchase) => _productIds.contains(purchase.productID))
          .toList();

      if (pastPurchases.isEmpty) {
        print('[IAPService][IAPRestoreVerify] no matching past purchase found');
        return;
      }

      print(
        '[IAPService][IAPRestoreVerify] start: source=$source count=${pastPurchases.length}',
      );

      for (final purchase in pastPurchases) {
        final orderId = _safePurchaseOrderId(purchase);
        print(
          '[IAPService][IAPRestoreVerify] verify start: '
          'productId=${purchase.productID} orderId=$orderId',
        );

        final result = await _verifyPurchase(purchase);

        if (!result.valid) {
          print(
            '[IAPService][IAPRestoreVerify] verify failed: '
            'productId=${purchase.productID} orderId=$orderId '
            'status=${result.status} code=${result.errorCode}',
          );
          continue;
        }

        await _deliverProduct(
          purchase,
          verificationResult: result,
          orderId: orderId,
        );

        print(
          '[IAPService][IAPRestoreVerify] verify applied: '
          'productId=${purchase.productID} orderId=$orderId',
        );
      }
    } catch (error, stackTrace) {
      print('[IAPService][IAPRestoreVerify] failed: $error');
      print(stackTrace);
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
