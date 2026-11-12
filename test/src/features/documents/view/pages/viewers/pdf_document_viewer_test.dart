import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/documents/view/pages/viewers/pdf_document_viewer.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  testWidgets('PdfDocumentViewer configures annotation rendering mode', (
    tester,
  ) async {
    final bytes = Uint8List(0);
    final widget = MaterialApp(
      home: PdfDocumentViewer(bytes: bytes, title: 'Test Document'),
    );

    await tester.pumpWidget(widget);

    final pdfViewerFinder = find.byType(PdfViewer);
    expect(pdfViewerFinder, findsOneWidget);

    final pdfViewer = tester.widget<PdfViewer>(pdfViewerFinder);
    expect(
      pdfViewer.params.annotationRenderingMode,
      equals(PdfAnnotationRenderingMode.annotationAndForms),
    );
  });
}
