import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import 'announcements_screen.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final UserStatusManager _userStatusManager = UserStatusManager();
  final CloudService _cloudService = CloudService();
  final ImagePicker _imagePicker = ImagePicker();
  String _appVersionText = 'v- (Build -)';
  bool _isDeletingAccount = false;

  static const Color _bgColor = Color(0xFFF6F7F8);
  static const Color _cardColor = Colors.white;
  static const Color _primaryBlue = Color(0xFF2BADEE);

  @override
  void initState() {
    super.initState();
    _initializeProfileState();
  }

  Future<void> _initializeProfileState() async {
    print(
      '[ProfileScreen][Diag] initialize start '
      'tier(beforeInit)=${_userStatusManager.currentTier} '
      'nextTier(beforeInit)=${_userStatusManager.nextTier} '
      'effectiveAt(beforeInit)=${_userStatusManager.nextTierEffectiveAt}',
    );

    // UserStatusManager는 앱 시작 직후 비동기 초기화될 수 있어
    // 프로필 진입 시점에 최신 tier를 보장하도록 한 번 더 초기화한다.
    await _userStatusManager.initialize();

    print(
      '[ProfileScreen][Diag] initialize after userStatus.initialize '
      'tier=${_userStatusManager.currentTier} '
      'productId=${_userStatusManager.productId} '
      'nextTier=${_userStatusManager.nextTier} '
      'effectiveAt=${_userStatusManager.nextTierEffectiveAt}',
    );

    final downgraded = await _userStatusManager
        .evaluateAndAutoDowngradeIfExpired(reason: 'profile_initialize');
    if (downgraded) {
      await _authService.syncFreeTierToFirestore(
        reason: 'profile_initialize_auto_downgrade',
      );
    }

    await _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionText = 'v${info.version} (Build ${info.buildNumber})';
      });
    } catch (_) {}
  }

  Future<void> _refreshProfile() async {
    print(
      '[ProfileScreen][Diag] refresh start '
      'tier(beforeInit)=${_userStatusManager.currentTier} '
      'nextTier(beforeInit)=${_userStatusManager.nextTier}',
    );

    await _userStatusManager.initialize();

    print(
      '[ProfileScreen][Diag] refresh after userStatus.initialize '
      'tier=${_userStatusManager.currentTier} '
      'productId=${_userStatusManager.productId} '
      'nextTier=${_userStatusManager.nextTier} '
      'effectiveAt=${_userStatusManager.nextTierEffectiveAt}',
    );

    final downgraded = await _userStatusManager
        .evaluateAndAutoDowngradeIfExpired(reason: 'profile_refresh');
    if (downgraded) {
      await _authService.syncFreeTierToFirestore(
        reason: 'profile_refresh_auto_downgrade',
      );
    }

    await _loadAppVersion();
  }

  String _profileDisplayName(User? user) {
    final trimmedDisplayName = user?.displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      return trimmedDisplayName;
    }

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }

    final uid = user?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      final suffix = uid.length > 6 ? uid.substring(uid.length - 6) : uid;
      return '사용자 $suffix';
    }

    return 'Guest User';
  }

  String _providerLabel(User? user) {
    if (user == null) return '로그인';

    final providerIds = user.providerData
        .map((entry) => entry.providerId.toLowerCase())
        .toList(growable: false);

    if (providerIds.any((value) => value.contains('kakao'))) return 'KAKAO';
    if (providerIds.any((value) => value.contains('naver'))) return 'NAVER';
    if (providerIds.any((value) => value.contains('google'))) return 'GOOGLE';
    if (providerIds.any((value) => value.contains('apple'))) return 'APPLE';
    if (providerIds.any((value) => value.isNotEmpty)) {
      return providerIds.first.toUpperCase();
    }

    return 'SOCIAL';
  }

  String _profileSubtitle(User? user) {
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }

    final provider = _providerLabel(user);
    return '$provider로 로그인됨';
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _openAnnouncements() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
    );
  }

  Future<void> _openEditProfileDialog() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final nicknameController = TextEditingController(
      text: _profileDisplayName(user),
    );

    File? selectedImageFile;
    String? previewPhotoUrl = user.photoURL;
    bool isSaving = false;
    String? nicknameErrorText;

    final result = await showDialog<({bool saved, String message})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            ImageProvider? imageProvider;
            if (selectedImageFile != null) {
              imageProvider = FileImage(selectedImageFile!);
            } else if (previewPhotoUrl != null && previewPhotoUrl!.isNotEmpty) {
              imageProvider = NetworkImage(previewPhotoUrl!);
            }

            return AlertDialog(
              title: const Text('프로필 편집'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: isSaving
                          ? null
                          : () async {
                              final picked = await _imagePicker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 85,
                                maxWidth: 1024,
                              );
                              if (picked == null) return;

                              setDialogState(() {
                                selectedImageFile = File(picked.path);
                                previewPhotoUrl = null;
                              });
                            },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: const Color(0xFFE2E8F0),
                            backgroundImage: imageProvider,
                            child: imageProvider == null
                                ? const Icon(
                                    Icons.person,
                                    size: 44,
                                    color: Color(0xFF94A3B8),
                                  )
                                : null,
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _primaryBlue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_library,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '이미지 변경',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nicknameController,
                      enabled: !isSaving,
                      maxLength: 30,
                      decoration: InputDecoration(
                        labelText: '닉네임',
                        hintText: '닉네임을 입력하세요',
                        errorText: nicknameErrorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext, (
                          saved: false,
                          message: '프로필 편집이 취소되었습니다.',
                        )),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final trimmedName = nicknameController.text.trim();
                          if (trimmedName.isEmpty) {
                            setDialogState(() {
                              nicknameErrorText = '닉네임을 입력해 주세요.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            nicknameErrorText = null;
                          });

                          final saveResult = await _authService
                              .updateCurrentUserProfile(
                                displayName: trimmedName,
                                profileImageFile: selectedImageFile,
                              );

                          if (!saveResult.success) {
                            setDialogState(() {
                              isSaving = false;
                            });
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(saveResult.message)),
                            );
                            return;
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, (
                            saved: true,
                            message: saveResult.message,
                          ));
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    nicknameController.dispose();

    if (result == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));

    if (result.saved) {
      await _refreshProfile();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _shareApp() async {
    await Share.share('3-Second Vlog와 함께 짧고 빠르게 브이로그를 기록해보세요!');
  }

  Future<void> _openHelp() async {
    final supportEmail = Uri.parse(
      'mailto:dongkwon81@gmail.com?subject=Three%20Sec%20Vlog%20Support',
    );
    final ok = await launchUrl(supportEmail);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('메일 앱을 열 수 없습니다.')));
    }
  }

  Future<void> _confirmSignOut() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('로그아웃하시겠습니까')],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _authService.signOut(localDataPolicy: 'retain');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그아웃 되었습니다.')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_isDeletingAccount) return;

    final eligibility = await _authService.checkAccountDeletionEligibility();
    if (!mounted) return;
    if (!eligibility.canDelete) {
      await _showAccountDeletionBlockedDialog(message: eligibility.message);
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정 삭제'),
        content: Text(
          eligibility.hasActiveSubscription
              ? '계정 삭제가 일시적으로 제한된 상태입니다.\n잠시 후 다시 시도해 주세요.'
              : '계정을 삭제하면 계정 데이터가 모두 제거됩니다. 계속 진행할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제 진행'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (!mounted) return;
      setState(() {
        _isDeletingAccount = true;
      });

      final deleteResult = await _authService.deleteAccount(
        purgeCloud: () async {
          final purge = await _cloudService.purgeCurrentUserCloudData();
          return (
            success: purge.success,
            message: purge.message,
            failedPhase: purge.failedPhase,
          );
        },
        localDataPolicy: 'delete',
      );
      if (!mounted) return;

      final currentUid = _authService.currentUser?.uid;

      setState(() {
        _isDeletingAccount = false;
      });

      if (deleteResult.requiresRecentLogin) {
        await _showDeleteRequiresRecentLoginDialog(uid: currentUid);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteResult.success ? '계정이 삭제되었습니다.' : deleteResult.message,
          ),
        ),
      );
    }
  }

  /// 계정 삭제 시 재인증 필요 안내 다이얼로그
  Future<void> _showDeleteRequiresRecentLoginDialog({String? uid}) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정 삭제를 진행하려면 재인증이 필요합니다'),
        content: Text(
          '보안을 위해 최근 로그인 이력이 필요합니다.\n\n'
          '로그아웃 후 재로그인하여 삭제를 진행해 주세요. ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final dialogContext = context;
              await _authService.signOut(localDataPolicy: 'retain');
              if (!mounted || !dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('재인증을 위해 로그아웃 되었습니다. 카카오 로그인을 다시 진행해 주세요.'),
                ),
              );
            },
            child: const Text('지금 재로그인'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountDeletionBlockedDialog({required String message}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정 삭제 불가'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final tier = _userStatusManager.currentTier;
    print(
      '[ProfileScreen][Diag] build '
      'tier=$tier '
      'productId=${_userStatusManager.productId} '
      'nextTier=${_userStatusManager.nextTier} '
      'effectiveAt=${_userStatusManager.nextTierEffectiveAt} '
      'uid=${_userStatusManager.userId}',
    );
    final displayName = _profileDisplayName(user);
    final subtitle = _profileSubtitle(user);

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _openEditProfileDialog,
            child: const Text(
              'Edit',
              style: TextStyle(
                color: _primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshProfile,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _buildProfileCard(
                  displayName: displayName,
                  subtitle: subtitle,
                  photoUrl: user?.photoURL,
                ),
                const SizedBox(height: 18),
                _buildStatsCard(),
                const SizedBox(height: 20),
                _buildSectionTitle('SETTINGS'),
                _buildMenuGroup(
                  children: [
                    _buildMenuItem(
                      Icons.notifications,
                      '알림 설정',
                      iconBgColor: const Color(0xFFFFF7ED),
                      iconColor: const Color(0xFFF97316),
                      onTap: _openNotifications,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSectionTitle('SUPPORT'),
                _buildMenuGroup(
                  children: [
                    _buildMenuItem(
                      Icons.campaign_outlined,
                      '공지사항',
                      iconBgColor: const Color(0xFFEEF2FF),
                      iconColor: const Color(0xFF4F46E5),
                      onTap: _openAnnouncements,
                    ),
                    _buildMenuItem(
                      Icons.help,
                      'Help & Feedback',
                      iconBgColor: const Color(0xFFF1F5F9),
                      iconColor: const Color(0xFF475569),
                      onTap: _openHelp,
                    ),
                    _buildMenuItem(
                      Icons.ios_share,
                      '앱 공유',
                      iconBgColor: const Color(0xFFEFF6FF),
                      iconColor: _primaryBlue,
                      onTap: _shareApp,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSectionTitle('ACCOUNT'),
                _buildMenuGroup(
                  children: [
                    _buildMenuItem(
                      Icons.logout,
                      '로그아웃',
                      iconBgColor: const Color(0xFFF8FAFC),
                      iconColor: const Color(0xFF475569),
                      onTap: _isDeletingAccount ? null : _confirmSignOut,
                    ),
                    _buildMenuItem(
                      Icons.delete_forever_outlined,
                      '계정 삭제',
                      valueText: '영구 삭제',
                      valueColor: const Color(0xFFEF4444),
                      iconBgColor: const Color(0xFFFEF2F2),
                      iconColor: const Color(0xFFEF4444),
                      onTap: _isDeletingAccount ? null : _confirmDeleteAccount,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    _appVersionText,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isDeletingAccount)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        '계정/Cloud 삭제 중입니다...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: Color(0xFF94A3B8),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required String displayName,
    required String subtitle,
    required String? photoUrl,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF8FAFC),
                      width: 5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    image: (photoUrl != null && photoUrl.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: const Color(0xFFE2E8F0),
                  ),
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? const Icon(
                          Icons.person,
                          size: 63,
                          color: Color(0xFF94A3B8),
                        )
                      : null,
                ),
              ],
            ),
            SizedBox(width: isCompact ? 18 : 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isCompact ? 22 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsCard() {
    return Consumer<VideoManager>(
      builder: (context, videoManager, child) {
        final clipCount = NumberFormat.decimalPattern().format(
          videoManager.totalClipCount,
        );

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [Expanded(child: _buildStatItem(clipCount, 'CLIP'))],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String value, String label, {bool isStorage = false}) {
    final isCloudUsageSummary =
        isStorage && (value.contains('/') || value.contains('미지원'));
    final parsedStorage = _splitStorageText(value);

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isCloudUsageSummary)
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            )
          else if (isStorage)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: parsedStorage.$1,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  TextSpan(
                    text: parsedStorage.$2,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _splitStorageText(String value) {
    final cleaned = value.trim();
    final match = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)$',
    ).firstMatch(cleaned);
    if (match != null) {
      return (match.group(1) ?? cleaned, (match.group(2) ?? '').toUpperCase());
    }
    return (cleaned, '');
  }

  Widget _buildMenuGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFEFF2F6),
                indent: 18,
                endIndent: 18,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String title, {
    String? valueText,
    Color valueColor = const Color(0xFF94A3B8),
    Color iconColor = const Color(0xFF334155),
    Color iconBgColor = const Color(0xFFF1F5F9),
    Future<void> Function()? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap == null ? null : () => onTap(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (valueText != null) ...[
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1), size: 24),
          ],
        ),
      ),
    );
  }
}
