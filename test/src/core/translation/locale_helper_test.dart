import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/core/translation/locale_helper.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart'
    as app_logger;
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

void main() {
  setUpAll(() {
    app_logger.logger = Logger(level: Level.off);
  });

  group('locale_helper parseLocale', () {
    test('handles various string formats and edge cases', () {
      expect(parseLocale('en_GB'), const Locale('en', 'GB'));
      expect(parseLocale('en-GB'), const Locale('en', 'GB'));
      expect(parseLocale('en'), const Locale('en'));
      expect(parseLocale('de_DE'), const Locale('de', 'DE'));
      expect(parseLocale('de-DE'), const Locale('de', 'DE'));
      expect(parseLocale(''), const Locale('en'));
      expect(parseLocale(null), const Locale('en'));
      expect(parseLocale('   '), const Locale('en'));
    });
  });

  group('locale_helper resolveSupportedLocale', () {
    test('resolves supported and unsupported locales correctly', () {
      // Direct string format
      expect(resolveSupportedLocale('en_GB'), const Locale('en', 'GB'));
      expect(resolveSupportedLocale('en-GB'), const Locale('en', 'GB'));

      // Locale object with 'en_GB' as languageCode (reproduces the exact root cause of #375)
      expect(
        resolveSupportedLocale(const Locale('en_GB')),
        const Locale('en', 'GB'),
      );

      // Supported base languages
      expect(resolveSupportedLocale('de'), const Locale('de'));
      expect(resolveSupportedLocale('de_DE'), const Locale('de', 'DE'));
      expect(resolveSupportedLocale('fr'), const Locale('fr'));

      // Unsupported language falls back to English
      expect(resolveSupportedLocale('zh_CN'), const Locale('en'));
      expect(resolveSupportedLocale(const Locale('zh')), const Locale('en'));
      expect(resolveSupportedLocale('unknown_xyz'), const Locale('en'));
      expect(resolveSupportedLocale(null), const Locale('en'));
      expect(resolveSupportedLocale(''), const Locale('en'));
    });
  });

  group('locale_helper loadAppLocalizations (#375 fix)', () {
    test(
      'reproduces issue #375: raw S.delegate.load fails on Locale("en_GB")',
      () {
        // Direct call to S.delegate.load with compound tag in languageCode throws FlutterError:
        // "S.delegate failed to load unsupported locale "en_GB"..."
        expect(
          () => S.delegate.load(const Locale('en_GB')),
          throwsA(isA<FlutterError>()),
        );
      },
    );

    test(
      'loadAppLocalizations loads "en_GB" string safely without error',
      () async {
        final tr = await loadAppLocalizations('en_GB');
        expect(tr, isNotNull);
        expect(tr.verifyYourIdentity, 'Verify your identity');
        expect(tr.restoringSession, 'Restoring session...');
        expect(tr.notificationDownloadComplete, 'Download complete');
      },
    );

    test(
      'loadAppLocalizations loads Locale("en_GB") safely without error',
      () async {
        final tr = await loadAppLocalizations(const Locale('en_GB'));
        expect(tr, isNotNull);
        expect(tr.verifyYourIdentity, 'Verify your identity');
        expect(tr.restoringSession, 'Restoring session...');
      },
    );

    test('loadAppLocalizations loads "en-GB" (hyphenated) safely', () async {
      final tr = await loadAppLocalizations('en-GB');
      expect(tr, isNotNull);
      expect(tr.verifyYourIdentity, 'Verify your identity');
    });

    test(
      'loadAppLocalizations safely handles unsupported locales with fallback to English',
      () async {
        final tr = await loadAppLocalizations('unsupported_locale_xyz');
        expect(tr, isNotNull);
        expect(tr.verifyYourIdentity, 'Verify your identity');
      },
    );

    test('loadAppLocalizations safely handles null or empty input', () async {
      final trNull = await loadAppLocalizations(null);
      expect(trNull.verifyYourIdentity, 'Verify your identity');

      final trEmpty = await loadAppLocalizations('');
      expect(trEmpty.verifyYourIdentity, 'Verify your identity');
    });

    test('loadAppLocalizations loads German localizations correctly', () async {
      final tr = await loadAppLocalizations('de');
      expect(tr, isNotNull);
      expect(tr.verifyYourIdentity, 'Verifiziere deine Identität');
      expect(tr.restoringSession, 'Sitzung wird wiederhergestellt...');
    });
  });

  group('appSupportedLocales', () {
    test('contains all S.supportedLocales plus British English', () {
      for (final locale in S.supportedLocales) {
        expect(appSupportedLocales.contains(locale), isTrue);
      }
      expect(appSupportedLocales.contains(const Locale('en', 'GB')), isTrue);
    });
  });
}
