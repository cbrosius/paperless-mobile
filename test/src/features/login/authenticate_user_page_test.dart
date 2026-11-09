import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/store/local_store.dart';
import 'package:paperless_mobile/features/login/authenticate_user/cubit/authenticate_user_cubit.dart';
import 'package:paperless_mobile/features/login/authenticate_user/view/authenticate_user_page.dart';
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

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Paperless Mobile',
      packageName: 'de.astubenbord.paperless_mobile',
      version: '3.2.1',
      buildNumber: '405',
      buildSignature: '',
    );
    packageInfo = await PackageInfo.fromPlatform();
  });

  setUp(() {
    storage = MockHydratedStorage();
    HydratedBloc.storage = storage;
  });

  Widget buildSubject({Size size = const Size(360, 500)}) {
    final localStore = LocalStore('en');
    final cubit = AuthenticateUserCubit();

    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<LocalStore>.value(value: localStore),
            BlocProvider<AuthenticateUserCubit>.value(value: cubit),
          ],
          child: const AuthenticateUserPage(
            serverUrl: 'https://demo.paperless.test',
          ),
        ),
      ),
    );
  }

  group('AuthenticateUserPage (#384)', () {
    testWidgets(
      'contains a SingleChildScrollView and avoids rigid overflow on small screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildSubject(size: const Size(360, 500)));
        await tester.pumpAndSettle();

        // Should have SingleChildScrollView for scrollability
        final scrollViewFinder = find.descendant(
          of: find.byType(AuthenticateUserPage),
          matching: find.byType(SingleChildScrollView),
        );
        expect(
          scrollViewFinder,
          findsOneWidget,
          reason: 'Login page must be scrollable (#384)',
        );

        // Scaffold should resize to avoid bottom inset (keyboard)
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.resizeToAvoidBottomInset,
          isTrue,
          reason: 'Scaffold must resize when keyboard appears (#384)',
        );

        // User must be able to scroll down to view submit and edit buttons
        await tester.drag(scrollViewFinder, const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(find.text('Sign In'), findsOneWidget);
      },
    );
  });
}
