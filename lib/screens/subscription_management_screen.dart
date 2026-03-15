import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../managers/user_status_manager.dart';
import '../services/iap_service.dart';
import 'paywall_screen.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen>
    with WidgetsBindingObserver {
  final UserStatusManager _userStatus = UserStatusManager();
  final IAPService _iapService = IAPService();

  static const String _androidPackageName = 'com.dk.three_sec';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSubscriptionState(reason: 'screen_init');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSubscriptionState(reason: 'app_resumed');
    }
  }

  Future<void> _refreshSubscriptionState({
    String reason = 'manual_refresh',
  }) async {
    print(
      '[SubscriptionManagement][Diag] refresh start '
      'reason=$reason tier(beforeSync)=${_userStatus.currentTier} '
      'nextTier(beforeSync)=${_userStatus.nextTier} '
      'effectiveAt(beforeSync)=${_userStatus.nextTierEffectiveAt}',
    );

    await _iapService.syncCancellationStateFromStore(reason: reason);
    print('[SubscriptionManagement][Diag] after cancel-sync reason=$reason');

    await _userStatus.initialize();
    print(
      '[SubscriptionManagement][Diag] refresh after initialize '
      'reason=$reason tier=${_userStatus.currentTier} '
      'productId=${_userStatus.productId} nextTier=${_userStatus.nextTier} '
      'effectiveAt=${_userStatus.nextTierEffectiveAt} '
      'estimatedExpiry=${_userStatus.estimatedExpiryAt}',
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openPaywallAndRefresh() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    await _refreshSubscriptionState(reason: 'return_from_paywall');
  }

  @override
  Widget build(BuildContext context) {
    final userStatus = _userStatus;
    final isSubscribed = userStatus.currentTier != UserTier.free;
    print(
      '[SubscriptionManagement][Diag] build '
      'tier=${userStatus.currentTier} isSubscribed=$isSubscribed '
      'productId=${userStatus.productId} nextTier=${userStatus.nextTier} '
      'effectiveAt=${userStatus.nextTierEffectiveAt} '
      'estimatedExpiry=${userStatus.estimatedExpiryAt}',
    );

    final statusLabel = _statusLabel(userStatus.currentTier);
    final expiryDate = userStatus.estimatedExpiryAt;
    final nextTier = userStatus.nextTier;
    final nextTierEffectiveAt = userStatus.nextTierEffectiveAt;
    final expiryDateText = expiryDate == null
        ? '확인 불가'
        : DateFormat('yyyy.MM.dd').format(expiryDate);

    return Scaffold(
      appBar: AppBar(title: const Text('구독 관리')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: '현재 구독 상태',
            value: statusLabel,
            helper: isSubscribed ? '활성 구독 중' : '현재 무료 플랜 이용 중',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: '만료일',
            value: expiryDateText,
            helper: isSubscribed
                ? '구독 해지 시 만료일까지 Cloud 및 편집 기능을 이용할 수 있습니다.'
                : '현재 활성 구독이 없습니다.',
          ),
          const SizedBox(height: 12),
          const _FeatureGuideCard(),
          if (nextTier != null &&
              nextTierEffectiveAt != null &&
              nextTier != userStatus.currentTier &&
              nextTierEffectiveAt.isAfter(DateTime.now())) ...[
            const SizedBox(height: 12),
            _InfoCard(
              title: '예약된 플랜 변경',
              value:
                  '${_statusLabel(userStatus.currentTier)} → ${_statusLabel(nextTier)}',
              helper: nextTier == UserTier.free
                  ? '해지 예약 완료 · Free 전환 예정일: ${DateFormat('yyyy.MM.dd').format(nextTierEffectiveAt)}'
                  : '적용 예정일: ${DateFormat('yyyy.MM.dd').format(nextTierEffectiveAt)}',
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _openPaywallAndRefresh,
              icon: const Icon(Icons.workspace_premium),
              label: Text(isSubscribed ? '플랜 변경 / 구독하기' : '구독하기'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: isSubscribed
                  ? () => _confirmAndOpenCancelSubscription(
                      context,
                      userStatus.productId,
                    )
                  : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('구독 해지'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            Platform.isAndroid
                ? '구독 해지는 Google Play 정기결제 관리 화면에서 진행됩니다.'
                : '현재 플랫폼에서는 앱 내 해지 이동을 지원하지 않습니다.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return 'Free';
      case UserTier.standard:
        return 'Standard';
      case UserTier.premium:
        return 'Premium';
    }
  }

  Future<void> _confirmAndOpenCancelSubscription(
    BuildContext context,
    String? productId,
  ) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(
          '해지 후 만료 시점부터 Cloud 및 편집 기능 사용이 불가합니다.\nCloud 데이터는 계속 보관됩니다.',
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해지하기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
        ],
      ),
    );

    if (shouldProceed == true && context.mounted) {
      await _openCancelSubscription(context, productId);
      await _refreshSubscriptionState(reason: 'return_from_play_cancel');
    }
  }

  Future<void> _openCancelSubscription(
    BuildContext context,
    String? productId,
  ) async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Android에서만 직접 이동할 수 있습니다.')),
      );
      return;
    }

    final query = <String, String>{'package': _androidPackageName};
    if (productId != null && productId.isNotEmpty) {
      query['sku'] = productId;
    }

    final uri = Uri.https(
      'play.google.com',
      '/store/account/subscriptions',
      query,
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Play 정기결제 화면을 열 수 없습니다.')),
      );
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.helper,
  });

  final String title;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _FeatureGuideCard extends StatelessWidget {
  const _FeatureGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '구독 기능 안내',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 10),
          _FeatureBullet(text: 'Cloud 백업/이동: Standard 이상에서 사용 가능'),
          SizedBox(height: 6),
          _FeatureBullet(text: '편집 기능: Standard 이상에서 사용 가능'),
          SizedBox(height: 6),
          _FeatureBullet(text: '내보내기 해상도: Free 720p · Standard 1080p · Premium 4K'),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6, color: Color(0xFF334155)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}
