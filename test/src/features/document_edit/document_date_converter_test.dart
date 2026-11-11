import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/converters/document_date_json_converter.dart';
import 'package:paperless_mobile/api/models/document.dart';
import 'package:paperless_mobile/api/models/patched_document_request.dart';
import 'package:paperless_mobile/api/utils/patched_value.dart';

void main() {
  group('DocumentDateJsonConverter (#286, #663)', () {
    const converter = DocumentDateJsonConverter();

    test('parses date-only string without modification', () {
      final date = converter.fromJson('2023-10-10');
      expect(date.year, equals(2023));
      expect(date.month, equals(10));
      expect(date.day, equals(10));
    });

    test(
      'parses ISO 8601 string with positive timezone offset without shifting to previous day',
      () {
        // In standard DateTime.parse(), "+02:00" is converted to UTC "2023-10-09 22:00:00Z",
        // which shifted the day back to October 9th in UTC and when serialized.
        final date = converter.fromJson('2023-10-10T00:00:00+02:00');
        expect(date.year, equals(2023));
        expect(date.month, equals(10));
        expect(date.day, equals(10));
      },
    );

    test('parses ISO 8601 string with UTC indicator without shifting day', () {
      final date = converter.fromJson('2023-10-10T00:00:00Z');
      expect(date.year, equals(2023));
      expect(date.month, equals(10));
      expect(date.day, equals(10));
    });

    test('parses ISO 8601 string with time components', () {
      final date = converter.fromJson('2023-10-10T14:32:05+02:00');
      expect(date.year, equals(2023));
      expect(date.month, equals(10));
      expect(date.day, equals(10));
    });

    test('serializes DateTime to YYYY-MM-DD', () {
      final date = DateTime(2023, 10, 10, 15, 30);
      expect(converter.toJson(date), equals('2023-10-10'));
    });
  });

  group('Document model date parsing (#286, #663)', () {
    test('parses document with timezone offset correctly', () {
      final json = <String, dynamic>{
        'id': 123,
        'title': 'Invoice Oct 2023',
        'created': '2023-10-10T00:00:00+02:00',
      };

      final doc = Document.fromJson(json);
      expect(doc.created, isNotNull);
      expect(doc.created!.year, equals(2023));
      expect(doc.created!.month, equals(10));
      expect(doc.created!.day, equals(10));
    });

    test('parses document with UTC created date correctly', () {
      final json = <String, dynamic>{
        'id': 124,
        'title': 'Receipt',
        'created': '2023-10-10T00:00:00Z',
      };

      final doc = Document.fromJson(json);
      expect(doc.created, isNotNull);
      expect(doc.created!.year, equals(2023));
      expect(doc.created!.month, equals(10));
      expect(doc.created!.day, equals(10));
    });
  });

  group('PatchedDocumentRequest date serialization (#286, #663)', () {
    test(
      'serializes calendar date (00:00:00) as YYYY-MM-DD to avoid timezone shifting',
      () {
        final request = PatchedDocumentRequest(
          created: PatchedValue(DateTime(2023, 10, 10)),
        );

        final json = request.toJson();
        expect(json['created'], equals('2023-10-10'));
      },
    );

    test(
      'omits created field when null (e.g. when only other fields change)',
      () {
        final request = PatchedDocumentRequest(
          documentType: PatchedValue(5),
          created: null,
        );

        final json = request.toJson();
        expect(json.containsKey('created'), isFalse);
        expect(json['document_type'], equals(5));
      },
    );
  });
}

