import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/custom_field_form_field/fields/date_form_field.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/custom_field_form_field/fields/select_form_field.dart';

void main() {
  testWidgets('SelectFormField displays initial matching value', (tester) async {
    Object? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectFormField(
            labelText: 'Status',
            value: 2,
            extraData: {
              'select_options': [
                {'id': 1, 'label': 'Pending'},
                {'id': 2, 'label': 'Approved'},
                {'id': 3, 'label': 'Rejected'},
              ]
            },
            enabled: true,
            onChanged: (val) {
              changedValue = val;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 'Approved' is visible as the selected item
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('DateFormField displays initial date value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DateFormField(
            labelText: 'Expiry Date',
            value: '2024-05-15',
            enabled: true,
            onChanged: (val) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Date should be rendered
    expect(find.byType(DateFormField), findsOneWidget);
    expect(find.text('2024-05-15'), findsOneWidget);
    expect(find.text('Expiry Date'), findsOneWidget);
  });
}
