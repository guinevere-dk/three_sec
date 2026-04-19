import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationCategory { clip, project, promotion, storageAlert }

extension NotificationCategoryX on NotificationCategory {
  String get preferenceKey {
    switch (this) {
      case NotificationCategory.clip:
        return 'notifications_category_clip_enabled';
      case NotificationCategory.project:
        return 'notifications_category_project_enabled';
      case NotificationCategory.promotion:
        return 'notifications_category_promotion_enabled';
      case NotificationCategory.storageAlert:
        return 'notifications_category_storage_alert_enabled';
    }
  }

  String get topicKey {
    switch (this) {
      case NotificationCategory.clip:
        return 'three_sec_clip';
      case NotificationCategory.project:
        return 'three_sec_project';
      case NotificationCategory.promotion:
        return 'three_sec_promotion';
      case NotificationCategory.storageAlert:
        return 'three_sec_storage_alert';
    }
  }
}

class NotificationSettingsService {
  NotificationSettingsService._();
  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const String permissionPromptedKey =
      'notification_permission_requested';
  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String categoryMigratedV1Key =
      'notifications_category_migrated_v1';
  static const String _legacyVlogPreferenceKey =
      'notifications_category_vlog_enabled';
  static const String _legacyVlogTopicKey = 'three_sec_vlog';

  static const Map<String, int> _mainTabRouteMap = {
    'capture': 0,
    'camera': 0,
    'library': 1,
    'album': 1,
    'profile': 2,
    'settings': 2,
  };

  static const Map<NotificationCategory, bool> _categoryDefaults = {
    NotificationCategory.clip: true,
    NotificationCategory.project: true,
    NotificationCategory.promotion: false,
    NotificationCategory.storageAlert: true,
  };

  Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(notificationsEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(notificationsEnabledKey, enabled);
  }

  Future<void> migrateCategorySettingsIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(categoryMigratedV1Key) ?? false;
    if (migrated) return;

    for (final entry in _categoryDefaults.entries) {
      final key = entry.key.preferenceKey;
      if (!prefs.containsKey(key)) {
        if (entry.key == NotificationCategory.project &&
            prefs.containsKey(_legacyVlogPreferenceKey)) {
          final legacyValue = prefs.getBool(_legacyVlogPreferenceKey);
          if (legacyValue != null) {
            await prefs.setBool(key, legacyValue);
            continue;
          }
        }
        await prefs.setBool(key, entry.value);
      }
    }
    await prefs.setBool(categoryMigratedV1Key, true);
  }

  Future<Map<NotificationCategory, bool>> getCategorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <NotificationCategory, bool>{};
    for (final category in NotificationCategory.values) {
      final fallback = _categoryDefaults[category] ?? false;
      result[category] = prefs.getBool(category.preferenceKey) ?? fallback;
    }
    return result;
  }

  Future<bool> isCategoryEnabled(NotificationCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = _categoryDefaults[category] ?? false;
    return prefs.getBool(category.preferenceKey) ?? fallback;
  }

  Future<void> setCategoryEnabled(
    NotificationCategory category,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(category.preferenceKey, enabled);
  }

  Future<bool> shouldShowInitialPermissionPrompt() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    final asked = prefs.getBool(permissionPromptedKey) ?? false;
    if (asked) return false;
    final enabled = prefs.getBool(notificationsEnabledKey) ?? true;
    return enabled;
  }

  Future<void> markInitialPermissionPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionPromptedKey, true);
  }

  Future<AuthorizationStatus> getAuthorizationStatus() async {
    if (kIsWeb) return AuthorizationStatus.authorized;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  bool isPermissionGranted(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  Future<AuthorizationStatus> requestPermissionAndSync() async {
    if (kIsWeb) return AuthorizationStatus.authorized;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    await syncTopicSubscriptions(
      authorizationStatus: settings.authorizationStatus,
    );
    return settings.authorizationStatus;
  }

  Future<void> syncTopicSubscriptions({
    bool? enabled,
    AuthorizationStatus? authorizationStatus,
    Map<NotificationCategory, bool>? categorySettings,
  }) async {
    if (kIsWeb) return;

    final shouldEnable = enabled ?? await isNotificationsEnabled();
    final status = authorizationStatus ?? await getAuthorizationStatus();
    final granted = isPermissionGranted(status);
    final categories = categorySettings ?? await getCategorySettings();

    if (!shouldEnable || !granted) {
      for (final category in NotificationCategory.values) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(category.topicKey);
      }
      return;
    }

    for (final category in NotificationCategory.values) {
      final isOn = categories[category] ?? false;
      if (isOn) {
        await FirebaseMessaging.instance.subscribeToTopic(category.topicKey);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(category.topicKey);
      }
    }

    // 카테고리 명칭 변경(vlog -> project) 이전 구독 정리
    await FirebaseMessaging.instance.unsubscribeFromTopic(_legacyVlogTopicKey);
  }

  Future<void> syncTopicSubscription({
    bool? enabled,
    AuthorizationStatus? authorizationStatus,
  }) async {
    await syncTopicSubscriptions(
      enabled: enabled,
      authorizationStatus: authorizationStatus,
    );
  }

  Future<void> ensureStartupSync() async {
    if (kIsWeb) return;
    await migrateCategorySettingsIfNeeded();
    await syncTopicSubscriptions();
  }

  /// 알림 payload에서 메인 탭 인덱스를 안전하게 해석한다.
  ///
  /// 지원 키: tab, targetTab, route, screen
  /// 지원 값: capture/camera, library/album, profile/settings 또는 0/1/2
  int? resolveMainTabIndexFromPayload(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }

    for (final key in const ['tab', 'targetTab', 'route', 'screen']) {
      final raw = payload[key];
      if (raw == null) continue;

      if (raw is num) {
        final index = raw.toInt();
        if (index >= 0 && index <= 2) {
          return index;
        }
        continue;
      }

      final normalized = raw.toString().trim().toLowerCase();
      if (normalized.isEmpty) continue;

      final parsedAsInt = int.tryParse(normalized);
      if (parsedAsInt != null && parsedAsInt >= 0 && parsedAsInt <= 2) {
        return parsedAsInt;
      }

      final mapped = _mainTabRouteMap[normalized];
      if (mapped != null) {
        return mapped;
      }
    }

    return null;
  }
}

