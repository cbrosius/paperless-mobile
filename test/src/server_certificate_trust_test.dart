import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/core/security/certificate_trust_store.dart';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/model/reachability_status.dart';
import 'package:paperless_mobile/features/login/server_connection/cubit/server_connection_cubit.dart';

class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

void main() {
  setUpAll(() {
    logger = Logger(level: Level.off);
  });

  group('ServerCertificate Model', () {
    test('formats fingerprint with colons and uppercase', () {
      final cert = ServerCertificate(
        fingerprint: 'aabbccdd11223344',
        host: 'example.com',
        trustedAt: DateTime(2025, 1, 1),
      );
      expect(cert.formattedFingerprint, 'AA:BB:CC:DD:11:22:33:44');
    });

    test('serializes and deserializes to JSON correctly', () {
      final now = DateTime.now();
      final cert = ServerCertificate(
        fingerprint: 'e55bfa1d63fb76b2',
        host: 'Paperless.local',
        port: 8443,
        subject: 'CN=localhost',
        issuer: 'CN=localhost',
        validFrom: DateTime(2025, 1, 1),
        validTo: DateTime(2027, 1, 1),
        trustedAt: now,
      );

      final json = cert.toJson();
      final restored = ServerCertificate.fromJson(json);

      expect(restored.fingerprint, 'e55bfa1d63fb76b2');
      expect(restored.host, 'paperless.local');
      expect(restored.port, 8443);
      expect(restored.subject, 'CN=localhost');
      expect(restored.issuer, 'CN=localhost');
      expect(restored.validFrom, DateTime(2025, 1, 1));
      expect(restored.validTo, DateTime(2027, 1, 1));
      expect(restored, cert);
    });
  });

  group('CertificateTrustStore in-memory implementation', () {
    test(
      'trusts, checks, and untrusts certificates case-insensitively',
      () async {
        final store = CertificateTrustStoreImpl.inMemory();
        const fingerprint = 'ABCDEF123456';
        const host = 'Paperless.Local';

        expect(store.isCertificateTrusted(host, fingerprint), isFalse);

        final cert = ServerCertificate(
          fingerprint: fingerprint,
          host: host,
          trustedAt: DateTime.now(),
        );
        await store.trustCertificate(cert);

        expect(
          store.isCertificateTrusted('paperless.local', 'abcdef123456'),
          isTrue,
        );
        expect(store.isCertificateTrusted('other.host', fingerprint), isFalse);
        expect(store.getTrustedCertificates().length, 1);

        await store.untrustCertificate('paperless.local', 'abcdef123456');
        expect(store.isCertificateTrusted(host, fingerprint), isFalse);
        expect(store.getTrustedCertificates(), isEmpty);
      },
    );
  });

  group('Self-Signed Certificate HTTPS Server Verification (#256)', () {
    late HttpServer server;
    late String serverAddress;
    late String expectedFingerprint;

    setUpAll(() async {
      final openssl = r'C:\Program Files\Git\usr\bin\openssl.exe';
      final dir = Directory.systemTemp.createTempSync('mtls_server_test');
      final keyPath = '${dir.path}/server.key';
      final crtPath = '${dir.path}/server.crt';

      Process.runSync(openssl, [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-keyout',
        keyPath,
        '-out',
        crtPath,
        '-days',
        '1',
        '-nodes',
        '-subj',
        '/CN=127.0.0.1',
      ]);

      final certBytes = File(crtPath).readAsBytesSync();
      // Calculate expected fingerprint from DER (or test server cert)
      final serverContext = SecurityContext()
        ..usePrivateKey(keyPath)
        ..useCertificateChain(crtPath);

      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );

      serverAddress = 'https://${server.address.address}:${server.port}';

      server.listen((HttpRequest request) {
        if (request.uri.path == '/api/') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'schema/view/',
          );
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.close();
        }
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test(
      'SessionManagerImpl rejects untrusted certificate by default',
      () async {
        final store = CertificateTrustStoreImpl.inMemory();
        final sessionManager = SessionManagerImpl([], store);

        expect(
          () => sessionManager.client.get(serverAddress),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'isPaperlessServerReachable returns untrustedServerCertificate, then reachable after trust',
      () async {
        final store = CertificateTrustStoreImpl.inMemory();
        final service = ConnectivityStatusServiceImpl(
          _FakeConnectivity(),
          store,
        );

        // 1. First probe without trusting: should report untrustedServerCertificate
        final status1 = await service.isPaperlessServerReachable(serverAddress);
        expect(status1, ReachabilityStatus.untrustedServerCertificate);
        expect(service.lastUntrustedCertificate, isNotNull);
        final untrustedCert = service.lastUntrustedCertificate!;
        expect(untrustedCert.host, server.address.address);
        expect(untrustedCert.port, server.port);
        expect(untrustedCert.fingerprint, isNotEmpty);

        // 2. Trust the certificate in the store
        await store.trustCertificate(untrustedCert);
        expect(
          store.isCertificateTrusted(
            untrustedCert.host,
            untrustedCert.fingerprint,
          ),
          isTrue,
        );

        // 3. Second probe: should succeed and report reachable
        final status2 = await service.isPaperlessServerReachable(serverAddress);
        expect(status2, ReachabilityStatus.reachable);
      },
    );

    test(
      'ServerConnectionCubit handles untrusted certificate and trustCertificateAndRetry',
      () async {
        final store = CertificateTrustStoreImpl.inMemory();
        final service = ConnectivityStatusServiceImpl(
          _FakeConnectivity(),
          store,
        );
        final cubit = ServerConnectionCubit(service, store);

        // Check reachability
        final future1 = expectLater(
          cubit.stream,
          emitsInOrder([
            isA<ServerConnectionCheckingReachability>(),
            predicate<ServerConnectionUntrustedCertificate>(
              (state) =>
                  state.address == serverAddress &&
                  state.certificate.host == server.address.address,
            ),
          ]),
        );

        cubit.checkReachability(address: serverAddress);
        await future1;

        expect(cubit.state, isA<ServerConnectionUntrustedCertificate>());
        final untrustedState =
            cubit.state as ServerConnectionUntrustedCertificate;

        // Now trust certificate and retry
        final future2 = expectLater(
          cubit.stream,
          emitsInOrder([
            isA<ServerConnectionCheckingReachability>(),
            predicate<ServerConnectionSuccess>(
              (state) => state.serverUrl == serverAddress,
            ),
          ]),
        );

        await cubit.trustCertificateAndRetry(
          certificate: untrustedState.certificate,
          address: serverAddress,
        );
        await future2;

        expect(cubit.state, isA<ServerConnectionSuccess>());
      },
    );
  });
}
