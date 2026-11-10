import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class UntrustedCertificateDialog extends StatelessWidget {
  final ServerCertificate certificate;
  final VoidCallback onTrust;
  final VoidCallback? onCancel;

  const UntrustedCertificateDialog({
    super.key,
    required this.certificate,
    required this.onTrust,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: errorColor, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.of(context)!.untrustedCertificate,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context)!.untrustedCertificateWarning(certificate.host),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      context,
                      'Host',
                      '${certificate.host}:${certificate.port}',
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      context,
                      S.of(context)!.sha256Fingerprint,
                      certificate.formattedFingerprint,
                      isMonospace: true,
                      canCopy: true,
                    ),
                    if (certificate.issuer.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        context,
                        S.of(context)!.certificateIssuer,
                        certificate.issuer,
                      ),
                    ],
                    if (certificate.validTo != null) ...[
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        context,
                        S.of(context)!.certificateValidity,
                        dateFormat.format(certificate.validTo!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel?.call();
          },
          child: Text(S.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onTrust();
          },
          child: Text(S.of(context)!.trustCertificate),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
    bool canCopy = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (canCopy)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of(context)!.copiedToClipboard(label)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Icon(
                  Icons.copy,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: isMonospace
              ? theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w500,
                )
              : theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
