import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/extensions/extensions.dart';
import 'package:paperless_mobile/api/models/models.dart';

void main() {
  group('Saved View Sort Persistence (#457)', () {
    test('updates sortField and sortReverse in newView and toRequest', () {
      final originalView = SavedView(
        id: 1,
        name: 'My View',
        showOnDashboard: true,
        showInSidebar: false,
        userCanChange: true,
        sortField: 'created',
        sortReverse: true,
        filterRules: [],
      );

      // User changed sort order to title ascending
      final currentFilter = originalView.toDocumentFilter().copyWith(
        sortField: SortField.title,
        sortOrder: SortOrder.ascending,
      );

      // Verify that changes are detected
      expect(originalView.toDocumentFilter() != currentFilter, isTrue);

      // Create updated view as done in SavedViewsWidget
      final updatedView = originalView.copyWith(
        filterRules: currentFilter.toFilterRules(),
        sortField: currentFilter.sortField?.value,
        sortReverse: currentFilter.sortOrder == SortOrder.descending,
      );

      expect(updatedView.sortField, 'title');
      expect(updatedView.sortReverse, isFalse);

      final request = updatedView.toRequest();
      expect(request.sortField, 'title');
      expect(request.sortReverse, isFalse);
    });

    test(
      'updates sortField and sortReverse when sorting descending by correspondent',
      () {
        final originalView = SavedView(
          id: 2,
          name: 'Correspondents View',
          showOnDashboard: false,
          showInSidebar: true,
          userCanChange: true,
          sortField: 'title',
          sortReverse: false,
          filterRules: [],
        );

        final currentFilter = originalView.toDocumentFilter().copyWith(
          sortField: SortField.correspondentName,
          sortOrder: SortOrder.descending,
        );

        expect(originalView.toDocumentFilter() != currentFilter, isTrue);

        final updatedView = originalView.copyWith(
          filterRules: currentFilter.toFilterRules(),
          sortField: currentFilter.sortField?.value,
          sortReverse: currentFilter.sortOrder == SortOrder.descending,
        );

        expect(updatedView.sortField, 'correspondent__name');
        expect(updatedView.sortReverse, isTrue);

        final request = updatedView.toRequest();
        expect(request.sortField, 'correspondent__name');
        expect(request.sortReverse, isTrue);
      },
    );

    test('toSavedViewRequest on DocumentFilter preserves sorting', () {
      const filter = DocumentFilter(
        sortField: SortField.archiveSerialNumber,
        sortOrder: SortOrder.descending,
      );

      final request = filter.toSavedViewRequest(
        name: 'ASN View',
        showInSidebar: true,
        showOnDashboard: true,
      );

      expect(request.sortField, 'archive_serial_number');
      expect(request.sortReverse, isTrue);
    });
  });
}
