import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/iap_service.dart';

/// 페이월(결제) 화면
/// 
/// 사용자가 프리미엄 기능을 사용하려 할 때나 설정에서 진입하는 결제 유도 화면
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final IAPService _iapService = IAPService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 초기화가 안 되어 있다면 시도
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
    final products = _iapService.products;

    return Scaffold(
      appBar: AppBar(
        title: const Text('수익화 설정'),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Text(
                  '3s Premium으로\n더 멋진 일상을 기록하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                
                if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      '현재 구매 가능한 상품이 없습니다.\n스토어 연결 상태를 확인해주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...products.map((product) => _buildProductCard(product)).toList(),
                
                const SizedBox(height: 40),
                
                // 구매 복원 버튼
                TextButton.icon(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    final success = await _iapService.restorePurchases();
                    if (mounted) {
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? '구매 항목을 복원했습니다.' : '복원할 항목이 없거나 실패했습니다.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore),
                  label: const Text('구매 복원(Restore)'),
                ),
                
                const SizedBox(height: 20),
                const Text(
                  '구독은 언제든지 스토어 설정에서 취소할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
    );
  }

  /// 상품 카드 위젯 빌더
  Widget _buildProductCard(ProductDetails product) {
    // 상품 ID에 따른 간단한 설명 분기
    String description = '';
    if (product.id.contains('standard')) {
      description = '광고 제거 및 무제한 클립 생성';
    } else if (product.id.contains('premium')) {
      description = '워터마크 제거 및 고급 편집 기능 포함';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    product.title.replaceAll('(3s)', '').trim(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  product.price,
                  style: const TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _handlePurchase(product.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('구매하기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// 구매 처리
  Future<void> _handlePurchase(String productId) async {
    setState(() => _isLoading = true);
    try {
      final success = await _iapService.purchase(productId);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매 요청을 시작할 수 없습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
