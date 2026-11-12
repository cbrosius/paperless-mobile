import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/documents/view/widgets/document_preview.dart';

void main() {
  group('DocumentPreview (#656)', () {
    test('buildCacheKey isolates thumbnails by user account', () {
      const docId = 42;
      final keyUserA = DocumentPreview.buildCacheKey(
        userId: 'user_a@example.com',
        documentId: docId,
      );
      final keyUserB = DocumentPreview.buildCacheKey(
        userId: 'user_b@example.com',
        documentId: docId,
      );

      expect(keyUserA, equals('user_a@example.com_thumb_42'));
      expect(keyUserB, equals('user_b@example.com_thumb_42'));
      expect(keyUserA, isNot(equals(keyUserB)));
    });

    test('buildCacheKey falls back to un-scoped key when userId is null', () {
      final key = DocumentPreview.buildCacheKey(userId: null, documentId: 100);

      expect(key, equals('thumb_100'));
    });
  });
}
