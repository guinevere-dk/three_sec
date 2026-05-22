import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

typedef PromoCodeUrlLauncher = Future<bool> Function(Uri uri);
typedef PromoCodePlatformResolver = bool Function();

enum PromoCodeValidationFailure { empty, tooShort, tooLong, invalidCharacters }

enum PromoCodeRedeemLaunchStatus {
  launched,
  invalidFormat,
  unsupportedPlatform,
  launchFailed,
}

class PromoCodeValidationResult {
  const PromoCodeValidationResult({
    required this.normalizedCode,
    required this.failure,
  });

  final String normalizedCode;
  final PromoCodeValidationFailure? failure;

  bool get isValid => failure == null;
  int get codeLength => normalizedCode.length;

  String? get message {
    switch (failure) {
      case PromoCodeValidationFailure.empty:
        return '코드를 입력해 주세요.';
      case PromoCodeValidationFailure.tooShort:
        return '코드가 너무 짧습니다.';
      case PromoCodeValidationFailure.tooLong:
        return '코드는 64자 이하로 입력해 주세요.';
      case PromoCodeValidationFailure.invalidCharacters:
        return '영문, 숫자, 하이픈만 사용할 수 있습니다.';
      case null:
        return null;
    }
  }
}

class PromoCodeRedeemResult {
  const PromoCodeRedeemResult({required this.status, required this.validation});

  final PromoCodeRedeemLaunchStatus status;
  final PromoCodeValidationResult validation;

  int get codeLength => validation.codeLength;
}

class PromoCodeRedeemService {
  const PromoCodeRedeemService({
    PromoCodeUrlLauncher? urlLauncher,
    PromoCodePlatformResolver? isAndroid,
  }) : _urlLauncher = urlLauncher,
       _isAndroid = isAndroid;

  static final RegExp _allowedCodePattern = RegExp(r'^[A-Z0-9-]+$');

  final PromoCodeUrlLauncher? _urlLauncher;
  final PromoCodePlatformResolver? _isAndroid;

  static String normalizeCode(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  PromoCodeValidationResult validate(String input) {
    final normalizedCode = normalizeCode(input);
    if (normalizedCode.isEmpty) {
      return PromoCodeValidationResult(
        normalizedCode: normalizedCode,
        failure: PromoCodeValidationFailure.empty,
      );
    }
    if (normalizedCode.length < 4) {
      return PromoCodeValidationResult(
        normalizedCode: normalizedCode,
        failure: PromoCodeValidationFailure.tooShort,
      );
    }
    if (normalizedCode.length > 64) {
      return PromoCodeValidationResult(
        normalizedCode: normalizedCode,
        failure: PromoCodeValidationFailure.tooLong,
      );
    }
    if (!_allowedCodePattern.hasMatch(normalizedCode)) {
      return PromoCodeValidationResult(
        normalizedCode: normalizedCode,
        failure: PromoCodeValidationFailure.invalidCharacters,
      );
    }
    return PromoCodeValidationResult(
      normalizedCode: normalizedCode,
      failure: null,
    );
  }

  Uri buildGooglePlayRedeemUri(String normalizedCode) {
    return Uri.https('play.google.com', '/redeem', {'code': normalizedCode});
  }

  Future<PromoCodeRedeemResult> launchRedeem(String input) async {
    final validation = validate(input);
    if (!validation.isValid) {
      return PromoCodeRedeemResult(
        status: PromoCodeRedeemLaunchStatus.invalidFormat,
        validation: validation,
      );
    }

    final isAndroid = _isAndroid?.call() ?? Platform.isAndroid;
    if (!isAndroid) {
      return PromoCodeRedeemResult(
        status: PromoCodeRedeemLaunchStatus.unsupportedPlatform,
        validation: validation,
      );
    }

    final launcher = _urlLauncher ?? _launchExternal;
    final launched = await launcher(
      buildGooglePlayRedeemUri(validation.normalizedCode),
    );
    return PromoCodeRedeemResult(
      status: launched
          ? PromoCodeRedeemLaunchStatus.launched
          : PromoCodeRedeemLaunchStatus.launchFailed,
      validation: validation,
    );
  }

  static Future<bool> _launchExternal(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
