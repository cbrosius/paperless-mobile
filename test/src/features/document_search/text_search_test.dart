import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/query_parameters/text_query.dart';

void main() {
  group('Text search query parameters (#685)', () {
    test(
      'TextQuery.titleAndContent defaults to modern "text" parameter for Paperless-ngx 3.x',
      () {
        const query = TextQuery.titleAndContent('Strom');
        final params = query.toQueryParameter();
        expect(params, equals({'text': 'Strom'}));
      },
    );

    test(
      'TextQuery.titleAndContent uses "title_content" for legacy API version < 8',
      () {
        const query = TextQuery.titleAndContent('Strom');
        final params = query.toQueryParameter(7);
        expect(params, equals({'title_content': 'Strom'}));
      },
    );

    test(
      'TextQuery.titleAndContent uses "text" for API version >= 8 (Paperless-ngx 3.0+)',
      () {
        const query = TextQuery.titleAndContent('Strom');
        final paramsV8 = query.toQueryParameter(8);
        expect(paramsV8, equals({'text': 'Strom'}));

        final paramsV10 = query.toQueryParameter(10);
        expect(paramsV10, equals({'text': 'Strom'}));
      },
    );

    test('TextQuery.extended uses "query" across all versions', () {
      const query = TextQuery.extended('Strom');
      expect(query.toQueryParameter(), equals({'query': 'Strom'}));
      expect(query.toQueryParameter(7), equals({'query': 'Strom'}));
      expect(query.toQueryParameter(10), equals({'query': 'Strom'}));
    });

    test('TextQuery.title uses "title__icontains"', () {
      const query = TextQuery.title('Strom');
      expect(query.toQueryParameter(), equals({'title__icontains': 'Strom'}));
    });

    test(
      'DocumentFilter.toQueryParameters forwards apiVersion to text query',
      () {
        const filter = DocumentFilter(
          query: TextQuery.titleAndContent('Invoice'),
        );

        final modernParams = filter.toQueryParameters(10);
        expect(modernParams['text'], equals('Invoice'));
        expect(modernParams.containsKey('title_content'), isFalse);

        final legacyParams = filter.toQueryParameters(6);
        expect(legacyParams['title_content'], equals('Invoice'));
        expect(legacyParams.containsKey('text'), isFalse);
      },
    );
  });
}
