import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:paperless_mobile/core/security/certificate_trust_store.dart';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/model/client_certificate.dart';
import 'package:paperless_mobile/features/login/model/reachability_status.dart';
import 'package:paperless_mobile/features/login/server_connection/model/header_entry.dart';

part 'server_connection_state.dart';

class ServerConnectionCubit extends Cubit<ServerConnectionState> {
  final ConnectivityStatusService _connectivityStatusService;
  final CertificateTrustStore? _certificateTrustStore;

  ServerConnectionCubit(
    this._connectivityStatusService, [
    this._certificateTrustStore,
  ]) : super(const ServerConnectionInitial());

  void reset() {
    emit(const ServerConnectionInitial());
  }

  void checkReachability({
    required String address,
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  }) async {
    emit(ServerConnectionCheckingReachability(address: address));
    try {
      final status = await _connectivityStatusService
          .isPaperlessServerReachable(
            address,
            clientCertificate,
            additionalHeaders,
          );
      if (status == ReachabilityStatus.reachable) {
        emit(
          ServerConnectionSuccess(
            serverUrl: address,
            clientCertificate: clientCertificate,
            additionalHeaders: additionalHeaders,
          ),
        );
      } else if (status == ReachabilityStatus.untrustedServerCertificate &&
          _connectivityStatusService.lastUntrustedCertificate != null) {
        emit(
          ServerConnectionUntrustedCertificate(
            address: address,
            certificate: _connectivityStatusService.lastUntrustedCertificate!,
            clientCertificate: clientCertificate,
            additionalHeaders: additionalHeaders,
          ),
        );
      } else {
        logger.fw(
          'Server is not reachable',
          className: runtimeType.toString(),
          methodName: 'checkReachability',
          error: {'status': status.toString()},
        );
        emit(ServerConnectionUnreachable(address: address, status: status));
      }
    } catch (error, stackTrace) {
      logger.fe(
        'Error while checking server reachability',
        className: runtimeType.toString(),
        methodName: 'checkReachability',
        error: error,
        stackTrace: stackTrace,
      );
      final fallbackStatus =
          (error is ArgumentError ||
                  error is TlsException ||
                  error is FormatException) &&
              clientCertificate != null
          ? ReachabilityStatus.invalidClientCertificateConfiguration
          : ReachabilityStatus.notReachable;
      emit(
        ServerConnectionUnreachable(address: address, status: fallbackStatus),
      );
    }
  }

  Future<void> trustCertificateAndRetry({
    required ServerCertificate certificate,
    required String address,
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
  }) async {
    final trustStore =
        _certificateTrustStore ?? SessionManagerImpl.defaultTrustStore;
    if (trustStore != null) {
      await trustStore.trustCertificate(certificate);
    }
    checkReachability(
      address: address,
      clientCertificate: clientCertificate,
      additionalHeaders: additionalHeaders,
    );
  }
}
