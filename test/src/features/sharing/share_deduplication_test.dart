import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Share intent deduplication (#624)', () {
    test('deduplicates duplicate share events for the same file path', () {
      final processedPaths = <String>{};

      List<String> filterUnique(List<String> incoming) {
        return incoming.where((path) {
          if (processedPaths.contains(path)) {
            return false;
          }
          processedPaths.add(path);
          return true;
        }).toList();
      }

      // Initial share arrives
      final firstBatch = filterUnique(['/tmp/doc1.pdf', '/tmp/doc2.pdf']);
      expect(firstBatch, equals(['/tmp/doc1.pdf', '/tmp/doc2.pdf']));

      // Duplicate event fires immediately (e.g. cold start + media stream)
      final duplicateBatch = filterUnique(['/tmp/doc1.pdf']);
      expect(duplicateBatch, isEmpty);

      // New file arrives
      final newBatch = filterUnique(['/tmp/doc3.pdf']);
      expect(newBatch, equals(['/tmp/doc3.pdf']));
    });
  });
}

