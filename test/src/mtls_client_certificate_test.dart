import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/model/client_certificate.dart';
import 'package:paperless_mobile/features/login/model/reachability_status.dart';
import 'package:paperless_mobile/features/login/server_connection/cubit/server_connection_cubit.dart';

// Test PKCS#12 fixture generated with password "secret"
const _kTestCertWithPwB64 =
    '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'
    'Qp/dtEECAggA';

// Test PKCS#12 fixture generated with no password
const _kTestCertNoPwB64 =
    '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'
    'USzrVzsCAggA';

class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

class _ThrowingConnectivityService implements ConnectivityStatusService {
  final Object errorToThrow;
  _ThrowingConnectivityService(this.errorToThrow);

  @override
  Future<ReachabilityStatus> isPaperlessServerReachable(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    dynamic additionalHeaders,
  ]) async {
    throw errorToThrow;
  }

  @override
  Stream<bool> connectivityChanges() => const Stream.empty();
  @override
  Future<int> getPaperlessServerApiVersion(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    dynamic additionalHeaders,
  ]) async => 9;
  @override
  Future<bool> isConnectedToInternet() async => true;
  @override
  Future<bool> isServerReachable(String serverAddress) async => true;
}

void main() {
  setUpAll(() {
    logger = Logger(level: Level.off);
  });

  final certWithPwBytes = Uint8List.fromList(base64Decode(_kTestCertWithPwB64));
  final certNoPwBytes = Uint8List.fromList(base64Decode(_kTestCertNoPwB64));

  group('SessionManagerImpl mTLS client certificate configuration (#666)', () {
    test(
      'succeeds for password-protected PKCS#12 (.pfx/.p12) with correct passphrase',
      () {
        final sessionManager = SessionManagerImpl();
        expect(
          () => sessionManager.updateSettings(
            clientCertificate: ClientCertificate(
              bytes: certWithPwBytes,
              filename: 'client.pfx',
              passphrase: 'secret',
            ),
          ),
          returnsNormally,
        );
      },
    );

    test(
      'succeeds for unencrypted PKCS#12 (.pfx/.p12) with null or empty passphrase',
      () {
        final sessionManager = SessionManagerImpl();
        // Test with null passphrase
        expect(
          () => sessionManager.updateSettings(
            clientCertificate: ClientCertificate(
              bytes: certNoPwBytes,
              filename: 'client.p12',
              passphrase: null,
            ),
          ),
          returnsNormally,
        );

        // Test with empty string passphrase
        expect(
          () => sessionManager.updateSettings(
            clientCertificate: ClientCertificate(
              bytes: certNoPwBytes,
              filename: 'client.pfx',
              passphrase: '',
            ),
          ),
          returnsNormally,
        );
      },
    );

    test(
      'throws when incorrect passphrase is provided for protected certificate',
      () {
        final sessionManager = SessionManagerImpl();
        expect(
          () => sessionManager.updateSettings(
            clientCertificate: ClientCertificate(
              bytes: certWithPwBytes,
              filename: 'client.pfx',
              passphrase: 'wrong_password',
            ),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('ConnectivityStatusService mTLS error mapping (#666)', () {
    test(
      'returns invalidClientCertificateConfiguration when cert passphrase is wrong',
      () async {
        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final cert = ClientCertificate(
          bytes: certWithPwBytes,
          filename: 'client.pfx',
          passphrase: 'wrong',
        );

        final status = await service.isPaperlessServerReachable(
          'https://example.com',
          cert,
        );
        expect(
          status,
          ReachabilityStatus.invalidClientCertificateConfiguration,
        );
      },
    );

    test(
      'returns invalidClientCertificateConfiguration when cert bytes are corrupted',
      () async {
        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final cert = ClientCertificate(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          filename: 'corrupted.pfx',
          passphrase: 'secret',
        );

        final status = await service.isPaperlessServerReachable(
          'https://example.com',
          cert,
        );
        expect(
          status,
          ReachabilityStatus.invalidClientCertificateConfiguration,
        );
      },
    );

    test(
      'getPaperlessServerApiVersion gracefully falls back to minSupportedApiVersion on cert error',
      () async {
        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final cert = ClientCertificate(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          filename: 'corrupted.pfx',
          passphrase: 'secret',
        );

        final version = await service.getPaperlessServerApiVersion(
          'https://example.com',
          cert,
        );
        expect(version, minSupportedApiVersion);
      },
    );
  });

  group('ServerConnectionCubit robust error handling (#666)', () {
    test(
      'emits ServerConnectionUnreachable with invalidClientCertificateConfiguration on cert error',
      () async {
        final service = _ThrowingConnectivityService(
          ArgumentError('Expected private key, but none was found'),
        );
        final cubit = ServerConnectionCubit(service);
        final cert = ClientCertificate(
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'test.pfx',
        );

        final future = expectLater(
          cubit.stream,
          emitsInOrder([
            isA<ServerConnectionCheckingReachability>(),
            predicate<ServerConnectionUnreachable>(
              (state) =>
                  state.status ==
                  ReachabilityStatus.invalidClientCertificateConfiguration,
            ),
          ]),
        );

        cubit.checkReachability(
          address: 'https://example.com',
          clientCertificate: cert,
        );

        await future;
      },
    );

    test(
      'emits ServerConnectionUnreachable with notReachable on unexpected error instead of dropping to initial',
      () async {
        final service = _ThrowingConnectivityService(
          Exception('Unknown network failure'),
        );
        final cubit = ServerConnectionCubit(service);

        final future = expectLater(
          cubit.stream,
          emitsInOrder([
            isA<ServerConnectionCheckingReachability>(),
            predicate<ServerConnectionUnreachable>(
              (state) => state.status == ReachabilityStatus.notReachable,
            ),
          ]),
        );

        cubit.checkReachability(address: 'https://example.com');

        await future;
      },
    );
  });
}
