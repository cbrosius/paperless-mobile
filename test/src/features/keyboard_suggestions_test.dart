import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/custom_field_form_field/fields/string_form_field.dart';

void main() {
  group(
    'Keyboard suggestions, autocorrect, and capitalization (#407, #482, #483)',
    () {
      testWidgets(
        'StringFormField enables autocorrect, suggestions, and sentence capitalization',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StringFormField(
                  labelText: 'Title',
                  value: 'Initial',
                  enabled: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          );

          final textFieldFinder = find.byType(TextField);
          expect(textFieldFinder, findsOneWidget);

          final textField = tester.widget<TextField>(textFieldFinder);
          expect(textField.autocorrect, isTrue);
          expect(textField.enableSuggestions, isTrue);
          expect(
            textField.textCapitalization,
            equals(TextCapitalization.sentences),
          );
          expect(textField.keyboardType, equals(TextInputType.text));
        },
      );

      testWidgets(
        'Single-line text form field with sentence capitalization configures TextField correctly',
        (tester) async {
          final formKey = GlobalKey<FormBuilderState>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FormBuilder(
                  key: formKey,
                  child: FormBuilderTextField(
                    name: 'title',
                    keyboardType: TextInputType.text,
                    autocorrect: true,
                    enableSuggestions: true,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ),
            ),
          );

          final textFieldFinder = find.byType(TextField);
          expect(textFieldFinder, findsOneWidget);

          final textField = tester.widget<TextField>(textFieldFinder);
          expect(textField.autocorrect, isTrue);
          expect(textField.enableSuggestions, isTrue);
          expect(
            textField.textCapitalization,
            equals(TextCapitalization.sentences),
          );
          expect(textField.keyboardType, equals(TextInputType.text));
        },
      );

      testWidgets(
        'Multiline notes/description form field configures multiline keyboard with suggestions',
        (tester) async {
          final formKey = GlobalKey<FormBuilderState>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FormBuilder(
                  key: formKey,
                  child: FormBuilderTextField(
                    name: 'description',
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    autocorrect: true,
                    enableSuggestions: true,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ),
            ),
          );

          final textFieldFinder = find.byType(TextField);
          expect(textFieldFinder, findsOneWidget);

          final textField = tester.widget<TextField>(textFieldFinder);
          expect(textField.autocorrect, isTrue);
          expect(textField.enableSuggestions, isTrue);
          expect(
            textField.textCapitalization,
            equals(TextCapitalization.sentences),
          );
          expect(textField.keyboardType, equals(TextInputType.multiline));
          expect(textField.maxLines, isNull);
        },
      );
    },
  );
}
