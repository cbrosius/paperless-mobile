import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:path/path.dart' as p;

class FakePaperlessDocumentsApi extends Fake implements PaperlessDocumentsApi {
  Document? mockDocument;
  Metadata? mockMetadata;

  @override
  Future<Document> get(int id, {List<String>? fields}) async {
    return mockDocument!;
  }

  @override
  Future<Metadata> getMetaData(int id) async {
    return mockMetadata!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePaperlessDocumentsApi fakeApi;
  late DocumentRepository repository;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('paperless_test_');
    FileService.instance = FileService.createForTesting(
      temporaryDirectory: tempDir,
      downloadsDirectory: tempDir,
    );
    fakeApi = FakePaperlessDocumentsApi();
    repository = DocumentRepository(fakeApi);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('generateLocalFilePath (#700)', () {
    test(
      'downloading original image document preserves original image extension instead of .pdf',
      () async {
        fakeApi.mockDocument = Document(
          id: 101,
          title: 'Receipt Image',
          originalFileName: 'receipt_photo.jpg',
          archivedFileName: 'receipt_photo.pdf',
        );
        fakeApi.mockMetadata = Metadata(
          originalFilename: 'receipt_photo.jpg',
          originalMimeType: 'image/jpeg',
          hasArchiveVersion: true,
          archiveMediaFilename: 'documents/archive/101.pdf',
          mediaFilename: 'documents/originals/receipt_photo.jpg',
        );

        final originalPath = await repository.generateLocalFilePath(
          101,
          original: true,
        );
        expect(p.extension(originalPath), equals('.jpg'));
        expect(p.basename(originalPath), equals('receipt_photo.jpg'));

        final archivedPath = await repository.generateLocalFilePath(
          101,
          original: false,
        );
        expect(p.extension(archivedPath), equals('.pdf'));
        expect(p.basename(archivedPath), equals('receipt_photo.pdf'));
      },
    );

    test(
      'downloading original PNG document preserves .png extension when archived version is .pdf',
      () async {
        fakeApi.mockDocument = Document(
          id: 102,
          title: 'Screenshot',
          originalFileName: 'screen_capture.png',
          archivedFileName: 'screen_capture.pdf',
        );
        fakeApi.mockMetadata = Metadata(
          originalFilename: 'screen_capture.png',
          originalMimeType: 'image/png',
          hasArchiveVersion: true,
        );

        final originalPath = await repository.generateLocalFilePath(
          102,
          original: true,
        );
        expect(p.extension(originalPath), equals('.png'));
        expect(p.basename(originalPath), equals('screen_capture.png'));
      },
    );

    test(
      'resolves extension from originalMimeType when filename lacks extension',
      () async {
        fakeApi.mockDocument = Document(
          id: 103,
          title: 'Scanned Document',
          originalFileName: 'scanned_receipt',
          archivedFileName: 'scanned_receipt.pdf',
        );
        fakeApi.mockMetadata = Metadata(
          originalFilename: 'scanned_receipt',
          originalMimeType: 'image/jpeg',
          hasArchiveVersion: true,
        );

        final originalPath = await repository.generateLocalFilePath(
          103,
          original: true,
        );
        expect(p.extension(originalPath), equals('.jpg'));
        expect(p.basename(originalPath), equals('scanned_receipt.jpg'));
      },
    );

    test(
      'strips directory prefixes from mediaFilename (#458) without leaking into file name',
      () async {
        fakeApi.mockDocument = Document(
          id: 104,
          title: 'Invoice 2024',
          originalFileName: null,
          archivedFileName: null,
        );
        fakeApi.mockMetadata = Metadata(
          mediaFilename: 'documents/2024/invoices/invoice_08.pdf',
          archiveMediaFilename:
              'documents/archive/2024/invoices/invoice_08.pdf',
          originalMimeType: 'application/pdf',
        );

        final path = await repository.generateLocalFilePath(
          104,
          original: true,
        );
        expect(p.basename(path), equals('invoice_08.pdf'));
        expect(path.contains('documents'), isFalse);
      },
    );

    test('falls back to document title when filename is empty', () async {
      fakeApi.mockDocument = Document(
        id: 105,
        title: 'Fallback Title',
        originalFileName: '.pdf',
        archivedFileName: null,
      );
      fakeApi.mockMetadata = Metadata(originalMimeType: 'application/pdf');

      final path = await repository.generateLocalFilePath(105, original: false);
      expect(p.basename(path), equals('Fallback Title.pdf'));
    });
  });
}
