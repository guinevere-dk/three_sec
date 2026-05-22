import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/services/promo_code_redeem_service.dart';

void main() {
  group('PromoCodeRedeemService', () {
    const service = PromoCodeRedeemService();

    test('normalizes code by trimming, removing spaces, and uppercasing', () {
      final result = service.validate(' moa welcome ');

      expect(result.isValid, isTrue);
      expect(result.normalizedCode, 'MOAWELCOME');
      expect(result.codeLength, 10);
    });

    test('allows one-time code style hyphenated values', () {
      final result = service.validate('ab12-cd34');

      expect(result.isValid, isTrue);
      expect(result.normalizedCode, 'AB12-CD34');
    });

    test(
      'rejects invalid characters without preserving raw code externally',
      () {
        final result = service.validate('MOA_WELCOME');

        expect(result.isValid, isFalse);
        expect(result.failure, PromoCodeValidationFailure.invalidCharacters);
      },
    );

    test('builds Google Play redeem URL with query encoding', () {
      final uri = service.buildGooglePlayRedeemUri('AB12-CD34');

      expect(uri.toString(), 'https://play.google.com/redeem?code=AB12-CD34');
    });

    test('launchRedeem uses injected Android launcher', () async {
      Uri? launchedUri;
      final service = PromoCodeRedeemService(
        isAndroid: () => true,
        urlLauncher: (uri) async {
          launchedUri = uri;
          return true;
        },
      );

      final result = await service.launchRedeem(' moa welcome ');

      expect(result.status, PromoCodeRedeemLaunchStatus.launched);
      expect(result.codeLength, 10);
      expect(
        launchedUri.toString(),
        'https://play.google.com/redeem?code=MOAWELCOME',
      );
    });

    test('launchRedeem blocks unsupported platforms before launch', () async {
      var launchCalled = false;
      final service = PromoCodeRedeemService(
        isAndroid: () => false,
        urlLauncher: (_) async {
          launchCalled = true;
          return true;
        },
      );

      final result = await service.launchRedeem('MOAWELCOME');

      expect(result.status, PromoCodeRedeemLaunchStatus.unsupportedPlatform);
      expect(launchCalled, isFalse);
    });
  });
}
