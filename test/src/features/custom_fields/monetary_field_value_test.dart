import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/document_details/view/widgets/custom_fields/monetary_field_value.dart';

void main() {
  group('MonetaryFieldValue formatting (#681)', () {
    testWidgets('formats with default_currency from extraData in German locale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de', 'DE'),
          supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: MonetaryFieldValue(
              value: '19.99',
              extraData: {'default_currency': 'EUR'},
              placeholder: Text('-'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // In de_DE, EUR formats as 19,99 €
      expect(find.text('19,99\u00A0€'), findsOneWidget);
    });

    testWidgets('formats value with embedded currency prefix like EUR12.50', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de', 'DE'),
          supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: MonetaryFieldValue(
              value: 'EUR12.50',
              placeholder: Text('-'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('12,50\u00A0€'), findsOneWidget);
    });

    testWidgets('formats value in en_US locale with USD when unspecified', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: MonetaryFieldValue(
              value: '42.00',
              placeholder: Text('-'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('\$42.00'), findsOneWidget);
    });
  });
}
