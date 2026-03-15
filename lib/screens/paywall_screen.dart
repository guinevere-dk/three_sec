import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:video_player/video_player.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../managers/user_status_manager.dart';
import '../services/iap_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldBright = Color(0xFFE8C95B);
  static const Color _goldDark = Color(0xFFB08D26);
  static const Color _glassNavy = Color(0xCC111A26);
  static const Color _glassBorder = Color(0x26FFFFFF);

  final IAPService _iapService = IAPService();
  VideoPlayerController? _videoController;
  bool _isPurchaseLoading = false;
  bool _isCatalogLoading = false;
  String? _catalogError;
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  // 0: Standard, 1: Premium
  int _selectedTierIndex = 1; // Default to Premium
  
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
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse('https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4'),
    )..initialize().then((_) {
        setState(() {});
        _videoController?.play();
        _videoController?.setLooping(true);
        _videoController?.setVolume(0); // Mute background
      }).catchError((e) {
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
    final Stream<List<PurchaseDetails>> purchaseUpdated = InAppPurchase.instance.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $error")));
         setState(() => _isPurchaseLoading = false);
       }
     });

    if (mounted) {
      setState(() {
        _products = _iapService.products;
        _isCatalogLoading = false;
        _catalogError = initialized
            ? null
            : '스토어 연결 또는 상품 조회에 실패했습니다.';
      });
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
               SnackBar(content: Text("Purchase Failed: ${purchaseDetails.error?.message ?? 'Unknown Error'}"))
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
    await _waitForLocalTierSync(purchaseDetails.productID);
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Subscription activated!")));
    setState(() => _isPurchaseLoading = false);
    Navigator.pop(context, true);
  }

  Future<void> _waitForLocalTierSync(String productId) async {
    final targetTier = _tierFromProductId(productId);
    final userStatus = UserStatusManager();
    final deadline = DateTime.now().add(const Duration(seconds: 2));

    while (DateTime.now().isBefore(deadline)) {
      await userStatus.initialize();
      if (userStatus.currentTier == targetTier &&
          userStatus.productId == productId) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  UserTier _tierFromProductId(String productId) {
    if (productId == IAPService.standardMonthly ||
        productId == IAPService.standardAnnual) {
      return UserTier.standard;
    }
    return UserTier.premium;
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(45),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _gold.withAlpha(110)),
                        ),
                        child: const Text(
                          '3S PREMIUM',
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
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
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
            )
          ]
       ),
       child: Column(
         mainAxisSize: MainAxisSize.min,
         children: [
           const Text(
             "Unlock Your Potential",
             style: TextStyle( color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
           ),
           const SizedBox(height: 20),
           
           // Toggle: Standard | Premium
           _buildTierToggle(),
           
           const SizedBox(height: 20),
           
           // Benefit List (Dynamic based on toggle)
           _buildBenefitList(),
           
           const SizedBox(height: 24),
           
            // Pricing Cards (Both Standard & Premium)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildPricingCard(
                    title: "Monthly",
                    price: _getPrice(_currentMonthlyProductId),
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
                    price: _getPrice(_currentAnnualProductId),
                    periodLabel: '/ year',
                    subtitle: _selectedTierIndex == 1 ? "Save 20%" : null,
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
                style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
              ),
              TextButton(
                onPressed: _initIAP,
                child: const Text('Retry'),
              ),
            ] else if (_isCatalogLoading) ...[
              const SizedBox(height: 12),
              Text(
                '가격 정보를 불러오는 중...',
                style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isPurchaseLoading
                    ? null
                    : () async {
                        final selectedProductId = _selectedProductId;
                        final ok = await _iapService.purchase(selectedProductId);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('구매 요청에 실패했습니다. 다시 시도해주세요.')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  shadowColor: _gold.withAlpha(80),
                ),
                child: Text(
                  _ctaLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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

  Widget _buildTierToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _buildToggleButton("Standard", 0),
          _buildToggleButton("Premium", 1),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String text, int index) {
    final isSelected = _selectedTierIndex == index;
    final isPremium = index == 1;
    final selectedBackground = isPremium
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_goldBright, _gold],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFEDEDED)],
          );

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTierIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12.5),
          decoration: BoxDecoration(
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            gradient: isSelected
                ? selectedBackground
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: isPremium ? _gold.withAlpha(60) : Colors.white.withAlpha(45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white.withAlpha(130),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitList() {
    final benefits = _selectedTierIndex == 0
        ? ["1080p Export", "Basic Filters", "Standard Support"]
        : ["4K Export", "All AI Filters", "Priority Support", "No Watermark"];

    return Column(
      children: benefits.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: _selectedTierIndex == 1 ? _gold : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              b,
              style: TextStyle(
                color: Colors.white.withAlpha(235),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String periodLabel,
    String? subtitle,
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
              ? [
                  BoxShadow(
                    color: _gold.withAlpha(35),
                    blurRadius: 16,
                  ),
                ]
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
                  child: const Text("BEST VALUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
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
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
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
                style: const TextStyle(
                  color: _goldDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildLegalLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegalTextButton('RESTORE'),
        Text('  •  ', style: TextStyle(color: Colors.white.withAlpha(70))),
        _buildLegalTextButton('TERMS'),
        Text('  •  ', style: TextStyle(color: Colors.white.withAlpha(70))),
        _buildLegalTextButton('PRIVACY'),
      ],
    );
  }

  Widget _buildLegalTextButton(String label) {
    return InkWell(
      onTap: () {},
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

  String _getPrice(String productId) {
    try {
      if (_products.isEmpty) return '---';
      final product = _products.firstWhere((p) => p.id == productId);
      return product.price;
    } catch (e) {
      return '---';
    }
  }

  String get _currentMonthlyProductId {
    return _selectedTierIndex == 1
        ? IAPService.premiumMonthly
        : IAPService.standardMonthly;
  }

  String get _currentAnnualProductId {
    return _selectedTierIndex == 1
        ? IAPService.premiumAnnual
        : IAPService.standardAnnual;
  }

  String get _selectedProductId {
    return _selectedPricingIndex == 0
        ? _currentAnnualProductId
        : _currentMonthlyProductId;
  }

  bool get _isDowngradeSelection {
    final currentTier = UserStatusManager().currentTier;
    return currentTier == UserTier.premium && _selectedTierIndex == 0;
  }

  String get _ctaLabel {
    if (_isDowngradeSelection) {
      return '다음 갱신일부터 Standard로 변경';
    }
    return _selectedTierIndex == 1 ? 'Premium으로 업그레이드' : 'Standard로 구독';
  }

  String get _planChangeHint {
    if (_isDowngradeSelection) {
      return '다운그레이드는 즉시 적용되지 않으며, 현재 결제 기간이 끝난 뒤 다음 갱신일부터 Standard로 전환됩니다.';
    }

    return '업그레이드는 즉시 적용되며, 남은 기간 금액은 스토어 정책에 따라 비례 정산됩니다.';
  }
}

