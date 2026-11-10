import 'dart:convert';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CertificateTrustStore {
  bool isCertificateTrusted(String host, String fingerprint);
  Future<void> trustCertificate(ServerCertificate certificate);
  Future<void> untrustCertificate(String host, String fingerprint);
  List<ServerCertificate> getTrustedCertificates();
}

class CertificateTrustStoreImpl implements CertificateTrustStore {
  static const _spKey = 'trusted_server_certificates_v1';
  final SharedPreferences? _prefs;
  final Map<String, Map<String, ServerCertificate>> _certificatesByHost = {};

  CertificateTrustStoreImpl([this._prefs]) {
    _loadFromPrefs();
  }

  factory CertificateTrustStoreImpl.inMemory([
    List<ServerCertificate> initialCertificates = const [],
  ]) {
    final store = CertificateTrustStoreImpl(null);
    for (final cert in initialCertificates) {
      final hostKey = cert.host.toLowerCase();
      final fpKey = cert.fingerprint.toLowerCase();
      store._certificatesByHost.putIfAbsent(hostKey, () => {})[fpKey] = cert;
    }
    return store;
  }

  static Future<CertificateTrustStoreImpl> init() async {
    final prefs = await SharedPreferences.getInstance();
    return CertificateTrustStoreImpl(prefs);
  }

  void _loadFromPrefs() {
    if (_prefs == null) return;
    final jsonList = _prefs.getStringList(_spKey);
    if (jsonList == null) return;

    for (final rawJson in jsonList) {
      try {
        final map = jsonDecode(rawJson) as Map<String, dynamic>;
        final cert = ServerCertificate.fromJson(map);
        final hostKey = cert.host.toLowerCase();
        final fpKey = cert.fingerprint.toLowerCase();
        _certificatesByHost.putIfAbsent(hostKey, () => {})[fpKey] = cert;
      } catch (_) {
        // Skip malformed entries
      }
    }
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    final list = <String>[];
    for (final map in _certificatesByHost.values) {
      for (final cert in map.values) {
        list.add(jsonEncode(cert.toJson()));
      }
    }
    await _prefs.setStringList(_spKey, list);
  }

  @override
  bool isCertificateTrusted(String host, String fingerprint) {
    final hostKey = host.toLowerCase();
    final fpKey = fingerprint.toLowerCase();
    return _certificatesByHost[hostKey]?.containsKey(fpKey) ?? false;
  }

  @override
  Future<void> trustCertificate(ServerCertificate certificate) async {
    final hostKey = certificate.host.toLowerCase();
    final fpKey = certificate.fingerprint.toLowerCase();
    _certificatesByHost.putIfAbsent(hostKey, () => {})[fpKey] = certificate;
    await _persist();
  }

  @override
  Future<void> untrustCertificate(String host, String fingerprint) async {
    final hostKey = host.toLowerCase();
    final fpKey = fingerprint.toLowerCase();
    _certificatesByHost[hostKey]?.remove(fpKey);
    if (_certificatesByHost[hostKey]?.isEmpty ?? false) {
      _certificatesByHost.remove(hostKey);
    }
    await _persist();
  }

  @override
  List<ServerCertificate> getTrustedCertificates() {
    final result = <ServerCertificate>[];
    for (final map in _certificatesByHost.values) {
      result.addAll(map.values);
    }
    return List.unmodifiable(result);
  }
}
