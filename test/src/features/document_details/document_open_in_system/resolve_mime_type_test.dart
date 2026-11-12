import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/document_details/document_open_in_system/cubit/document_open_in_system_cubit.dart';

void main() {
  group('DocumentOpenInSystemCubit.resolveMimeType (#333)', () {
    test('falls back to text/plain for .md files', () {
      final mime = DocumentOpenInSystemCubit.resolveMimeType('/tmp/readme.md');
      expect(mime, equals('text/plain'));
    });

    test('falls back to text/plain for .markdown files', () {
      final mime = DocumentOpenInSystemCubit.resolveMimeType(
        '/tmp/notes.markdown',
      );
      expect(mime, equals('text/plain'));
    });

    test('falls back to text/plain for .yaml and .yml files', () {
      expect(
        DocumentOpenInSystemCubit.resolveMimeType('/tmp/config.yaml'),
        equals('text/plain'),
      );
      expect(
        DocumentOpenInSystemCubit.resolveMimeType('/tmp/config.yml'),
        equals('text/plain'),
      );
    });

    test('retains standard MIME types for pdf and images', () {
      expect(
        DocumentOpenInSystemCubit.resolveMimeType('/tmp/invoice.pdf'),
        equals('application/pdf'),
      );
      expect(
        DocumentOpenInSystemCubit.resolveMimeType('/tmp/photo.jpg'),
        equals('image/jpeg'),
      );
      expect(
        DocumentOpenInSystemCubit.resolveMimeType('/tmp/graphic.png'),
        equals('image/png'),
      );
    });
  });
}
