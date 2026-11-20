import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/store/slices/local_user_account.dart';
import 'package:paperless_mobile/core/store/slices/user_profile.dart';
import 'package:paperless_mobile/features/document_upload/model/document_upload_queue.dart';
import 'package:paperless_mobile/features/document_upload/service/document_upload_queue_coordinator.dart';
import 'package:paperless_mobile/features/document_upload/view/document_upload_preparation_page.dart';
import 'package:paperless_mobile/features/sharing/view/widgets/file_thumbnail.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class _NoOpQueueDelegate implements DocumentUploadQueueDelegate<String> {
  @override
  Future<void> discardRemainingItems(
    BuildContext context,
    List<DocumentUploadQueueItem<String>> remainingItems,
  ) async {}

  @override
  Future<void> onItemUploaded(
    BuildContext context,
    DocumentUploadQueueItem<String> item,
    DocumentUploadResult result,
  ) async {}

  @override
  Future<DocumentUploadQueueCancellationDisposition> onQueueCancelled(
    BuildContext context,
    List<DocumentUploadQueueItem<String>> remainingItems,
  ) async => DocumentUploadQueueCancellationDisposition.keepRemaining;

  @override
  Future<void> onQueueCompleted(BuildContext context) async {}
}

void main() {
  const pngBytes = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

  late Directory tempDir;
  late File sampleImage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_perf_test_');
    sampleImage = File('${tempDir.path}/scan_page_1.png');
    await sampleImage.writeAsBytes(pngBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrapWithApp(Widget child) {
    return Provider.value(
      value: LocalUserAccount(
        appUserId: 'test@example.com',
        serverUrl: 'https://example.com',
        apiVersion: 9,
        profile: UserProfile(
          profile: Profile(),
          uiSettings: UiSettingsView(
            user: UiSettingsViewUser(id: 1, username: 'test'),
            permissions: const [],
          ),
        ),
      ),
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets(
    'FileThumbnail does not trigger PDF rasterization for image files and sets cacheWidth (#715)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FileThumbnail(file: sampleImage, width: 120)),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<Image>(imageFinder);
      expect(image.image, isA<ResizeImage>());
    },
  );

  testWidgets(
    'DocumentUploadPreparationPage renders previewFile immediately while fileBytes is still pending (#715)',
    (tester) async {
      final pendingPdf = Completer<Uint8List>();

      await tester.pumpWidget(
        wrapWithApp(
          DocumentUploadPreparationPage(
            fileBytes: pendingPdf.future,
            previewFile: sampleImage,
            title: 'Multi-page scan',
            filename: 'multi_page_scan',
            fileExtension: '.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FileThumbnail), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(pendingPdf.isCompleted, isFalse);
    },
  );

  testWidgets(
    'DocumentUploadQueueCoordinator invokes loadFileBytes only once across route rebuilds (#715)',
    (tester) async {
      var loadCalls = 0;
      final pendingBytes = Completer<Uint8List>();
      late BuildContext rootContext;

      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) {
              rootContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      final queueFuture = DocumentUploadQueueCoordinator.processQueue<String>(
        rootContext,
        items: [
          DocumentUploadQueueItem<String>(
            source: 'scan-1',
            loadFileBytes: () {
              loadCalls++;
              return pendingBytes.future;
            },
            previewFile: sampleImage,
            title: 'Large Scan',
            filename: 'large_scan',
            fileExtension: '.pdf',
          ),
        ],
        delegate: _NoOpQueueDelegate(),
      );

      await tester.pumpAndSettle();
      expect(loadCalls, equals(1));

      // Push a secondary route (simulating opening FullscreenTagsForm / CreateLabelRoute)
      // and pop it back to trigger MaterialPageRoute rebuilds.
      final nav = Navigator.of(rootContext, rootNavigator: true);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Create Tag')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create Tag'), findsOneWidget);

      nav.pop();
      await tester.pumpAndSettle();

      // Pop the upload preparation page to complete the queue cleanly.
      nav.pop();
      await tester.pumpAndSettle();
      await queueFuture;

      expect(
        loadCalls,
        equals(1),
        reason: 'loadFileBytes must not be re-invoked on route rebuilds',
      );
    },
  );
}
