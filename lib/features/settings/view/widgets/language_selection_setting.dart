import 'package:flutter/material.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/store/bloc/global_settings_builder.dart';
import 'package:paperless_mobile/core/store/slices/global_settings.dart';
import 'package:paperless_mobile/features/settings/view/widgets/radio_settings_dialog.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class LanguageSelectionSetting extends StatefulWidget {
  const LanguageSelectionSetting({super.key});

  @override
  State<LanguageSelectionSetting> createState() =>
      _LanguageSelectionSettingState();
}

class _LanguageSelectionSettingState extends State<LanguageSelectionSetting> {
  static const _languageOptions = {
    'en': LanguageOption('English (US)', true),
    'en_GB': LanguageOption('English (GB)', true),
    'de': LanguageOption('Deutsch', true),
    'es': LanguageOption("Español", true),
    'fr': LanguageOption('Français', true),
    'cs': LanguageOption('Česky', true),
    'tr': LanguageOption('Türkçe', true),
    'pl': LanguageOption('Polska', true),
    'ca': LanguageOption('Català', true),
    'ru': LanguageOption('Русский', true),
    'it': LanguageOption('Italiano', true),
    'ar': LanguageOption('العربية', false),
    'pt': LanguageOption('Português', false),
    'ro': LanguageOption('Română', false),
    'sl': LanguageOption('Slovenščina', false),
    'nl': LanguageOption('Nederlands', false),
  };

  @override
  Widget build(BuildContext context) {
    final localStore = context.localStore;
    return GlobalSettingsBuilder(
      builder: (context, settings) {
        final currentOption =
            _languageOptions[settings.preferredLocaleSubtag] ??
            _languageOptions[settings.preferredLocaleSubtag
                .split(RegExp(r'[-_]'))
                .first] ??
            _languageOptions['en']!;
        final initialValue =
            _languageOptions.containsKey(settings.preferredLocaleSubtag)
            ? settings.preferredLocaleSubtag
            : (_languageOptions.containsKey(
                    settings.preferredLocaleSubtag.split(RegExp(r'[-_]')).first,
                  )
                  ? settings.preferredLocaleSubtag.split(RegExp(r'[-_]')).first
                  : 'en');

        return ListTile(
          title: Text(S.of(context)!.language),
          subtitle: Text(currentOption.name),
          onTap: () =>
              showDialog<String>(
                useRootNavigator: false,
                context: context,
                builder: (_) => RadioSettingsDialog<String>(
                  // footer: const Text(
                  //   "* Not fully translated yet. Some words may be displayed in English!",
                  // ),
                  titleText: S.of(context)!.language,
                  options: [
                    for (var language in _languageOptions.entries)
                      RadioOption(
                        value: language.key,
                        label:
                            language.value.name +
                            (language.value.isComplete ? '' : '*'),
                      ),
                  ],
                  initialValue: initialValue,
                ),
              ).then((value) {
                if (value != null) {
                  localStore.updateGlobalSettings(
                    (state) => state.copyWith(preferredLocaleSubtag: value),
                  );
                }
              }),
        );
      },
    );
  }
}

class LanguageOption {
  final String name;
  final bool isComplete;

  const LanguageOption(this.name, this.isComplete);
}
