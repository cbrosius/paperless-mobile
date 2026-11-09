import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/models/custom_field_instance.dart';
import 'package:paperless_mobile/api/models/document.dart';
import 'package:paperless_mobile/api/models/query_parameters/tags_query.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/form_builder_localized_date_picker.dart';
import 'package:paperless_mobile/features/document_edit/utils/document_edit_patch_builder.dart';

void main() {
  group('DocumentEditPatchBuilder', () {
    late Document baseDocument;

    setUp(() {
      baseDocument = Document(
        id: 42,
        title: 'Original Title',
        correspondent: 10,
        documentType: 20,
        storagePath: 30,
        tags: [1, 2, 3],
        created: DateTime(2023, 5, 10, 14, 30, 0),
        content: 'Original Content',
        customFields: [CustomFieldInstance(field: 1, value: 'test')],
      );
    });

    test('returns null when no fields changed', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkTitle: 'Original Title',
        DocumentEditPatchBuilder.fkCorrespondent: 10,
        DocumentEditPatchBuilder.fkDocumentType: 20,
        DocumentEditPatchBuilder.fkStoragePath: 30,
        DocumentEditPatchBuilder.fkTags: IdsTagsQuery(include: [1, 2, 3]),
        DocumentEditPatchBuilder.fkCreatedDate: FormDateTime.fromDateTime(
          DateTime(2023, 5, 10),
        ),
        DocumentEditPatchBuilder.fkContent: 'Original Content',
        DocumentEditPatchBuilder.fkCustomFields: [
          CustomFieldInstance(field: 1, value: 'test'),
        ],
      };
      final present = formValues.keys.toSet();

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
        isContentTouched: false,
      );

      expect(patch, isNull);
      expect(
        DocumentEditPatchBuilder.hasChanges(
          document: baseDocument,
          formValues: formValues,
          presentFieldNames: present,
          isContentTouched: false,
        ),
        isFalse,
      );
    });

    test(
      'omits unpermitted/hidden fields completely so they are not sent in JSON (Issue #427)',
      () {
        // User does NOT have permission to view or edit storage paths or document types.
        // Those fields are not rendered in the form and thus not in presentFieldNames.
        final formValues = <String, dynamic>{
          DocumentEditPatchBuilder.fkTitle: 'New Title',
          DocumentEditPatchBuilder.fkCorrespondent: 10,
          DocumentEditPatchBuilder.fkTags: IdsTagsQuery(include: [1, 2, 3]),
          DocumentEditPatchBuilder.fkCreatedDate: FormDateTime.fromDateTime(
            DateTime(2023, 5, 10),
          ),
        };
        final present = {
          DocumentEditPatchBuilder.fkTitle,
          DocumentEditPatchBuilder.fkCorrespondent,
          DocumentEditPatchBuilder.fkTags,
          DocumentEditPatchBuilder.fkCreatedDate,
        };

        final patch = DocumentEditPatchBuilder.buildPatchRequest(
          document: baseDocument,
          formValues: formValues,
          presentFieldNames: present,
        );

        expect(patch, isNotNull);
        // Changed field is present
        expect(patch!.title?.value, 'New Title');
        // Unpermitted/hidden fields MUST be null in the Dart object
        expect(patch.storagePath, isNull);
        expect(patch.documentType, isNull);
        expect(patch.content, isNull);
        expect(patch.customFields, isNull);

        // And when serialized to JSON, storage_path and document_type MUST NOT exist
        final json = patch.toJson();
        expect(json.containsKey('storage_path'), isFalse);
        expect(json.containsKey('document_type'), isFalse);
        expect(json['title'], 'New Title');
      },
    );

    test(
      'explicitly sends null in JSON when user clears an existing value',
      () {
        final formValues = <String, dynamic>{
          DocumentEditPatchBuilder.fkCorrespondent: null, // cleared
        };
        final present = {DocumentEditPatchBuilder.fkCorrespondent};

        final patch = DocumentEditPatchBuilder.buildPatchRequest(
          document: baseDocument,
          formValues: formValues,
          presentFieldNames: present,
        );

        expect(patch, isNotNull);
        expect(patch!.correspondent, isNotNull);
        expect(patch.correspondent!.value, isNull);

        final json = patch.toJson();
        expect(json.containsKey('correspondent'), isTrue);
        expect(json['correspondent'], isNull);
      },
    );

    test('ignores tag reordering without actual changes', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkTags: IdsTagsQuery(
          include: [3, 1, 2],
        ), // reordered
      };
      final present = {DocumentEditPatchBuilder.fkTags};

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
      );

      expect(patch, isNull);
    });

    test('detects added and removed tags', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkTags: IdsTagsQuery(include: [1, 2, 99]),
      };
      final present = {DocumentEditPatchBuilder.fkTags};

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
      );

      expect(patch, isNotNull);
      expect(patch!.tags?.value, [1, 2, 99]);
      final json = patch.toJson();
      expect(json['tags'], [1, 2, 99]);
    });

    test(
      'does not treat created date with different time on same day as changed',
      () {
        // Document from server has time 14:30:00, date picker only has day/month/year
        final formValues = <String, dynamic>{
          DocumentEditPatchBuilder.fkCreatedDate: FormDateTime.fromDateTime(
            DateTime(2023, 5, 10, 0, 0, 0),
          ),
        };
        final present = {DocumentEditPatchBuilder.fkCreatedDate};

        final patch = DocumentEditPatchBuilder.buildPatchRequest(
          document: baseDocument,
          formValues: formValues,
          presentFieldNames: present,
        );

        expect(patch, isNull);
      },
    );

    test('detects created date changed to a different day', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkCreatedDate: FormDateTime.fromDateTime(
          DateTime(2023, 5, 11),
        ),
      };
      final present = {DocumentEditPatchBuilder.fkCreatedDate};

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
      );

      expect(patch, isNotNull);
      expect(patch!.created?.value, DateTime(2023, 5, 11));
    });

    test('ignores content if not touched (isContentTouched is false)', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkContent: 'Different Content',
      };
      final present = {DocumentEditPatchBuilder.fkContent};

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
        isContentTouched: false,
      );

      expect(patch, isNull);
    });

    test(
      'includes content if isContentTouched is true and content changed',
      () {
        final formValues = <String, dynamic>{
          DocumentEditPatchBuilder.fkContent: 'Different Content',
        };
        final present = {DocumentEditPatchBuilder.fkContent};

        final patch = DocumentEditPatchBuilder.buildPatchRequest(
          document: baseDocument,
          formValues: formValues,
          presentFieldNames: present,
          isContentTouched: true,
        );

        expect(patch, isNotNull);
        expect(patch!.content?.value, 'Different Content');
        final json = patch.toJson();
        expect(json['content'], 'Different Content');
      },
    );

    test('detects custom field changes and maps to requests', () {
      final formValues = <String, dynamic>{
        DocumentEditPatchBuilder.fkCustomFields: [
          CustomFieldInstance(field: 1, value: 'updated value'),
          CustomFieldInstance(field: 2, value: 42),
        ],
      };
      final present = {DocumentEditPatchBuilder.fkCustomFields};

      final patch = DocumentEditPatchBuilder.buildPatchRequest(
        document: baseDocument,
        formValues: formValues,
        presentFieldNames: present,
      );

      expect(patch, isNotNull);
      expect(patch!.customFields?.value?.length, 2);
      expect(patch.customFields?.value?[0].value, 'updated value');
      expect(patch.customFields?.value?[1].field, 2);
    });
  });
}
