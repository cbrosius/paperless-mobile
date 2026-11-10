import 'dart:io';
import 'package:crypto/crypto.dart';

class ServerCertificate {
  final String fingerprint; // SHA-256 fingerprint in lowercase hex
  final String host;
  final int port;
  final String subject;
  final String issuer;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DateTime trustedAt;

  const ServerCertificate({
    required this.fingerprint,
    required this.host,
    this.port = 443,
    this.subject = '',
    this.issuer = '',
    this.validFrom,
    this.validTo,
    required this.trustedAt,
  });

  factory ServerCertificate.fromX509({
    required X509Certificate cert,
    required String host,
    int port = 443,
    DateTime? trustedAt,
  }) {
    final sha256Hex = sha256.convert(cert.der).toString().toLowerCase();
    return ServerCertificate(
      fingerprint: sha256Hex,
      host: host.toLowerCase(),
      port: port,
      subject: cert.subject,
      issuer: cert.issuer,
      validFrom: cert.startValidity,
      validTo: cert.endValidity,
      trustedAt: trustedAt ?? DateTime.now(),
    );
  }

  String get formattedFingerprint {
    final clean = fingerprint.replaceAll(':', '').toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(
        clean.substring(i, (i + 2 <= clean.length) ? i + 2 : clean.length),
      );
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'host': host,
    'port': port,
    'subject': subject,
    'issuer': issuer,
    'validFrom': validFrom?.toIso8601String(),
    'validTo': validTo?.toIso8601String(),
    'trustedAt': trustedAt.toIso8601String(),
  };

  factory ServerCertificate.fromJson(Map<String, dynamic> json) =>
      ServerCertificate(
        fingerprint: (json['fingerprint'] as String).toLowerCase(),
        host: (json['host'] as String).toLowerCase(),
        port: (json['port'] as num?)?.toInt() ?? 443,
        subject: json['subject'] as String? ?? '',
        issuer: json['issuer'] as String? ?? '',
        validFrom: json['validFrom'] != null
            ? DateTime.tryParse(json['validFrom'] as String)
            : null,
        validTo: json['validTo'] != null
            ? DateTime.tryParse(json['validTo'] as String)
            : null,
        trustedAt: json['trustedAt'] != null
            ? DateTime.tryParse(json['trustedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerCertificate &&
          runtimeType == other.runtimeType &&
          fingerprint.toLowerCase() == other.fingerprint.toLowerCase() &&
          host.toLowerCase() == other.host.toLowerCase() &&
          port == other.port;

  @override
  int get hashCode =>
      Object.hash(fingerprint.toLowerCase(), host.toLowerCase(), port);
}
