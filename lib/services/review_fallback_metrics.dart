import 'package:shared_preferences/shared_preferences.dart';

/// 리뷰 대응 임시 게스트 모드용 계측 이벤트 카운터
class ReviewFallbackMetrics {
  static final ReviewFallbackMetrics _instance =
      ReviewFallbackMetrics._internal();
  factory ReviewFallbackMetrics() => _instance;
  ReviewFallbackMetrics._internal();

  static const String _keyPrefix = 'review_fallback_v1_';

  static const String _socialLoginFailurePrefix =
      '${_keyPrefix}social_login_fail_';
  static const String _socialLoginFailureTotalKey =
      '${_keyPrefix}social_login_fail_total';

  static const String _guestEntryAttemptsKey =
      '${_keyPrefix}guest_entry_attempts';
  static const String _guestEntrySuccessKey =
      '${_keyPrefix}guest_entry_success';
  static const String _guestEntryFailureKey =
      '${_keyPrefix}guest_entry_failure';

  static const String _cloudBlockTotalKey = '${_keyPrefix}cloud_block_total';
  static const String _cloudBlockOperationPrefix = '${_keyPrefix}cloud_block_';

  String _normalizeToken(String token) {
    final normalized = token
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.isEmpty) return 'unknown';
    return normalized.length > 64 ? normalized.substring(0, 64) : normalized;
  }

  Future<int> _increment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, next);
    return next;
  }

  Future<void> _logCount(String eventType, String name, int count) async {
    print('[ReviewMetrics][$eventType] $name count=$count');
  }

  Future<void> recordSocialLoginFailure({
    required String provider,
    String reason = 'unknown',
  }) async {
    final providerKey = _normalizeToken(provider);
    final reasonKey = _normalizeToken(reason);

    final total = await _increment(_socialLoginFailureTotalKey);
    await _logCount('social_login_failure', 'total', total);

    final providerCounterKey = '$_socialLoginFailurePrefix$providerKey';
    final providerFailure = await _increment(providerCounterKey);
    await _logCount(
      'social_login_failure',
      providerCounterKey,
      providerFailure,
    );

    final reasonCounterKey =
        '${_socialLoginFailurePrefix}${providerKey}_$reasonKey';
    final reasonFailure = await _increment(reasonCounterKey);
    await _logCount('social_login_failure', reasonCounterKey, reasonFailure);
  }

  Future<void> recordGuestEntry({required bool success, String? reason}) async {
    final attempts = await _increment(_guestEntryAttemptsKey);
    await _logCount('guest_entry', 'attempts', attempts);

    if (success) {
      final successCount = await _increment(_guestEntrySuccessKey);
      await _logCount('guest_entry', 'success', successCount);
      return;
    }

    final reasonKey = _normalizeToken(reason ?? 'failed');
    final failCount = await _increment(_guestEntryFailureKey);
    await _logCount('guest_entry', 'failure', failCount);

    final reasonFailure = await _increment(
      '${_guestEntryFailureKey}_$reasonKey',
    );
    await _logCount(
      'guest_entry',
      '${_guestEntryFailureKey}_$reasonKey',
      reasonFailure,
    );
  }

  Future<void> recordCloudAccessBlocked({
    required String operation,
    String reason = 'guest_mode',
  }) async {
    final operationToken = _normalizeToken(operation);
    final reasonToken = _normalizeToken(reason);

    final total = await _increment(_cloudBlockTotalKey);
    await _logCount('cloud_block', 'total', total);

    final operationCount = await _increment(
      '$_cloudBlockOperationPrefix$operationToken',
    );
    await _logCount(
      'cloud_block',
      '$_cloudBlockOperationPrefix$operationToken',
      operationCount,
    );

    final reasonCount = await _increment(
      '$_cloudBlockOperationPrefix${operationToken}_$reasonToken',
    );
    await _logCount(
      'cloud_block',
      '$_cloudBlockOperationPrefix${operationToken}_$reasonToken',
      reasonCount,
    );
  }

  /// 디버그/점검을 위한 스냅샷 로그
  Future<void> dumpCounters() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList()
      ..sort();

    final entries = keys
        .where((k) => prefs.get(k) is int)
        .map((k) => '$k=${prefs.getInt(k)}')
        .join(', ');

    print(
      '[ReviewMetrics][snapshot] totalKeys=${keys.length} counters=' +
          (entries.isEmpty ? '<none>' : entries),
    );
  }
}
