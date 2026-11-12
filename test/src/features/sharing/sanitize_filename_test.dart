import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/sharing/cubit/receive_share_cubit.dart';

void main() {
  group('ConsumptionChangeNotifier.sanitizeFileName (#437)', () {
    test('replaces slashes and backslashes in filenames with underscores', () {
      final name = 'Rechnung 08/2024.pdf';
      final sanitized = ConsumptionChangeNotifier.sanitizeFileName(name);
      expect(sanitized, equals('Rechnung 08_2024.pdf'));
    });

    test('replaces colons, quotes, question marks and pipe characters', () {
      final name = 'Invoice:2024*final?"test"|<tag>.pdf';
      final sanitized = ConsumptionChangeNotifier.sanitizeFileName(name);
      expect(sanitized, equals('Invoice_2024_final_test_tag_.pdf'));
    });

    test('preserves valid standard filenames unchanged', () {
      final name = 'my-scanned-document_2024.pdf';
      final sanitized = ConsumptionChangeNotifier.sanitizeFileName(name);
      expect(sanitized, equals('my-scanned-document_2024.pdf'));
    });
  });
}
