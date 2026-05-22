import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:video_player/video_player.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../managers/user_status_manager.dart';
import '../services/auth_service.dart';
import '../services/iap_service.dart';
import '../services/standard_annual_offer_service.dart';
import 'legal_document_screen.dart';
import 'login_screen.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldDark = Color(0xFFB08D26);
  static const Color _glassNavy = Color(0xCC111A26);
  static const Color _glassBorder = Color(0x26FFFFFF);

  final IAPService _iapService = IAPService();
  final AuthService _authService = AuthService();
  final StandardAnnualOfferService _standardAnnualOfferService =
      const StandardAnnualOfferService();
  VideoPlayerController? _videoController;
  bool _isPurchaseLoading = false;
  bool _isCatalogLoading = false;
  String? _catalogError;
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Selected Pricing Option
  // 0: Annual, 1: Monthly
  int _selectedPricingIndex = 0; // Default to Annual

  @override
  void initState() {
    super.initState();
    _initVideoBackground();
    _initIAP();
  }

  void _initVideoBackground() {
    // Placeholder video (Butterfly)
    _videoController =
        VideoPlayerController.networkUrl(
            Uri.parse(
              'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
            ),
          )
          ..initialize()
              .then((_) {
                setState(() {});
                _videoController?.play();
                _videoController?.setLooping(true);
                _videoController?.setVolume(0); // Mute background
              })
              .catchError((e) {
                debugPrint("Video initialization failed: $e");
              });
  }

  Future<void> _initIAP() async {
    if (mounted) {
      setState(() {
        _isCatalogLoading = true;
        _catalogError = null;
      });
    }

    final initialized = await _iapService.initialize();

    // Listen to purchase updates for UI feedback
    final Stream<List<PurchaseDetails>> purchaseUpdated =
        InAppPurchase.instance.purchaseStream;
    _subscription = purchaseUpdated.listen(
      (purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      },
      onDone: () {
        _subscription?.cancel();
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $error")));
          setState(() => _isPurchaseLoading = false);
        }
      },
    );

    if (mounted) {
      setState(() {
        _products = _iapService.products;
        _isCatalogLoading = false;
        _catalogError = initialized ? null : '스토어 연결 또는 상품 조회에 실패했습니다.';
      });
      _logAnnualOfferDiagnostics('catalog_loaded');
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _isPurchaseLoading = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Purchase Failed: ${purchaseDetails.error?.message ?? 'Unknown Error'}",
                ),
              ),
            );
            setState(() => _isPurchaseLoading = false);
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          _handlePurchaseCompleted(purchaseDetails);
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
          if (mounted) setState(() => _isPurchaseLoading = false);
        }
      }
    }
  }

  Future<void> _handlePurchaseCompleted(PurchaseDetails purchaseDetails) async {
    var synced = await _waitForLocalTierSync(purchaseDetails.productID);
    if (!synced) {
      await _iapService.refreshEntitlementsFromStore(
        reason: 'return_from_paywall',
      );
      synced = await _waitForLocalTierSync(purchaseDetails.productID);
    }
    if (synced && _authService.isAuthenticatedAccount) {
      final userStatus = UserStatusManager();
      await _authService.syncSubscriptionToFirestore(
        tier: userStatus.currentTier,
        productId: purchaseDetails.productID,
        purchaseDate: userStatus.purchaseDate,
      );
    }
    if (!mounted) return;

    setState(() => _isPurchaseLoading = false);
    if (synced) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Subscription activated!")));
      Navigator.pop(context, true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('구독 확인 중입니다. 잠시 후 구독 관리 화면에서 다시 확인해 주세요.')),
    );
  }

  Future<bool> _waitForLocalTierSync(String productId) async {
    final targetTier = IAPEntitlementPolicy.tierForProductId(productId);
    if (targetTier == null) {
      debugPrint('[Paywall] unsupported purchase productId=$productId');
      return false;
    }
    final userStatus = UserStatusManager();
    final deadline = DateTime.now().add(const Duration(seconds: 5));

    while (DateTime.now().isBefore(deadline)) {
      await userStatus.initialize();
      if (userStatus.currentTier == targetTier &&
          userStatus.productId == productId) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  Future<bool> _ensureAuthenticatedAccountForPaidAction() async {
    if (_authService.isAuthenticatedAccount) {
      return true;
    }

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Standard 구독은 로그인이 필요합니다'),
        content: const Text(
          '구독 권한을 계정에 안전하게 연결하기 위해 구매 전에 로그인해 주세요. '
          '게스트로 만든 영상과 프로젝트는 삭제되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에 하기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그인하고 계속하기'),
          ),
        ],
      ),
    );

    if (shouldLogin != true || !mounted) {
      return false;
    }

    if (_authService.isGuest) {
      await _authService.signOutGuest();
      if (!mounted) return false;
    }

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const LoginScreen(popOnSuccess: true, allowGuest: false),
      ),
    );

    if (!mounted) {
      return false;
    }

    return _authService.isAuthenticatedAccount;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Video Background
          if (_videoController != null && _videoController!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            Container(color: Colors.black), // Fallback
          // 2. Blur Overlay + Tone Layer
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xCC050B12),
                      Color(0xCC111A26),
                      Color(0xCC070D14),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -140,
            bottom: -40,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _gold.withAlpha(90),
                      _gold.withAlpha(10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Content
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(70),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(45),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _gold.withAlpha(110)),
                        ),
                        child: const Text(
                          'MOA STANDARD',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Main Content Card
                _buildGlassCard(),
              ],
            ),
          ),

          if (_isPurchaseLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _glassNavy,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _glassBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2432).withAlpha(230),
            const Color(0xFF0E1826).withAlpha(230),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(64),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "MOA Standard로 더 자유롭게 기록하세요",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Benefit List
          _buildBenefitList(),

          const SizedBox(height: 24),

          // Pricing Cards (Standard only)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 2,
                child: _buildPricingCard(
                  title: "Monthly",
                  price: _monthlyPriceText,
                  periodLabel: '/ month',
                  isHero: false,
                  isSelected: _selectedPricingIndex == 1,
                  onTap: () => setState(() => _selectedPricingIndex = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildPricingCard(
                  title: "Annual",
                  price: _annualPriceText,
                  periodLabel: '/ year',
                  subtitle: _annualSubtitleText,
                  detailText: _annualDetailText,
                  isHero: true,
                  isSelected: _selectedPricingIndex == 0,
                  onTap: () => setState(() => _selectedPricingIndex = 0),
                ),
              ),
            ],
          ),

          if (_catalogError != null) ...[
            const SizedBox(height: 12),
            Text(
              _catalogError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withAlpha(180),
                fontSize: 12,
              ),
            ),
            TextButton(onPressed: _initIAP, child: const Text('Retry')),
          ] else if (_isCatalogLoading) ...[
            const SizedBox(height: 12),
            Text(
              '가격 정보를 불러오는 중...',
              style: TextStyle(
                color: Colors.white.withAlpha(160),
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isPurchaseLoading || !_canStartSelectedPurchase
                  ? null
                  : () async {
                      if (!await _ensureAuthenticatedAccountForPaidAction()) {
                        return;
                      }
                      final purchaseRequest = _selectedPurchaseRequest;
                      if (purchaseRequest == null) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('가격 정보를 불러온 뒤 다시 시도해주세요.'),
                          ),
                        );
                        return;
                      }
                      _logPurchaseStartDiagnostics(purchaseRequest);
                      final ok = await _iapService.purchase(
                        purchaseRequest.productId,
                        offerToken: purchaseRequest.offerToken,
                        requireOfferToken: purchaseRequest.requireOfferToken,
                        purchaseContext: purchaseRequest.purchaseContext,
                      );
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('구매 요청에 실패했습니다. 다시 시도해주세요.'),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                shadowColor: _gold.withAlpha(80),
              ),
              child: Text(
                _ctaLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _planChangeHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withAlpha(170),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _buildLegalLinks(),
        ],
      ),
    );
  }

  Widget _buildBenefitList() {
    final benefits = ["50GB Cloud 백업", "1080p 내보내기", "편집 기능"];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: benefits
          .map(
            (benefit) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withAlpha(28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    benefit,
                    style: TextStyle(
                      color: Colors.white.withAlpha(235),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String periodLabel,
    String? subtitle,
    String? detailText,
    required bool isHero,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(isHero ? 16 : 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1A2432).withAlpha(240)
              : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _gold : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: _gold.withAlpha(35), blurRadius: 16)]
              : null,
        ),
        child: Column(
          children: [
            if (isHero) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  "BEST VALUE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withAlpha(isSelected ? 230 : 145),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? _gold : Colors.white24,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                color: Colors.white.withAlpha(isSelected ? 245 : 220),
                fontSize: isHero ? 20 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              periodLabel,
              style: TextStyle(
                color: Colors.white.withAlpha(isSelected ? 170 : 120),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _goldDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (detailText != null) ...[
              const SizedBox(height: 3),
              Text(
                detailText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(isSelected ? 170 : 120),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegalLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegalTextButton('TERMS', LegalDocumentType.terms),
        Text('  •  ', style: TextStyle(color: Colors.white.withAlpha(70))),
        _buildLegalTextButton('PRIVACY', LegalDocumentType.privacy),
      ],
    );
  }

  Widget _buildLegalTextButton(String label, LegalDocumentType type) {
    return InkWell(
      onTap: () async {
        if (!mounted) {
          return;
        }

        await openLegalDocument(context, type);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(110),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  String get _currentMonthlyProductId {
    return IAPService.standardMonthly;
  }

  ProductDetails? _findProduct(String productId) {
    for (final product in _products) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  StandardAnnualOfferViewModel get _annualOfferViewModel {
    return _standardAnnualOfferService.buildFromProductDetails(_products);
  }

  void _logAnnualOfferDiagnostics(String trigger) {
    final annualOffer = _annualOfferViewModel;
    final selectedPurchase = _selectedPurchaseRequest;
    debugPrint(
      '[Paywall][StandardAnnualOffer] '
      'trigger=$trigger '
      'annualProductFound=${annualOffer.annualProductFound} '
      'annualProductCount=${annualOffer.annualProductCount} '
      'androidOfferDetailsCount=${annualOffer.androidOfferDetailsCount} '
      'launchTagOfferFound=${annualOffer.launchTagOfferFound} '
      'selectedOfferTokenExists=${selectedPurchase?.offerToken != null} '
      'displayedAnnualBasePriceAvailable=${annualOffer.basePlanPriceText != null} '
      'displayedLaunchPriceAvailable=${annualOffer.launchOfferPriceText != null} '
      'canPurchase=${annualOffer.canPurchase} '
      'purchaseMode=${annualOffer.purchaseMode.name} '
      'diagnosticReason=${annualOffer.diagnosticReason}',
    );
  }

  void _logPurchaseStartDiagnostics(_PaywallPurchaseRequest purchaseRequest) {
    debugPrint(
      '[Paywall][StandardAnnualOffer] '
      'purchaseStarted=true '
      'productId=${purchaseRequest.productId} '
      'purchaseContext=${purchaseRequest.purchaseContext} '
      'purchaseStartedWithLaunchOffer=${purchaseRequest.isLaunchOfferPurchase} '
      'selectedOfferTokenExists=${purchaseRequest.offerToken != null} '
      'requireOfferToken=${purchaseRequest.requireOfferToken}',
    );
  }

  String get _monthlyPriceText {
    if (_isCatalogLoading) return '...';
    return _findProduct(_currentMonthlyProductId)?.price ?? '---';
  }

  String get _annualPriceText {
    if (_isCatalogLoading) return '...';
    final annualOffer = _annualOfferViewModel;
    return annualOffer.launchOfferPriceText ??
        annualOffer.basePlanPriceText ??
        '---';
  }

  String? get _annualSubtitleText {
    final annualOffer = _annualOfferViewModel;
    if (annualOffer.hasLaunchOffer) {
      return '첫해 선택';
    }
    if (annualOffer.purchaseMode ==
        StandardAnnualOfferPurchaseMode.regularAnnual) {
      return 'Best value';
    }
    return null;
  }

  String? get _annualDetailText {
    final annualOffer = _annualOfferViewModel;
    if (!annualOffer.hasLaunchOffer) return null;
    final basePlanPrice = annualOffer.basePlanPriceText;
    if (basePlanPrice == null) return null;
    return '이후 $basePlanPrice / year';
  }

  _PaywallPurchaseRequest? get _selectedPurchaseRequest {
    if (_isCatalogLoading || _catalogError != null) return null;
    if (_selectedPricingIndex == 1) {
      final product = _findProduct(_currentMonthlyProductId);
      if (product == null) return null;
      return const _PaywallPurchaseRequest(
        productId: IAPService.standardMonthly,
        purchaseContext: 'standard_monthly_regular',
      );
    }

    final annualOffer = _annualOfferViewModel;
    if (!annualOffer.canPurchase) return null;
    switch (annualOffer.purchaseMode) {
      case StandardAnnualOfferPurchaseMode.launchOffer:
        return _PaywallPurchaseRequest(
          productId: IAPService.standardAnnual,
          offerToken: annualOffer.launchOfferToken,
          requireOfferToken: true,
          purchaseContext: 'standard_annual_launch',
        );
      case StandardAnnualOfferPurchaseMode.regularAnnual:
        return _PaywallPurchaseRequest(
          productId: IAPService.standardAnnual,
          offerToken: annualOffer.regularAnnualOfferToken,
          purchaseContext: 'standard_annual_regular',
        );
      case StandardAnnualOfferPurchaseMode.unavailable:
        return null;
    }
  }

  bool get _canStartSelectedPurchase => _selectedPurchaseRequest != null;

  bool get _isDowngradeSelection {
    final currentTier = UserStatusManager().currentTier;
    return currentTier == UserTier.premium;
  }

  String get _ctaLabel {
    if (_isDowngradeSelection) {
      return '다음 갱신일부터 Standard로 변경';
    }
    return 'Standard로 구독';
  }

  String get _planChangeHint {
    if (_isDowngradeSelection) {
      return '다운그레이드는 즉시 적용되지 않으며, 현재 결제 기간이 끝난 뒤 다음 갱신일부터 Standard로 전환됩니다.';
    }

    return '구매 전 로그인한 계정에 Standard 구독 권한이 안전하게 연결됩니다.';
  }
}

class _PaywallPurchaseRequest {
  final String productId;
  final String? offerToken;
  final bool requireOfferToken;
  final String purchaseContext;

  const _PaywallPurchaseRequest({
    required this.productId,
    this.offerToken,
    this.requireOfferToken = false,
    required this.purchaseContext,
  });

  bool get isLaunchOfferPurchase => purchaseContext == 'standard_annual_launch';
}
