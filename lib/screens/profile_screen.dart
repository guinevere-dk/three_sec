import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../managers/user_status_manager.dart';
import '../managers/video_manager.dart';
import '../services/auth_service.dart';

/// 사용자 프로필을 보여주는 화면
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final UserStatusManager _userStatusManager = UserStatusManager();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<User?>(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data;
          if (user == null) {
            return _buildEmptyState();
          }

          return _buildProfileBody(user);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 68, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              '로그인 후 프로필을 확인할 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showSnackbar('로그인 화면은 아직 연결되지 않았습니다.'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('로그인하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBody(User user) {
    final tier = _userStatusManager.currentTier;
    final isPremium = tier == UserTier.premium;
    final badgeLabel = isPremium ? 'Premium' : 'Standard';
    final detailText = _tierDetailText(tier);
    final displayName = (user.displayName?.trim().isEmpty ?? true)
        ? '이름 정보 없음'
        : user.displayName!;
    final email = user.email ?? '이메일 정보 없음';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: Colors.grey[200],
              foregroundImage: (user.photoURL != null) ? NetworkImage(user.photoURL!) : null,
              child: user.photoURL == null
                  ? const Icon(Icons.person, size: 48, color: Colors.grey)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            _buildSubscriptionCard(badgeLabel, isPremium, detailText),
            const SizedBox(height: 24),
            _buildCloudUsageCard(),
            const SizedBox(height: 24),
            _buildSettingsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(String badgeLabel, bool isPremium, String detailText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 구독 등급',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildTierBadge(badgeLabel, isPremium),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  detailText,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _openSubscriptionManagement,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('구독 관리'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierBadge(String label, bool isPremium) {
    final gradient = isPremium
        ? const LinearGradient(
            colors: [Color(0xFF5E3BFF), Color(0xFF9C5BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Colors.black87, Colors.black54],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '설정',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1),
          _buildSettingTile(
            label: '알림 설정',
            icon: Icons.notifications,
            onTap: _handleNotificationSettings,
          ),
          _buildSettingTile(
            label: '개인정보 처리방침',
            icon: Icons.privacy_tip,
            onTap: _handlePrivacyPolicy,
          ),
          _buildSettingTile(
            label: '로그아웃',
            icon: Icons.logout,
            onTap: _handleLogout,
            destructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCloudUsageCard() {
    return FutureBuilder<CloudUsage>(
      future: videoManager.getCloudUsage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        }
        final usage = snapshot.data ?? const CloudUsage(usedBytes: 0, limitBytes: 10 * 1024 * 1024 * 1024);
        final ratio = usage.limitBytes == 0 ? 0.0 : (usage.usedBytes / usage.limitBytes).clamp(0.0, 1.0);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '클라우드 사용량',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '${_formatBytes(usage.usedBytes)} / ${_formatBytes(usage.limitBytes)} 사용 중',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    final gb = bytes / 1024 / 1024 / 1024;
    return '${gb.toStringAsFixed(1)}GB';
  }

  Widget _buildSettingTile({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      horizontalTitleGap: 0,
      minLeadingWidth: 0,
      leading: Icon(icon, color: destructive ? Colors.redAccent : Colors.black54),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: destructive ? Colors.redAccent : Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }

  Future<void> _openSubscriptionManagement() async {
    if (Platform.isIOS) {
      final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
      await _launchOrReport(uri);
    } else if (Platform.isAndroid) {
      final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
      await _launchOrReport(uri);
    } else {
      _showSnackbar('구독 관리는 모바일 기기에서만 지원됩니다.');
    }
  }

  Future<void> _launchOrReport(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnackbar('스토어를 열 수 없습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (!mounted) return;
    _showSnackbar('로그아웃되었습니다.');
  }

  void _handleNotificationSettings() {
    _showSnackbar('OS 설정의 알림 항목에서 변경 가능합니다.');
  }

  void _handlePrivacyPolicy() {
    _showSnackbar('개인정보 처리방침은 웹에서 곧 공개됩니다.');
  }

  String _tierDetailText(UserTier tier) {
    switch (tier) {
      case UserTier.premium:
        return 'Premium 정기구독 중이며 모든 기능을 이용할 수 있어요.';
      case UserTier.standard:
        return 'Standard 구독 중입니다. 광고와 시간 제한이 해제됩니다.';
      case UserTier.free:
        return 'Free 등급입니다. Standard 기능 업그레이드를 고려해보세요.';
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
