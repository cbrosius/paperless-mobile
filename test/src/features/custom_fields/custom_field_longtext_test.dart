import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/models/custom_field.dart';
import 'package:paperless_mobile/api/models/data_type_enum.dart';

void main() {
  group('CustomField longtext and fallback parsing (#672)', () {
    test('successfully parses custom field with dataType longtext', () {
      final json = {
        'id': 42,
        'name': 'Invoice Details',
        'data_type': 'longtext',
        'extra_data': null,
        'document_count': 5,
      };

      final customField = CustomField.fromJson(json);

      expect(customField.id, equals(42));
      expect(customField.name, equals('Invoice Details'));
      expect(customField.dataType, equals(DataTypeEnum.longtext));
      expect(customField.documentCount, equals(5));
    });

    test('falls back to string when unknown data_type is received', () {
      final json = {
        'id': 99,
        'name': 'Future Field',
        'data_type': 'unknown_future_type',
        'extra_data': null,
        'document_count': 0,
      };

      final customField = CustomField.fromJson(json);

      expect(customField.id, equals(99));
      expect(customField.name, equals('Future Field'));
      expect(customField.dataType, equals(DataTypeEnum.string));
    });
  });
}
