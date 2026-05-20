import 'package:flutter_test/flutter_test.dart';
import 'package:three_s/managers/user_status_manager.dart';
import 'package:three_s/services/auth_service.dart';

void main() {
  group('R3 QA subscription lock guard', () {
    test('lock off allows Firestore paid restore', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: false,
        isReleaseMode: false,
        isSignedInUser: true,
        localTier: UserTier.free,
        localGraceHistoryPresent: true,
        firestoreCandidateTier: UserTier.standard,
      );

      expect(skip, isFalse);
    });

    test('lock on with local grace skips Firestore paid overwrite', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: true,
        isReleaseMode: false,
        isSignedInUser: true,
        localTier: UserTier.free,
        localGraceHistoryPresent: true,
        firestoreCandidateTier: UserTier.standard,
      );

      expect(skip, isTrue);
    });

    test('lock on without grace history does not bypass paid restore', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: true,
        isReleaseMode: false,
        isSignedInUser: true,
        localTier: UserTier.free,
        localGraceHistoryPresent: false,
        firestoreCandidateTier: UserTier.standard,
      );

      expect(skip, isFalse);
    });

    test('release mode guard forces lock disabled', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: true,
        isReleaseMode: true,
        isSignedInUser: true,
        localTier: UserTier.free,
        localGraceHistoryPresent: true,
        firestoreCandidateTier: UserTier.standard,
      );

      expect(skip, isFalse);
    });

    test('lock does not apply to Firestore free candidate', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: true,
        isReleaseMode: false,
        isSignedInUser: true,
        localTier: UserTier.free,
        localGraceHistoryPresent: true,
        firestoreCandidateTier: UserTier.free,
      );

      expect(skip, isFalse);
    });

    test('lock requires signed-in user', () {
      final skip = AuthService.shouldSkipFirestorePaidForQaLock(
        qaLockRequested: true,
        isReleaseMode: false,
        isSignedInUser: false,
        localTier: UserTier.free,
        localGraceHistoryPresent: true,
        firestoreCandidateTier: UserTier.standard,
      );

      expect(skip, isFalse);
    });
  });
}
