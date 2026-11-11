import 'package:cached_query/cached_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:paperless_mobile/api/models/document.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/paginated_result_list.dart';
import 'package:paperless_mobile/api/models/query_parameters/text_query.dart';
import 'package:paperless_mobile/api/modules/paperless_documents_api.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';

class MockPaperlessDocumentsApi extends Mock implements PaperlessDocumentsApi {
  @override
  Future<PaginatedResultList<Document>> getAll([DocumentFilter? filter]) =>
      super.noSuchMethod(
            Invocation.method(#getAll, [filter]),
            returnValue: Future.value(
              PaginatedResultList<Document>(count: 0, results: []),
            ),
          )
          as Future<PaginatedResultList<Document>>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search pagination (#683)', () {
    late MockPaperlessDocumentsApi mockApi;
    late DocumentRepository documentRepository;

    setUp(() {
      CachedQuery.instance.reset();
      mockApi = MockPaperlessDocumentsApi();
      documentRepository = DocumentRepository(mockApi);
    });

    test('getAllQuery paginates when getNextPage is called', () async {
      final doc1 = Document(
        id: 1,
        title: 'Document 1',
        content: 'content',
        created: DateTime.now(),
        modified: DateTime.now(),
        added: DateTime.now(),
      );
      final doc2 = Document(
        id: 2,
        title: 'Document 2',
        content: 'content',
        created: DateTime.now(),
        modified: DateTime.now(),
        added: DateTime.now(),
      );

      when(mockApi.getAll(any)).thenAnswer((invocation) async {
        final filter = invocation.positionalArguments.first as DocumentFilter?;
        if (filter?.page == 2) {
          return PaginatedResultList<Document>(
            count: 50,
            next: null,
            previous: 'https://example.com/api/documents/?page=1',
            results: [doc2],
          );
        }
        return PaginatedResultList<Document>(
          count: 50,
          next: 'https://example.com/api/documents/?page=2',
          previous: null,
          results: [doc1],
        );
      });

      final query = documentRepository.getAllQuery(
        filter: DocumentFilter(query: TextQuery.titleAndContent('tax')),
      );

      final firstState = await query.result;
      expect(firstState.data?.pages.length, equals(1));
      expect(firstState.data?.pages.first.results.first.id, equals(1));
      expect(firstState.data?.firstPage?.count, equals(50));
      expect(firstState.data?.lastPage?.next, isNotNull);

      // Now fetch next page (which DocumentSearchPage was previously missing)
      final secondState = await query.getNextPage();
      expect(secondState?.data?.pages.length, equals(2));
      expect(secondState?.data?.pages.last.results.first.id, equals(2));
      expect(secondState?.data?.lastPage?.next, isNull);

      final totalResults = secondState?.data?.pages
          .expand((p) => p.results)
          .toList();
      expect(totalResults?.length, equals(2));
    });
  });
}
