import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/extensions/filter_rule_extension.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/query_parameters/id_query_parameter.dart';
import 'package:paperless_mobile/api/models/rule_type_enum.dart';
import 'package:paperless_mobile/api/models/saved_view_filter_rule.dart';

void main() {
  group('Storage path filter rules (#304)', () {
    test(
      'RuleTypeEnum.hasStoragePathIn (30) applies to DocumentFilter with trimmed IDs and generates query params',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.hasStoragePathIn,
          value: '1, 3, 5',
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.storagePath, isA<IncludeIdsQueryParameter>());
        expect(
          (filter.storagePath as IncludeIdsQueryParameter).ids,
          equals([1, 3, 5]),
        );

        final queryParams = filter.toQueryParameters();
        expect(queryParams['storage_path__id__in'], equals('1,3,5'));
      },
    );

    test(
      'RuleTypeEnum.storagePathIs (25) applies correctly for single, null, and any',
      () {
        final singleRule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.storagePathIs,
          value: '7',
        );
        final singleFilter = singleRule.applyToFilter(const DocumentFilter());
        expect(singleFilter.storagePath, isA<SingleIdQueryParameter>());
        expect(
          (singleFilter.storagePath as SingleIdQueryParameter).id,
          equals(7),
        );
        expect(
          singleFilter.toQueryParameters()['storage_path__id'],
          equals('7'),
        );

        final nullRule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.storagePathIs,
          value: null,
        );
        final nullFilter = nullRule.applyToFilter(const DocumentFilter());
        expect(nullFilter.storagePath, isA<NotAssignedIdQueryParameter>());
        expect(
          nullFilter.toQueryParameters()['storage_path__isnull'],
          equals('true'),
        );

        final anyRule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.storagePathIs,
          value: '-1',
        );
        final anyFilter = anyRule.applyToFilter(const DocumentFilter());
        expect(anyFilter.storagePath, isA<AnyAssignedIdQueryParameter>());
        expect(
          anyFilter.toQueryParameters()['storage_path__isnull'],
          equals('false'),
        );
      },
    );

    test(
      'RuleTypeEnum.doesNotHaveStoragePathIn (31) applies to DocumentFilter',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.doesNotHaveStoragePathIn,
          value: '4,6',
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.storagePath, isA<ExcludeIdsQueryParameter>());
        expect(
          (filter.storagePath as ExcludeIdsQueryParameter).ids,
          equals([4, 6]),
        );

        final queryParams = filter.toQueryParameters();
        expect(queryParams['storage_path__id__none'], equals('4,6'));
      },
    );

    test(
      'DocumentFilter with storagePath converts back to SavedViewFilterRule via toFilterRules',
      () {
        final includeFilter = const DocumentFilter(
          storagePath: IncludeIdsQueryParameter(ids: [1, 2]),
        );
        final includeRules = includeFilter.toFilterRules();
        expect(
          includeRules.any(
            (r) =>
                r.ruleType == RuleTypeEnum.hasStoragePathIn && r.value == '1,2',
          ),
          isTrue,
        );

        final singleFilter = DocumentFilter(
          storagePath: SingleIdQueryParameter(id: 9),
        );
        final singleRules = singleFilter.toFilterRules();
        expect(
          singleRules.any(
            (r) => r.ruleType == RuleTypeEnum.storagePathIs && r.value == '9',
          ),
          isTrue,
        );
      },
    );
  });
}
