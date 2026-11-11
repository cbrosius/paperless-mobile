import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/extensions/extensions.dart';
import 'package:paperless_mobile/api/models/document_filter.dart';
import 'package:paperless_mobile/api/models/rule_type_enum.dart';
import 'package:paperless_mobile/api/paperless_api.dart';

void main() {
  group('Saved View Custom Field / Selection Filter (#641)', () {
    test('applies customFieldsQuery rule (42) to DocumentFilter', () {
      final rule = SavedViewFilterRule(
        ruleType: RuleTypeEnum.customFieldsQuery,
        value: '["Status","exact","unpaid"]',
      );

      final filter = rule.applyToFilter(const DocumentFilter());

      expect(filter.customFieldQuery, '["Status","exact","unpaid"]');
      expect(filter.appliedFiltersCount, 1);

      final queryParams = filter.toQueryParameters();
      expect(queryParams['custom_field_query'], '["Status","exact","unpaid"]');
    });

    test('applies hasCustomFieldValue rule (36) to DocumentFilter', () {
      final rule = SavedViewFilterRule(
        ruleType: RuleTypeEnum.hasCustomFieldValue,
        value: '["Status","exact","unpaid"]',
      );

      final filter = rule.applyToFilter(const DocumentFilter());

      expect(filter.customFieldQuery, '["Status","exact","unpaid"]');
      expect(
        filter.toQueryParameters()['custom_field_query'],
        '["Status","exact","unpaid"]',
      );
    });

    test('combines multiple custom field queries using AND', () {
      final rule1 = SavedViewFilterRule(
        ruleType: RuleTypeEnum.customFieldsQuery,
        value: '["Status","exact","unpaid"]',
      );
      final rule2 = SavedViewFilterRule(
        ruleType: RuleTypeEnum.customFieldsQuery,
        value: '["Priority","exact","high"]',
      );

      var filter = const DocumentFilter();
      filter = rule1.applyToFilter(filter);
      filter = rule2.applyToFilter(filter);

      expect(
        filter.customFieldQuery,
        '["AND",[["Status","exact","unpaid"],["Priority","exact","high"]]]',
      );
      expect(
        filter.toQueryParameters()['custom_field_query'],
        '["AND",[["Status","exact","unpaid"],["Priority","exact","high"]]]',
      );
    });

    test(
      'serializes customFieldQuery back into SavedViewFilterRule in toFilterRules',
      () {
        const filter = DocumentFilter(
          customFieldQuery: '["Status","exact","unpaid"]',
        );

        final rules = filter.toFilterRules();
        final customFieldRules = rules.where(
          (r) => r.ruleType == RuleTypeEnum.customFieldsQuery,
        );

        expect(customFieldRules, hasLength(1));
        expect(customFieldRules.first.value, '["Status","exact","unpaid"]');
      },
    );

    test(
      'SavedView.toDocumentFilter preserves selection custom field filter',
      () {
        final savedView = SavedView(
          id: 42,
          name: 'Unpaid Invoices',
          showOnDashboard: false,
          showInSidebar: false,
          userCanChange: true,
          sortField: 'created',
          sortReverse: false,
          filterRules: [
            SavedViewFilterRule(
              ruleType: RuleTypeEnum.customFieldsQuery,
              value: '["Status","exact","unpaid"]',
            ),
          ],
        );

        final filter = savedView.toDocumentFilter();

        expect(filter.selectedView, 42);
        expect(filter.customFieldQuery, '["Status","exact","unpaid"]');
        expect(
          filter.toQueryParameters()['custom_field_query'],
          '["Status","exact","unpaid"]',
        );
      },
    );
  });
}
