import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notification_settings_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  final NotificationSettingsService _notificationService =
      NotificationSettingsService.instance;

  bool _enabled = true;
  bool _loading = true;
  AuthorizationStatus _status = AuthorizationStatus.notDetermined;
  Map<NotificationCategory, bool> _categorySettings = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _loadState() async {
    await _notificationService.migrateCategorySettingsIfNeeded();
    final enabled = await _notificationService.isNotificationsEnabled();
    final status = await _notificationService.getAuthorizationStatus();
    final categories = await _notificationService.getCategorySettings();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _status = status;
      _categorySettings = categories;
      _loading = false;
    });
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await _notificationService.getAuthorizationStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
    });
    await _notificationService.syncTopicSubscriptions(
      enabled: _enabled,
      authorizationStatus: status,
      categorySettings: _categorySettings,
    );
  }

  Future<void> _onToggle(bool value) async {
    setState(() {
      _loading = true;
      _enabled = value;
    });

    await _notificationService.setNotificationsEnabled(value);

    AuthorizationStatus status = await _notificationService.getAuthorizationStatus();

    if (value && status == AuthorizationStatus.notDetermined) {
      status = await _notificationService.requestPermissionAndSync();
    } else {
      await _notificationService.syncTopicSubscriptions(
        enabled: value,
        authorizationStatus: status,
        categorySettings: _categorySettings,
      );
    }

    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });

    if (value && !_notificationService.isPermissionGranted(status)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 권한이 꺼져 있습니다. 시스템 설정에서 허용해주세요.')),
      );
    }
  }

  Future<void> _onCategoryToggle(
    NotificationCategory category,
    bool value,
  ) async {
    setState(() {
      _loading = true;
      _categorySettings = {
        ..._categorySettings,
        category: value,
      };
    });

    await _notificationService.setCategoryEnabled(category, value);

    final status = await _notificationService.getAuthorizationStatus();
    await _notificationService.syncTopicSubscriptions(
      enabled: _enabled,
      authorizationStatus: status,
      categorySettings: _categorySettings,
    );

    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  String _categoryTitle(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.clip:
        return 'Clip 알림';
      case NotificationCategory.project:
        return 'Project 알림';
      case NotificationCategory.promotion:
        return '프로모션 알림';
      case NotificationCategory.storageAlert:
        return '저장공간 알림';
    }
  }

  String _categorySubtitle(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.clip:
        return '클립 업로드/처리 상태 알림';
      case NotificationCategory.project:
        return '프로젝트 처리 및 완료 알림';
      case NotificationCategory.promotion:
        return '이벤트/혜택 안내 알림';
      case NotificationCategory.storageAlert:
        return '클라우드 용량 임계치 알림';
    }
  }

  Future<void> _openSystemSettings() async {
    final opened = await openAppSettings();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시스템 설정을 열 수 없습니다.')),
      );
    }
  }

  String _statusText(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return '허용됨';
      case AuthorizationStatus.provisional:
        return '임시 허용';
      case AuthorizationStatus.denied:
        return '거부됨';
      case AuthorizationStatus.notDetermined:
        return '미결정';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('권한 상태'),
                    subtitle: Text(_statusText(_status)),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('앱 내 알림 수신'),
                    subtitle: const Text('수신을 끄면 푸시 알림 구독이 해제됩니다.'),
                    value: _enabled,
                    onChanged: _loading ? null : _onToggle,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final category in NotificationCategory.values)
                        SwitchListTile(
                          secondary: const Icon(Icons.tune),
                          title: Text(_categoryTitle(category)),
                          subtitle: Text(_categorySubtitle(category)),
                          value: _categorySettings[category] ?? false,
                          onChanged: (!_enabled || _loading)
                              ? null
                              : (value) => _onCategoryToggle(category, value),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('시스템 설정 열기'),
                    subtitle: const Text('권한 거부 상태일 때 OS 설정에서 변경할 수 있습니다.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openSystemSettings,
                  ),
                ),
              ],
            ),
    );
  }
}

