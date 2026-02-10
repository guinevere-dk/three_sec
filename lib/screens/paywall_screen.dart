import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:video_player/video_player.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/iap_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final IAPService _iapService = IAPService();
  VideoPlayerController? _videoController;
  bool _isLoading = false;
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  // 0: Standard, 1: Premium
  int _selectedTierIndex = 1; // Default to Premium
  
  // Selected Pricing Option (for Premium)
  // 0: Annual, 1: Monthly
  int _selectedPricingIndex = 0; // Default to Annual

  @override
  void initState() {
    super.initState();
    _initVideoBackground();
    if (!_iapService.isInitialized) {
      _initIAP();
    }
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
    setState(() => _isLoading = true);
    await _iapService.initialize();
    
    // Listen to purchase updates for UI feedback
    final Stream<List<PurchaseDetails>> purchaseUpdated = InAppPurchase.instance.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $error")));
         setState(() => _isLoading = false);
      }
    });

    if (mounted) {
      setState(() {
        _products = _iapService.products;
        _isLoading = false;
      });
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _isLoading = true);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text("Purchase Failed: ${purchaseDetails.error?.message ?? 'Unknown Error'}"))
             );
             setState(() => _isLoading = false);
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("Welcome to Premium!"))
             );
             setState(() => _isLoading = false);
             Navigator.pop(context); // Close Paywall
          }
        }
      }
    }
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

          // 2. Blur Overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withAlpha(102),
              ),
            ),
          ),

          // 3. Content
          SafeArea(
            child: Column(
              children: [
                // Close Button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                
                const Spacer(),

                // Main Content Card
                _buildGlassCard(),
              ],
            ),
          ),
          
          if (_isLoading)
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
         color: Colors.white.withAlpha(25),
         borderRadius: BorderRadius.circular(32),
         border: Border.all(color: Colors.white24),
         boxShadow: [
           BoxShadow(
             color: Colors.black.withAlpha(51),
             blurRadius: 20,
             spreadRadius: 5,
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
           
           if (_selectedTierIndex == 1) ...[
              // Pricing Cards (Only for Premium)
              if (_products.isNotEmpty) ...[
                 Row(
                   crossAxisAlignment: CrossAxisAlignment.end,
                   children: [
                     // Monthly (Anchor - Smaller)
                     Expanded(
                       flex: 2,
                       child: _buildPricingCard(
                         title: "Monthly",
                         price: _getPrice(IAPService.premiumMonthly),
                         isHero: false,
                         isSelected: _selectedPricingIndex == 1,
                         onTap: () => setState(() => _selectedPricingIndex = 1),
                       ),
                     ),
                     const SizedBox(width: 12),
                     // Annual (Hero - Larger)
                     Expanded(
                       flex: 3,
                       child: _buildPricingCard(
                         title: "Annual",
                         price: _getPrice(IAPService.premiumAnnual),
                         subtitle: "Save 20%",
                         isHero: true,
                         isSelected: _selectedPricingIndex == 0,
                         onTap: () => setState(() => _selectedPricingIndex = 0),
                       ),
                     ),
                   ],
                 ),
              ] else ...[
                 const Center(child: CircularProgressIndicator(color: Colors.white)),
                 const SizedBox(height: 20),
              ],
             const SizedBox(height: 24),
             
             // Upgrade Button
             SizedBox(
               width: double.infinity,
               height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    final productId = _selectedPricingIndex == 0 
                        ? IAPService.premiumAnnual 
                        : IAPService.premiumMonthly;
                    _iapService.purchase(productId);
                  },
                 style: ElevatedButton.styleFrom(
                   backgroundColor: const Color(0xFFFFD700),
                   foregroundColor: Colors.black,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   elevation: 0,
                 ),
                 child: const Text(
                   "Upgrade Now",
                   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                 ),
               ),
             ),
           ] else ...[
             // Standard Message
             const Padding(
               padding: EdgeInsets.symmetric(vertical: 20),
               child: Text(
                 "You are currently on the Standard plan.",
                 style: TextStyle(color: Colors.white70),
               ),
             ),
           ],
           
           const SizedBox(height: 16),
           TextButton(
             onPressed: () => _iapService.restorePurchases(), 
             child: const Text("Restore Purchases", style: TextStyle(color: Colors.white54, fontSize: 12))
           ),
         ],
       ),
    );
  }

  Widget _buildTierToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(16),
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
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTierIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitList() {
    final benefits = _selectedTierIndex == 0
        ? ["720p Export", "Basic Filters", "Standard Support"]
        : ["4K Export", "All AI Filters", "Priority Support", "No Watermark"];

    return Column(
      children: benefits.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: _selectedTierIndex == 1 ? const Color(0xFFFFD700) : Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(b, style: const TextStyle(color: Colors.white)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    String? subtitle,
    required bool isHero,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(isHero ? 16 : 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withAlpha(38) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white12, 
            width: isSelected ? 2 : 1
          ),
        ),
        child: Column(
          children: [
            if (isHero) ...[
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                 decoration: BoxDecoration(
                   color: const Color(0xFFFFD700),
                   borderRadius: BorderRadius.circular(4)
                 ),
                 child: const Text("BEST VALUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
               ),
               const SizedBox(height: 8),
            ],
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 4),
            Text(price, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12)),
            ]
          ],
        ),
      ),
    );
  }

  String _getPrice(String productId) {
    try {
      if (_products.isEmpty) return "...";
      final product = _products.firstWhere((p) => p.id == productId);
      return product.price;
    } catch (e) {
      return "..."; // Loading or Error
    }
  }
}

