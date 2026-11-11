import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/extensions/filter_rule_extension.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/query_parameters/id_query_parameter.dart';
import 'package:paperless_mobile/api/models/rule_type_enum.dart';
import 'package:paperless_mobile/api/models/saved_view_filter_rule.dart';

void main() {
  group('Owner filter (#417)', () {
    test(
      'RuleTypeEnum.ownerIs with specific user ID applies to DocumentFilter and generates query parameters',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.ownerIs,
          value: '3',
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.owner, isA<SingleIdQueryParameter>());
        expect((filter.owner as SingleIdQueryParameter).id, equals(3));

        final queryParams = filter.toQueryParameters();
        expect(queryParams['owner__id'], equals('3'));
      },
    );

    test(
      'RuleTypeEnum.ownerIs with null value maps to NotAssignedIdQueryParameter',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.ownerIs,
          value: null,
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.owner, isA<NotAssignedIdQueryParameter>());

        final queryParams = filter.toQueryParameters();
        expect(queryParams['owner__isnull'], equals('true'));
      },
    );

    test(
      'RuleTypeEnum.doesNotHaveOwner applies to DocumentFilter with owner__isnull=true',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.doesNotHaveOwner,
          value: 'true',
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.owner, isA<NotAssignedIdQueryParameter>());

        final queryParams = filter.toQueryParameters();
        expect(queryParams['owner__isnull'], equals('true'));
      },
    );

    test(
      'RuleTypeEnum.hasOwnerIn applies to DocumentFilter with owner__id__in',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.hasOwnerIn,
          value: '2,5',
        );

        final filter = rule.applyToFilter(const DocumentFilter());
        expect(filter.owner, isA<IncludeIdsQueryParameter>());
        expect((filter.owner as IncludeIdsQueryParameter).ids, equals([2, 5]));

        final queryParams = filter.toQueryParameters();
        expect(queryParams['owner__id__in'], equals('2,5'));
      },
    );

    test(
      'DocumentFilter with owner serializes back to SavedViewFilterRule via toFilterRules',
      () {
        final singleFilter = DocumentFilter(
          owner: SingleIdQueryParameter(id: 4),
        );
        final singleRules = singleFilter.toFilterRules();
        expect(
          singleRules.any(
            (r) => r.ruleType == RuleTypeEnum.ownerIs && r.value == '4',
          ),
          isTrue,
        );

        final unownedFilter = const DocumentFilter(
          owner: NotAssignedIdQueryParameter(),
        );
        final unownedRules = unownedFilter.toFilterRules();
        expect(
          unownedRules.any((r) => r.ruleType == RuleTypeEnum.doesNotHaveOwner),
          isTrue,
        );

        final includeFilter = const DocumentFilter(
          owner: IncludeIdsQueryParameter(ids: [1, 2]),
        );
        final includeRules = includeFilter.toFilterRules();
        expect(
          includeRules.any(
            (r) => r.ruleType == RuleTypeEnum.hasOwnerIn && r.value == '1,2',
          ),
          isTrue,
        );
      },
    );
  });
}
