import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class LocalAuthenticationService {
  final LocalAuthentication localAuthentication;

  LocalAuthenticationService(this.localAuthentication);

  Future<bool> authenticateLocalUser(String localizedReason) async {
    if (await localAuthentication.isDeviceSupported()) {
      try {
        return await localAuthentication.authenticate(
          localizedReason: localizedReason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
            useErrorDialogs: true,
          ),
        );
      } on PlatformException catch (_) {
        // Handle biometric lockout (LockedOut, PermanentlyLockedOut) or unavailability
        // gracefully so caller can fall back to password/credentials (#442).
        return false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
