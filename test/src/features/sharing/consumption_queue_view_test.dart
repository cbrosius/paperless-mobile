import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/store/slices/local_user_account.dart';
import 'package:paperless_mobile/core/store/slices/user_profile.dart';
import 'package:paperless_mobile/features/sharing/cubit/receive_share_cubit.dart';
import 'package:paperless_mobile/features/sharing/view/consumption_queue_view.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late File sampleFile;

  // Minimal valid 1x1 PNG image so FileThumbnail renders with its 75px width.
  const pngBytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
    0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
    0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
    0x0D, 0x0A, 0x2D, 0xB4,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
    0xAE, 0x42, 0x60, 0x82,
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('consumption_queue_test_');
    sampleFile = File('${tempDir.path}/facture_2026_11.png');
    await sampleFile.writeAsBytes(pngBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestApp(ConsumptionChangeNotifier notifier, Locale locale) {
    return MultiProvider(
      providers: [
        Provider.value(
          value: LocalUserAccount(
            appUserId: 'test@example.com',
            serverUrl: 'https://example.com',
            apiVersion: 9,
            profile: UserProfile(
              profile: Profile(),
              uiSettings: UiSettingsView(
                user: UiSettingsViewUser(id: 1, username: 'test'),
              ),
            ),
          ),
        ),
        ChangeNotifierProvider<ConsumptionChangeNotifier>.value(
          value: notifier,
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: const ConsumptionQueueView(),
      ),
    );
  }

  testWidgets(
    'does not overflow action buttons in French locale on narrow screens (#717)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final notifier = ConsumptionChangeNotifier()..pendingFiles = [sampleFile];

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(buildTestApp(notifier, const Locale('fr')));
      await tester.pumpAndSettle();

      expect(
        errors,
        isEmpty,
        reason: 'Expected no RenderFlex overflow errors in French locale',
      );

      final uploadChip = find.widgetWithText(ActionChip, 'Charger le document');
      final discardChip = find.widgetWithText(ActionChip, 'Abandonner');

      expect(uploadChip, findsOneWidget);
      expect(discardChip, findsOneWidget);

      final uploadRect = tester.getRect(uploadChip);
      final discardRect = tester.getRect(discardChip);

      expect(uploadRect.right, lessThanOrEqualTo(360.0));
      expect(discardRect.right, lessThanOrEqualTo(360.0));
    },
  );

  testWidgets('keeps action chips side by side on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final notifier = ConsumptionChangeNotifier()..pendingFiles = [sampleFile];

    await tester.pumpWidget(buildTestApp(notifier, const Locale('fr')));
    await tester.pumpAndSettle();

    final uploadRect = tester.getRect(
      find.widgetWithText(ActionChip, 'Charger le document'),
    );
    final discardRect = tester.getRect(
      find.widgetWithText(ActionChip, 'Abandonner'),
    );

    expect(uploadRect.top, equals(discardRect.top));
    expect(discardRect.right, lessThanOrEqualTo(600.0));
  });
}
