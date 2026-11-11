import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/extensions/filter_rule_extension.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/query_parameters/id_query_parameter.dart';
import 'package:paperless_mobile/api/models/rule_type_enum.dart';
import 'package:paperless_mobile/api/models/saved_view_filter_rule.dart';

void main() {
  group('Custom field filtering & SavedView rules (#686)', () {
    test(
      'RuleTypeEnum.hasCustomFieldIn applies to DocumentFilter and generates query params',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.hasCustomFieldIn,
          value: '5,10',
        );

        final filter = rule.applyToFilter(const DocumentFilter());

        expect(filter.customFields, isA<IncludeIdsQueryParameter>());
        expect(
          (filter.customFields as IncludeIdsQueryParameter).ids,
          equals([5, 10]),
        );

        final queryParams = filter.toQueryParameters();
        expect(queryParams['custom_fields__id__in'], equals('5,10'));
      },
    );

    test('RuleTypeEnum.doesNotHaveCustomFieldIn applies to DocumentFilter', () {
      final rule = SavedViewFilterRule(
        ruleType: RuleTypeEnum.doesNotHaveCustomFieldIn,
        value: '7',
      );

      final filter = rule.applyToFilter(const DocumentFilter());

      expect(filter.customFields, isA<ExcludeIdsQueryParameter>());
      expect(
        (filter.customFields as ExcludeIdsQueryParameter).ids,
        equals([7]),
      );

      final queryParams = filter.toQueryParameters();
      expect(queryParams['custom_fields__id__none'], equals('7'));
    });

    test(
      'RuleTypeEnum.hasCustomFields applies to DocumentFilter as anyAssigned',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.hasCustomFields,
          value: 'true',
        );

        final filter = rule.applyToFilter(const DocumentFilter());

        expect(filter.customFields, isA<AnyAssignedIdQueryParameter>());
        final queryParams = filter.toQueryParameters();
        expect(queryParams['custom_fields__isnull'], equals('0'));
      },
    );

    test(
      'RuleTypeEnum.doesNotHaveCustomField applies to DocumentFilter as notAssigned',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.doesNotHaveCustomField,
          value: 'true',
        );

        final filter = rule.applyToFilter(const DocumentFilter());

        expect(filter.customFields, isA<NotAssignedIdQueryParameter>());
        final queryParams = filter.toQueryParameters();
        expect(queryParams['custom_fields__isnull'], equals('1'));
      },
    );

    test(
      'customFieldsQuery applies to DocumentFilter and outputs query param',
      () {
        final rule = SavedViewFilterRule(
          ruleType: RuleTypeEnum.customFieldsQuery,
          value: '["field", "exact", "value"]',
        );

        final filter = rule.applyToFilter(const DocumentFilter());

        expect(filter.customFieldQuery, equals('["field", "exact", "value"]'));
        final queryParams = filter.toQueryParameters();
        expect(
          queryParams['custom_field_query'],
          equals('["field", "exact", "value"]'),
        );
      },
    );

    test(
      'DocumentFilter with customFields converts back to SavedViewFilterRule',
      () {
        const filter = DocumentFilter(
          customFields: IncludeIdsQueryParameter(ids: [1, 2]),
          customFieldQuery: 'my_query',
        );

        final rules = filter.toFilterRules();

        expect(
          rules.any(
            (r) =>
                r.ruleType == RuleTypeEnum.hasCustomFieldIn && r.value == '1,2',
          ),
          isTrue,
        );
        expect(
          rules.any(
            (r) =>
                r.ruleType == RuleTypeEnum.customFieldsQuery &&
                r.value == 'my_query',
          ),
          isTrue,
        );
      },
    );
  });
}
