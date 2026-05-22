import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../managers/user_status_manager.dart';
import '../services/auth_service.dart';
import '../services/iap_service.dart';
import '../services/promo_code_redeem_service.dart';
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
  final AuthService _authService = AuthService();
  final PromoCodeRedeemService _promoCodeRedeemService =
      const PromoCodeRedeemService();
  bool _promoRedeemPending = false;

  static const String _androidPackageName = 'com.dk.three_sec';

  static String _entitlementTierName(UserTier tier) {
    switch (tier) {
      case UserTier.free:
        return 'free';
      case UserTier.standard:
        return 'standard';
      case UserTier.premium:
        return 'premium';
    }
  }

  static String _entitlementTrigger(String reason) {
    switch (reason) {
      case 'app_resumed':
      case 'return_from_paywall':
        return reason;
      case 'screen_init':
      case 'return_from_play_cancel':
      case 'manual_refresh':
        return 'subscription_management_init';
      default:
        return 'subscription_management_init';
    }
  }

  static void _logEntitlementRefresh({
    required String trigger,
    required String source,
    required UserTier beforeTier,
    required UserTier afterTier,
    required String result,
    required String reasonCode,
    required int durationMs,
  }) {
    print(
      '[EntitlementRefresh] '
      'trigger=${_entitlementTrigger(trigger)} '
      'source=$source '
      'before_tier=${_entitlementTierName(beforeTier)} '
      'after_tier=${_entitlementTierName(afterTier)} '
      'result=$result '
      'reason_code=$reasonCode '
      'candidate_count=0 '
      'verified_active_count=0 '
      'verified_inactive_count=0 '
      'verification_failed_count=0 '
      'duration_ms=$durationMs',
    );
  }

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
      if (_promoRedeemPending) {
        _handlePromoRedeemReturn();
      } else {
        _refreshSubscriptionState(reason: 'app_resumed');
      }
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

    await _iapService.refreshEntitlementsFromStore(reason: reason);
    print('[SubscriptionManagement][Diag] after store-refresh reason=$reason');

    await _iapService.syncCancellationStateFromStore(reason: reason);
    print('[SubscriptionManagement][Diag] after cancel-sync reason=$reason');

    final localCacheStopwatch = Stopwatch()..start();
    final beforeLocalCacheTier = _userStatus.currentTier;
    await _userStatus.initialize();
    _logEntitlementRefresh(
      trigger: reason,
      source: 'local_cache',
      beforeTier: beforeLocalCacheTier,
      afterTier: _userStatus.currentTier,
      result: beforeLocalCacheTier == _userStatus.currentTier
          ? 'preserved'
          : 'applied',
      reasonCode: 'no_candidate',
      durationMs: localCacheStopwatch.elapsedMilliseconds,
    );
    if (_authService.isAuthenticatedAccount) {
      await _authService.syncCurrentUserSubscriptionFromFirestore(
        preserveLocalPaidTier: true,
        reason: reason,
      );
      await _userStatus.initialize();
    }
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
    if (!mounted) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    await _refreshSubscriptionState(reason: 'return_from_paywall');
  }

  bool _shouldShowPromoCodeButton(UserTier tier) {
    return Platform.isAndroid && tier == UserTier.free;
  }

  Future<void> _openPromoCodeDialog() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Play 코드는 Android에서만 등록할 수 있습니다.')),
      );
      return;
    }

    if (_authService.isGuest) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('로그인이 필요합니다'),
          content: const Text(
            '프로모션 코드는 구독 권한을 MOA 계정에 연결하기 위해 로그인이 필요합니다.\n\n먼저 로그인한 뒤 같은 Google Play 계정으로 코드 등록을 진행해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController();
    String? errorText;
    var isLaunching = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isLaunching,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final validation = _promoCodeRedeemService.validate(
                controller.text,
              );
              final canLaunch = validation.isValid && !isLaunching;

              void handleCodeChanged(String value) {
                final upperValue = value.toUpperCase();
                if (upperValue != value) {
                  controller.value = TextEditingValue(
                    text: upperValue,
                    selection: TextSelection.collapsed(
                      offset: upperValue.length,
                    ),
                  );
                }

                final nextValidation = _promoCodeRedeemService.validate(
                  upperValue,
                );
                setDialogState(() {
                  errorText =
                      upperValue.trim().isEmpty || nextValidation.isValid
                      ? null
                      : nextValidation.message;
                });
              }

              Future<void> submit() async {
                final submitValidation = _promoCodeRedeemService.validate(
                  controller.text,
                );
                if (!submitValidation.isValid) {
                  setDialogState(() => errorText = submitValidation.message);
                  return;
                }

                debugPrint(
                  '[PromoRedeem] launch requested '
                  'source=subscription_management '
                  'platform=${Platform.operatingSystem} '
                  'codeLength=${submitValidation.codeLength} validFormat=true',
                );

                setDialogState(() {
                  isLaunching = true;
                  errorText = null;
                });

                final result = await _promoCodeRedeemService.launchRedeem(
                  controller.text,
                );
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  isLaunching = false;
                  errorText =
                      result.status == PromoCodeRedeemLaunchStatus.invalidFormat
                      ? result.validation.message
                      : null;
                });

                switch (result.status) {
                  case PromoCodeRedeemLaunchStatus.launched:
                    if (mounted) {
                      setState(() => _promoRedeemPending = true);
                    }
                    Navigator.pop(dialogContext);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Google Play에서 코드 등록을 완료한 뒤 앱으로 돌아와 주세요.',
                          ),
                        ),
                      );
                    }
                    break;
                  case PromoCodeRedeemLaunchStatus.invalidFormat:
                    break;
                  case PromoCodeRedeemLaunchStatus.unsupportedPlatform:
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Google Play 코드는 Android에서만 등록할 수 있습니다.',
                          ),
                        ),
                      );
                    }
                    break;
                  case PromoCodeRedeemLaunchStatus.launchFailed:
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Google Play 코드 등록 화면을 열 수 없습니다. Play Store에서 프로필 > 결제 및 정기 결제 > 코드 사용으로 등록해 주세요.',
                          ),
                        ),
                      );
                    }
                    break;
                }
              }

              return AlertDialog(
                title: const Text('Google Play 코드 등록'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google Play에 로그인된 계정이 MOA 구독에 사용할 Google 계정과 같은지 확인한 뒤 등록해 주세요.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        enabled: !isLaunching,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: handleCodeChanged,
                        decoration: InputDecoration(
                          labelText: '프로모션 코드',
                          hintText: '받은 코드 입력',
                          errorText: errorText,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '등록 후 앱으로 돌아오면 구독 상태를 다시 확인합니다. 필요하면 Standard 구매창의 코드 사용 메뉴에서도 같은 코드를 등록할 수 있습니다.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isLaunching
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('취소'),
                  ),
                  FilledButton.icon(
                    onPressed: canLaunch ? submit : null,
                    icon: isLaunching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new, size: 18),
                    label: Text(isLaunching ? '이동 중...' : '코드 등록하러 가기'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _handlePromoRedeemReturn() async {
    if (!_promoRedeemPending) return;

    final beforeTier = _userStatus.currentTier;
    debugPrint(
      '[PromoRedeem] return observed '
      'source=subscription_management '
      'beforeTier=${_entitlementTierName(beforeTier)} pending=true',
    );

    // main.dart refreshes IAP on app resume. Wait briefly, then re-read local
    // entitlement state so this screen does not issue an immediate duplicate
    // Store query for the same return event.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    await _userStatus.initialize();
    if (_authService.isAuthenticatedAccount) {
      await _authService.syncCurrentUserSubscriptionFromFirestore(
        preserveLocalPaidTier: true,
        reason: 'promo_redeem_return',
      );
      await _userStatus.initialize();
    }
    if (!mounted) return;

    final afterTier = _userStatus.currentTier;
    final activeStandard = _userStatus.isStandardOrAbove();
    debugPrint(
      '[PromoRedeem] return sync done '
      'source=subscription_management '
      'beforeTier=${_entitlementTierName(beforeTier)} '
      'afterTier=${_entitlementTierName(afterTier)} '
      'activeStandard=$activeStandard refreshSource=global_resume_debounce',
    );

    setState(() => _promoRedeemPending = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          activeStandard
              ? 'Standard 구독이 활성화되었습니다.'
              : '아직 활성 구독을 확인하지 못했습니다. Google Play에서 코드 등록을 완료했는지 확인해 주세요.',
        ),
      ),
    );
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

    final currentTier = userStatus.currentTier;
    final statusLabel = _statusLabel(currentTier);
    final primaryButtonLabel = switch (currentTier) {
      UserTier.free => 'Standard 구독하기',
      UserTier.standard => 'Standard 플랜 관리',
      UserTier.premium => '구독 상태 확인',
    };
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
                ? '구독 해지 시 만료일까지 Cloud 및 편집 기능을 이용할 수 있습니다. 만료 전 Cloud 보관함에서 필요한 클립을 이 기기에 복원해 두세요.'
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
              label: Text(primaryButtonLabel),
            ),
          ),
          if (_shouldShowPromoCodeButton(currentTier)) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openPromoCodeDialog,
                icon: const Icon(Icons.redeem_outlined),
                label: const Text('프로모션 코드'),
              ),
            ),
          ],
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
        title: const Text('구독 해지 전 확인'),
        content: const Text(
          '해지 후 만료 시점부터 Cloud 및 편집 기능 사용이 불가합니다.\n\n만료 전 Cloud 보관함에서 필요한 클립을 이 기기에 복원해 두세요.',
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
          _FeatureBullet(text: '50 GB Cloud 제공'),
          SizedBox(height: 6),
          _FeatureBullet(text: '편집 기능 제공'),
          SizedBox(height: 6),
          _FeatureBullet(text: '내보내기 해상도 1080p 제공'),
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
