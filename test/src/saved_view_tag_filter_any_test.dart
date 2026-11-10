import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';

void main() {
  group('SavedView Tag Filter Any/All (#428)', () {
    test(
      'hasTagsIn deserializes comma-separated value into AnyAssignedTagsQuery',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.hasTagsIn,
          value: '10,12',
        );
        final filter = rule.applyToFilter(DocumentFilter.initial);

        expect(filter.tags, isA<AnyAssignedTagsQuery>());
        final anyTags = filter.tags as AnyAssignedTagsQuery;
        expect(anyTags.tagIds, [10, 12]);
        expect(filter.toQueryParameters()['tags__id__in'], '10,12');
        expect(filter.appliedFiltersCount, 2);
      },
    );

    test(
      'multiple hasTagsIn rules accumulate tag IDs in AnyAssignedTagsQuery',
      () {
        final rules = [
          SavedViewFilterRule(ruleType: RuleTypeEnum.hasTagsIn, value: '5'),
          SavedViewFilterRule(ruleType: RuleTypeEnum.hasTagsIn, value: '8'),
        ];

        DocumentFilter filter = DocumentFilter.initial;
        for (final rule in rules) {
          filter = rule.applyToFilter(filter);
        }

        expect(filter.tags, isA<AnyAssignedTagsQuery>());
        final anyTags = filter.tags as AnyAssignedTagsQuery;
        expect(anyTags.tagIds, [5, 8]);
        expect(filter.toQueryParameters()['tags__id__in'], '5,8');
      },
    );

    test('hasTag rules accumulate tag IDs in IdsTagsQuery (All)', () {
      final rules = [
        SavedViewFilterRule(ruleType: RuleTypeEnum.hasTag, value: '3'),
        SavedViewFilterRule(ruleType: RuleTypeEnum.hasTag, value: '7'),
      ];

      DocumentFilter filter = DocumentFilter.initial;
      for (final rule in rules) {
        filter = rule.applyToFilter(filter);
      }

      expect(filter.tags, isA<IdsTagsQuery>());
      final idsTags = filter.tags as IdsTagsQuery;
      expect(idsTags.include, [3, 7]);
      expect(filter.toQueryParameters()['tags__id__all'], '3,7');
    });

    test(
      'toFilterRules serializes AnyAssignedTagsQuery with tagIds to hasTagsIn (22)',
      () {
        const filter = DocumentFilter(
          tags: AnyAssignedTagsQuery(tagIds: [10, 12]),
        );

        final rules = filter.toFilterRules();
        final tagRules = rules
            .where((r) => r.ruleType == RuleTypeEnum.hasTagsIn)
            .toList();

        expect(tagRules, hasLength(1));
        expect(tagRules.first.value, '10,12');
      },
    );

    test(
      'toFilterRules serializes AnyAssignedTagsQuery without tagIds to hasAnyTag (7) with true',
      () {
        const filter = DocumentFilter(tags: AnyAssignedTagsQuery(tagIds: []));

        final rules = filter.toFilterRules();
        final tagRules = rules
            .where((r) => r.ruleType == RuleTypeEnum.hasAnyTag)
            .toList();

        expect(tagRules, hasLength(1));
        expect(tagRules.first.value, 'true');
      },
    );

    test(
      'toFilterRules serializes NotAssignedTagsQuery to hasAnyTag (7) with false',
      () {
        const filter = DocumentFilter(tags: NotAssignedTagsQuery());

        final rules = filter.toFilterRules();
        final tagRules = rules
            .where((r) => r.ruleType == RuleTypeEnum.hasAnyTag)
            .toList();

        expect(tagRules, hasLength(1));
        expect(tagRules.first.value, 'false');
      },
    );

    test(
      'round-trip: SavedView with hasTagsIn retains filter rules after toDocumentFilter and toFilterRules',
      () {
        final originalRules = [
          SavedViewFilterRule(ruleType: RuleTypeEnum.hasTagsIn, value: '10,12'),
        ];

        final savedView = SavedView(
          id: 1,
          name: 'Any Tags View',
          showInSidebar: true,
          showOnDashboard: true,
          userCanChange: true,
          filterRules: originalRules,
        );

        final filter = savedView.toDocumentFilter();
        expect(filter.tags, const AnyAssignedTagsQuery(tagIds: [10, 12]));

        final generatedRules = filter.toFilterRules();
        final hasTagsInRules = generatedRules
            .where((r) => r.ruleType == RuleTypeEnum.hasTagsIn)
            .toList();

        expect(hasTagsInRules, hasLength(1));
        expect(hasTagsInRules.first.value, '10,12');
      },
    );

    test(
      'appliedFiltersCount correctly counts empty and non-empty AnyAssignedTagsQuery',
      () {
        const emptyAny = DocumentFilter(tags: AnyAssignedTagsQuery(tagIds: []));
        expect(emptyAny.appliedFiltersCount, 1);

        const specificAny = DocumentFilter(
          tags: AnyAssignedTagsQuery(tagIds: [1, 2, 3]),
        );
        expect(specificAny.appliedFiltersCount, 3);
      },
    );
  });
}
