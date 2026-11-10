import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:paperless_mobile/core/security/certificate_trust_store.dart';
import 'package:paperless_mobile/core/security/server_certificate.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class TrustedCertificatesSetting extends StatelessWidget {
  const TrustedCertificatesSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.security),
      title: Text(S.of(context)!.trustedCertificates),
      subtitle: Text(S.of(context)!.manageTrustedCertificates),
      onTap: () {
        CertificateTrustStore? store;
        try {
          store = context.read<CertificateTrustStore>();
        } catch (_) {
          store = SessionManagerImpl.defaultTrustStore;
        }
        if (store != null) {
          _showCertificatesDialog(context, store);
        }
      },
    );
  }

  void _showCertificatesDialog(
    BuildContext context,
    CertificateTrustStore store,
  ) {
    showDialog(
      context: context,
      builder: (context) => _TrustedCertificatesDialog(store: store),
    );
  }
}

class _TrustedCertificatesDialog extends StatefulWidget {
  final CertificateTrustStore store;
  const _TrustedCertificatesDialog({required this.store});

  @override
  State<_TrustedCertificatesDialog> createState() =>
      _TrustedCertificatesDialogState();
}

class _TrustedCertificatesDialogState
    extends State<_TrustedCertificatesDialog> {
  late List<ServerCertificate> _certificates;

  @override
  void initState() {
    super.initState();
    _certificates = widget.store.getTrustedCertificates();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    );

    return AlertDialog(
      title: Text(S.of(context)!.trustedCertificates),
      content: SizedBox(
        width: double.maxFinite,
        child: _certificates.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Text(
                  S.of(context)!.noTrustedCertificates,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _certificates.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final cert = _certificates[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      cert.host,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          cert.formattedFingerprint,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'RobotoMono',
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${S.of(context)!.trustedAt}: ${dateFormat.format(cert.trustedAt)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                      ),
                      onPressed: () async {
                        await widget.store.untrustCertificate(
                          cert.host,
                          cert.fingerprint,
                        );
                        if (mounted) {
                          setState(() {
                            _certificates = widget.store
                                .getTrustedCertificates();
                          });
                        }
                      },
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context)!.close),
        ),
      ],
    );
  }
}
