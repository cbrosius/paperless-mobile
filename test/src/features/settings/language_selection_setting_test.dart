import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:paperless_mobile/core/store/local_store.dart';
import 'package:paperless_mobile/features/settings/view/widgets/language_selection_setting.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class MockHydratedStorage extends Fake implements HydratedStorage {
  @override
  dynamic read(String key) => null;

  @override
  Future<void> write(String key, dynamic value) async {}

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;

  setUp(() {
    storage = MockHydratedStorage();
    HydratedBloc.storage = storage;
  });

  Widget createSubject(String preferredLocaleSubtag) {
    final localStore = LocalStore(preferredLocaleSubtag);
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: BlocProvider<LocalStore>.value(
          value: localStore,
          child: const LanguageSelectionSetting(),
        ),
      ),
    );
  }

  group('LanguageSelectionSetting (#403)', () {
    testWidgets('renders properly with standard language tag "en"', (
      tester,
    ) async {
      await tester.pumpWidget(createSubject('en'));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageSelectionSetting), findsOneWidget);
      expect(find.text('English (US)'), findsOneWidget);
    });

    testWidgets(
      'renders without throwing when preferredLocaleSubtag is regional e.g. "en_US"',
      (tester) async {
        await tester.pumpWidget(createSubject('en_US'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(LanguageSelectionSetting), findsOneWidget);
        expect(find.text('English (US)'), findsOneWidget);
      },
    );

    testWidgets(
      'renders without throwing when preferredLocaleSubtag is regional e.g. "nl_NL"',
      (tester) async {
        await tester.pumpWidget(createSubject('nl_NL'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(LanguageSelectionSetting), findsOneWidget);
        expect(find.text('Nederlands'), findsOneWidget);
      },
    );

    testWidgets(
      'renders fallback without throwing when preferredLocaleSubtag is unknown',
      (tester) async {
        await tester.pumpWidget(createSubject('unknown_LANG'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(LanguageSelectionSetting), findsOneWidget);
      },
    );
  });
}
