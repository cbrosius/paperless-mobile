import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:paperless_mobile/features/login/services/authentication_service.dart';

class FakeLocalAuthentication extends Fake implements LocalAuthentication {
  bool isSupported = true;
  bool shouldThrowLockedOut = false;
  bool authSuccess = true;

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    if (shouldThrowLockedOut) {
      throw PlatformException(
        code: 'LockedOut',
        message: 'The operation was canceled because the API is locked out.',
      );
    }
    return authSuccess;
  }
}

void main() {
  group('LocalAuthenticationService (#442)', () {
    late FakeLocalAuthentication fakeLocalAuth;
    late LocalAuthenticationService service;

    setUp(() {
      fakeLocalAuth = FakeLocalAuthentication();
      service = LocalAuthenticationService(fakeLocalAuth);
    });

    test('returns true when biometric authentication succeeds', () async {
      fakeLocalAuth.authSuccess = true;
      final result = await service.authenticateLocalUser('Reason');
      expect(result, isTrue);
    });

    test(
      'returns false without throwing when PlatformException (LockedOut) occurs',
      () async {
        fakeLocalAuth.shouldThrowLockedOut = true;
        final result = await service.authenticateLocalUser('Reason');
        expect(result, isFalse);
      },
    );

    test('returns false when device is not supported', () async {
      fakeLocalAuth.isSupported = false;
      final result = await service.authenticateLocalUser('Reason');
      expect(result, isFalse);
    });
  });
}
