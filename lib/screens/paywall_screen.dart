import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/iap_service.dart';

/// 페이월(결제) 화면 - 억만장자의 설계
/// 
/// 단일 화면 구조:
/// - Monthly/Annual 슬라이드 토글 (기본값: Annual)
/// - Standard vs Premium 대조 카드 (나란히 배치)
/// - Annual 모드: 할인액 강조 ("$20 Save")
/// - Premium 강조: "Best Choice" 대형 뱃지
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final IAPService _iapService = IAPService();
  bool _isLoading = false;
  
  // 토글 상태: true=Annual, false=Monthly (기본값: Annual)
  bool _isAnnual = true;

  @override
  void initState() {
    super.initState();
    if (!_iapService.isInitialized) {
      _initIAP();
    }
  }

  Future<void> _initIAP() async {
    setState(() => _isLoading = true);
    await _iapService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cycle = _isAnnual ? IAPSubscriptionCycle.annual : IAPSubscriptionCycle.monthly;
    final standardProduct = _iapService.getProductFor(
      cycle: cycle,
      tier: IAPSubscriptionTier.standard,
    );
    final premiumProduct = _iapService.getProductFor(
      cycle: cycle,
      tier: IAPSubscriptionTier.premium,
    );
    final bool productsReady = standardProduct != null && premiumProduct != null;

    if (_isLoading || !productsReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Upgrade to Premium'),
          centerTitle: true,
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final standard = standardProduct!;
    final premium = premiumProduct!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade to Premium'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 30),
                
                // 헤더
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Text(
                        'Unlock Your Creative Power',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Remove watermarks, unlimited clips & 4K export',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // 글로벌 토글 스위치 [ Monthly ●── Annual (Save 20%) ]
                _buildPricingToggle(),
                
                const SizedBox(height: 30),
                
                // Standard vs Premium 대조 카드 (나란히 배치)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Standard 카드
                      Expanded(
                        child: _buildPlanCard(
                          product: standard,
                          isStandard: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Premium 카드 (화려하게)
                      Expanded(
                        child: _buildPlanCard(
                          product: premium,
                          isStandard: false,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // 구매 복원 및 약관
                TextButton.icon(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    final success = await _iapService.restorePurchases();
                    if (mounted) {
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'Purchases restored' : 'No purchases found')),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Purchases'),
                ),
                
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Cancel anytime in Store settings.\nPrices in USD. Auto-renewal applies.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
    );
  }

  /// 슬라이드 토글 스위치: [ Monthly ●── Annual (Save 20%) ]
  Widget _buildPricingToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          // Monthly 옵션
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isAnnual = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: !_isAnnual ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text(
                  'Monthly',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: !_isAnnual ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
          
          // Annual 옵션 (Save 20% 강조)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isAnnual = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _isAnnual ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Annual',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isAnnual ? Colors.white : Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isAnnual ? const Color(0xFFFFD700) : Colors.amber[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Save 20%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 플랜 카드 빌더 (Standard vs Premium)
  Widget _buildPlanCard({
    required ProductDetails product,
    required bool isStandard,
  }) {
    // 가격 추출
    final priceString = product.price.replaceAll(RegExp(r'[^\d.]'), '');
    final price = double.tryParse(priceString) ?? 0;
    
    // Annual 모드에서 할인액 계산 (월간 대비)
    String savingsText = '';
    if (_isAnnual && price > 0) {
      // Standard: $4.99/mo * 12 = $59.88 → $49.99 = Save $10
      // Premium: $9.99/mo * 12 = $119.88 → $99.99 = Save $20
      final monthlyEquivalent = isStandard ? 4.99 : 9.99;
      final annualFull = monthlyEquivalent * 12;
      final savings = annualFull - price;
      if (savings > 0) {
        savingsText = '\$${savings.toStringAsFixed(0)} Save';
      }
    }
    
    // 플랜별 정보
    final planName = isStandard ? 'Standard' : 'Premium';
    final features = isStandard 
      ? ['Ad removal', 'Unlimited clips', 'Basic editing']
      : ['Ad removal', 'Watermark removal', 'Unlimited clips', '4K export', 'Advanced editing', 'Priority support'];
    
    // Premium은 화려하게
    final isPremium = !isStandard;
    final cardColor = isPremium ? Colors.black : Colors.white;
    final textColor = isPremium ? Colors.white : Colors.black;
    final borderColor = isPremium ? Colors.amber : Colors.grey[300]!;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor, width: isPremium ? 3 : 1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isPremium ? [
          BoxShadow(
            color: Colors.amber.withOpacity(0.4),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ] : [],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 플랜명
                Text(
                  planName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 가격
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.price,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isAnnual ? '/year' : '/month',
                        style: TextStyle(
                          fontSize: 12,
                          color: isPremium ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Annual 모드에서 할인액 강조
                if (savingsText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      savingsText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 20),
                
                // 기능 목록
                ...features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: isPremium ? Colors.amber : Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: TextStyle(
                            fontSize: 13,
                            color: isPremium ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                
                const SizedBox(height: 20),
                
                // 구매 버튼
                      ElevatedButton(
                        onPressed: () => _handlePurchase(product.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPremium ? const Color(0xFFFFD700) : Colors.black,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 6,
                        ),
                        child: Text(
                          isPremium ? 'GET PREMIUM' : 'Select',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
              ],
            ),
          ),
          
          // Premium 전용: "Best Choice" 또는 "4K Exclusive" 대형 뱃지
          if (isPremium)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.stars, color: Colors.black, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'BEST CHOICE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.stars, color: Colors.black, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 구매 처리 (토글 상태에 따라 정확한 상품 ID 전달)
  Future<void> _handlePurchase(String productId) async {
    setState(() => _isLoading = true);
    try {
      final success = await _iapService.purchase(productId);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase request failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
