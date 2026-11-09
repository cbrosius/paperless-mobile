import 'package:flutter/widgets.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

/// Locales supported by the app, combining standard locales generated from arb files
/// and regional variants explicitly handled (e.g. British English).
const List<Locale> appSupportedLocales = [
  ...S.supportedLocales,
  Locale('en', 'GB'),
];

/// Parses a locale identifier string (e.g. "en_GB", "en-US", "de") into a [Locale].
///
/// Falls back to `Locale('en')` if [code] is null or empty.
Locale parseLocale(String? code) {
  if (code == null || code.trim().isEmpty) {
    return const Locale('en');
  }
  final cleanCode = code.trim().replaceAll('-', '_');
  final parts = cleanCode.split('_');
  final languageCode = parts[0];
  final countryCode = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  return Locale(languageCode, countryCode);
}

/// Resolves a locale (given as a [Locale] or [String]) to a [Locale] supported by [S.delegate].
///
/// If a regional locale like `Locale('en_GB')` or string `'en_GB'` is provided,
/// it normalizes it so that the languageCode is `'en'` (which [S.delegate] supports).
/// If the locale is completely unsupported, it falls back to `const Locale('en')`.
Locale resolveSupportedLocale(dynamic localeOrString) {
  Locale target;
  if (localeOrString is Locale) {
    target = localeOrString;
  } else if (localeOrString is String) {
    target = parseLocale(localeOrString);
  } else {
    return const Locale('en');
  }

  // Handle case where Locale was constructed with compound tag in languageCode (e.g. Locale('en_GB'))
  if (target.languageCode.contains(RegExp(r'[-_]'))) {
    final parsed = parseLocale(target.languageCode);
    target = Locale(
      parsed.languageCode,
      target.countryCode ?? parsed.countryCode,
    );
  }

  // 1. Direct match with S.delegate
  if (S.delegate.isSupported(target)) {
    return target;
  }

  // 2. Base language match (e.g. 'de_AT' -> 'de')
  final baseLocale = Locale(target.languageCode);
  if (S.delegate.isSupported(baseLocale)) {
    return baseLocale;
  }

  // 3. Fallback to English
  return const Locale('en');
}

/// Safely loads [S] localizations for the given [localeOrString].
///
/// This avoids [FlutterError] crashes from [S.delegate.load] when an unsupported
/// or compound locale tag (such as "en_GB") is passed.
Future<S> loadAppLocalizations([dynamic localeOrString]) async {
  final resolved = resolveSupportedLocale(localeOrString);
  try {
    return await S.delegate.load(resolved);
  } catch (error, stackTrace) {
    logger.fw(
      'Failed to load localizations for "$localeOrString" (resolved to "$resolved"). Falling back to English.',
      error: error,
      stackTrace: stackTrace,
    );
    return await S.delegate.load(const Locale('en'));
  }
}
