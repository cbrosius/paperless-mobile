import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/global/os_error_codes.dart';
import 'package:paperless_mobile/core/interceptor/server_reachability_error_interceptor.dart';
import 'package:paperless_mobile/core/security/certificate_trust_store.dart';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:paperless_mobile/core/security/session_manager.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/model/client_certificate.dart';
import 'package:paperless_mobile/features/login/model/reachability_status.dart';
import 'package:paperless_mobile/features/login/server_connection/model/header_entry.dart';
import 'package:rxdart/subjects.dart';

abstract class ConnectivityStatusService {
  Future<bool> isConnectedToInternet();
  Future<bool> isServerReachable(String serverAddress);
  Stream<bool> connectivityChanges();
  ServerCertificate? get lastUntrustedCertificate;
  Future<ReachabilityStatus> isPaperlessServerReachable(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]);
  Future<int> getPaperlessServerApiVersion(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]);
}

class ConnectivityStatusServiceImpl implements ConnectivityStatusService {
  final Connectivity _connectivity;
  final CertificateTrustStore? _certificateTrustStore;
  final BehaviorSubject<bool> _connectivityState$ = BehaviorSubject();
  ServerCertificate? _lastUntrustedCertificate;

  @override
  ServerCertificate? get lastUntrustedCertificate => _lastUntrustedCertificate;

  ConnectivityStatusServiceImpl(
    this._connectivity, [
    this._certificateTrustStore,
  ]) {
    _connectivityState$.addStream(
      _connectivity.onConnectivityChanged
          .map(_hasActiveInternetConnection)
          .asBroadcastStream(),
    );
  }

  @override
  Stream<bool> connectivityChanges() {
    return _connectivityState$.asBroadcastStream();
  }

  @override
  Future<bool> isConnectedToInternet() async {
    return _hasActiveInternetConnection(
      await (Connectivity().checkConnectivity()),
    );
  }

  @override
  Future<bool> isServerReachable(String serverAddress) async {
    try {
      var uri = Uri.parse(serverAddress);
      final result = await InternetAddress.lookup(uri.host);
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      } else {
        return false;
      }
    } on SocketException catch (_) {
      return false;
    }
  }

  bool _hasActiveInternetConnection(List<ConnectivityResult> conns) {
    bool isActiveInternetConnection(ConnectivityResult conn) {
      switch (conn) {
        case ConnectivityResult.wifi:
        case ConnectivityResult.ethernet:
        case ConnectivityResult.mobile:
        case ConnectivityResult.vpn:
          return true;
        default:
          return false;
      }
    }

    return conns.any(isActiveInternetConnection);
  }

  @override
  Future<ReachabilityStatus> isPaperlessServerReachable(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]) async {
    if (!RegExp(r"^https?://.*").hasMatch(serverAddress)) {
      return ReachabilityStatus.unknown;
    }
    _lastUntrustedCertificate = null;
    X509Certificate? capturedCert;
    String? certHost;
    int? certPort;

    try {
      SessionManager manager =
          SessionManagerImpl(
            [ServerReachabilityErrorInterceptor()],
            _certificateTrustStore,
            (X509Certificate cert, String host, int port) {
              final effectiveStore =
                  _certificateTrustStore ??
                  SessionManagerImpl.defaultTrustStore;
              final fingerprint = sha256
                  .convert(cert.der)
                  .toString()
                  .toLowerCase();
              if (effectiveStore != null &&
                  effectiveStore.isCertificateTrusted(host, fingerprint)) {
                return true;
              }
              capturedCert = cert;
              certHost = host;
              certPort = port;
              return false;
            },
          )..updateSettings(
            baseUrl: serverAddress,
            clientCertificate: clientCertificate,
            additionalHeaders: additionalHeaders,
          );

      final response = await manager.client.head(
        '/api/',
        options: Options(
          receiveTimeout: 5.seconds,
          sendTimeout: 5.seconds,
          followRedirects: false,
          validateStatus: (status) => status == HttpStatus.found,
        ),
      );
      if (response.statusCode == HttpStatus.found) {
        return ReachabilityStatus.reachable;
      }
      logger.fw(
        'Unexpected response status code: ${response.statusCode}',
        className: runtimeType.toString(),
        methodName: 'isPaperlessServerReachable',
        error: {
          'statusCode': response.statusCode,
          'data': response.data.toString(),
        },
      );
      return ReachabilityStatus.notReachable;
    } on DioException catch (error) {
      if (capturedCert != null) {
        final uri = Uri.tryParse(serverAddress);
        _lastUntrustedCertificate = ServerCertificate.fromX509(
          cert: capturedCert!,
          host: certHost ?? uri?.host ?? serverAddress,
          port: certPort ?? uri?.port ?? (uri?.scheme == 'https' ? 443 : 80),
        );
        logger.fw(
          'Encountered untrusted server certificate: ${_lastUntrustedCertificate?.formattedFingerprint}',
          className: runtimeType.toString(),
          methodName: 'isPaperlessServerReachable',
        );
        return ReachabilityStatus.untrustedServerCertificate;
      }
      if (error.type == DioExceptionType.unknown &&
          error.error is ReachabilityStatus) {
        logger.fw(
          'Could not reach server: ${error.error}',
          className: runtimeType.toString(),
          methodName: 'isPaperlessServerReachable',
          error: {
            'statusCode': error.response?.statusCode,
            'data': error.response?.data.toString(),
          },
        );
        return error.error as ReachabilityStatus;
      }
    } on TlsException catch (error) {
      if (capturedCert != null) {
        final uri = Uri.tryParse(serverAddress);
        _lastUntrustedCertificate = ServerCertificate.fromX509(
          cert: capturedCert!,
          host: certHost ?? uri?.host ?? serverAddress,
          port: certPort ?? uri?.port ?? 443,
        );
        return ReachabilityStatus.untrustedServerCertificate;
      }
      final code = error.osError?.errorCode;
      if (code == OsErrorCodes.invalidClientCertConfig.code ||
          clientCertificate != null) {
        // Missing or incorrect client cert passphrase or certificate configuration error
        logger.fw(
          'Client certificate configuration error (TLS): ${error.message}',
          className: runtimeType.toString(),
          methodName: 'isPaperlessServerReachable',
        );
        return ReachabilityStatus.invalidClientCertificateConfiguration;
      }
      logger.fw(
        'Could not reach server due to an SSL/TLS issue: ${error.message}',
        className: runtimeType.toString(),
        methodName: 'isPaperlessServerReachable',
      );
    } on ArgumentError catch (error) {
      if (clientCertificate != null) {
        logger.fw(
          'Client certificate argument error: ${error.message}',
          className: runtimeType.toString(),
          methodName: 'isPaperlessServerReachable',
        );
        return ReachabilityStatus.invalidClientCertificateConfiguration;
      }
    } on FormatException catch (error) {
      if (clientCertificate != null) {
        logger.fw(
          'Client certificate format error: ${error.message}',
          className: runtimeType.toString(),
          methodName: 'isPaperlessServerReachable',
        );
        return ReachabilityStatus.invalidClientCertificateConfiguration;
      }
    }
    return ReachabilityStatus.notReachable;
  }

  @override
  Future<int> getPaperlessServerApiVersion(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]) async {
    try {
      SessionManager manager =
          SessionManagerImpl(const [], _certificateTrustStore)..updateSettings(
            baseUrl: serverAddress,
            clientCertificate: clientCertificate,
            additionalHeaders: additionalHeaders,
          );

      int apiVersion = await manager.getApiVersion();

      if (apiVersion > latestSupportedApiVersion) {
        logger.fw(
          'Server API version $apiVersion is newer than the latest supported version $latestSupportedApiVersion. Defaulting to latest supported version.',
          className: runtimeType.toString(),
          methodName: 'getPaperlessServerApiVersion',
        );
        apiVersion = latestSupportedApiVersion;
      }
      return apiVersion;
    } on TlsException catch (error) {
      logger.fw(
        'TLS exception while fetching API version: ${error.message}',
        className: runtimeType.toString(),
        methodName: 'getPaperlessServerApiVersion',
      );
      return minSupportedApiVersion;
    } on ArgumentError catch (error) {
      logger.fw(
        'Argument error while configuring client certificate for API version: ${error.message}',
        className: runtimeType.toString(),
        methodName: 'getPaperlessServerApiVersion',
      );
      return minSupportedApiVersion;
    } on FormatException catch (error) {
      logger.fw(
        'Format exception while configuring client certificate for API version: ${error.message}',
        className: runtimeType.toString(),
        methodName: 'getPaperlessServerApiVersion',
      );
      return minSupportedApiVersion;
    } catch (error) {
      logger.fw(
        'Unexpected error while fetching API version: $error',
        className: runtimeType.toString(),
        methodName: 'getPaperlessServerApiVersion',
      );
      return minSupportedApiVersion;
    }
  }
}

class ConnectivityStatusServiceMock implements ConnectivityStatusService {
  final bool isConnected;

  ConnectivityStatusServiceMock(this.isConnected);
  @override
  ServerCertificate? get lastUntrustedCertificate => null;
  @override
  Stream<bool> connectivityChanges() {
    return Stream.value(isConnected);
  }

  @override
  Future<bool> isConnectedToInternet() async {
    return isConnected;
  }

  @override
  Future<ReachabilityStatus> isPaperlessServerReachable(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]) async {
    return isConnected
        ? ReachabilityStatus.reachable
        : ReachabilityStatus.notReachable;
  }

  @override
  Future<bool> isServerReachable(String serverAddress) async {
    return isConnected;
  }

  @override
  Future<int> getPaperlessServerApiVersion(
    String serverAddress, [
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  ]) {
    return Future.value(9);
  }
}
