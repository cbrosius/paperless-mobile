import 'package:collection/collection.dart';
import 'package:paperless_mobile/api/models/custom_field_instance.dart';
import 'package:paperless_mobile/api/models/custom_field_instance_request.dart';
import 'package:paperless_mobile/api/models/document.dart';
import 'package:paperless_mobile/api/models/patched_document_request.dart';
import 'package:paperless_mobile/api/models/query_parameters/tags_query.dart';
import 'package:paperless_mobile/api/utils/patched_value.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/form_builder_localized_date_picker.dart';

class DocumentEditPatchBuilder {
  static const fkTitle = 'title';
  static const fkCorrespondent = 'correspondent';
  static const fkTags = 'tags';
  static const fkDocumentType = 'documentType';
  static const fkCreatedDate = 'createdAtDate';
  static const fkStoragePath = 'storagePath';
  static const fkContent = 'content';
  static const fkCustomFields = 'customFields';

  static bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Builds a [PatchedDocumentRequest] containing ONLY the fields that were present
  /// in the form and actually changed by the user.
  ///
  /// Fields that were not present (e.g., hidden because the user lacks permissions)
  /// or fields that did not change will be `null` in the request, and therefore
  /// omitted from the JSON PATCH payload.
  ///
  /// Returns `null` if no fields were changed.
  static PatchedDocumentRequest? buildPatchRequest({
    required Document document,
    required Map<String, dynamic> formValues,
    required Set<String> presentFieldNames,
    bool isContentTouched = false,
  }) {
    bool hasAnyChange = false;

    PatchedValue<String?>? titlePatch;
    if (presentFieldNames.contains(fkTitle)) {
      final title = formValues[fkTitle] as String?;
      if (document.title != title) {
        titlePatch = PatchedValue(title);
        hasAnyChange = true;
      }
    }

    PatchedValue<int?>? correspondentPatch;
    if (presentFieldNames.contains(fkCorrespondent)) {
      final correspondent = formValues[fkCorrespondent] as int?;
      if (document.correspondent != correspondent) {
        correspondentPatch = PatchedValue(correspondent);
        hasAnyChange = true;
      }
    }

    PatchedValue<int?>? documentTypePatch;
    if (presentFieldNames.contains(fkDocumentType)) {
      final documentType = formValues[fkDocumentType] as int?;
      if (document.documentType != documentType) {
        documentTypePatch = PatchedValue(documentType);
        hasAnyChange = true;
      }
    }

    PatchedValue<int?>? storagePathPatch;
    if (presentFieldNames.contains(fkStoragePath)) {
      final storagePath = formValues[fkStoragePath] as int?;
      if (document.storagePath != storagePath) {
        storagePathPatch = PatchedValue(storagePath);
        hasAnyChange = true;
      }
    }

    PatchedValue<List<int>?>? tagsPatch;
    if (presentFieldNames.contains(fkTags)) {
      final tagsParam = formValues[fkTags] as IdsTagsQuery?;
      final tags = switch (tagsParam) {
        IdsTagsQuery(include: var include) => include,
        _ => <int>[],
      };
      if (!const UnorderedIterableEquality().equals(
        document.tags ?? [],
        tags,
      )) {
        tagsPatch = PatchedValue(tags);
        hasAnyChange = true;
      }
    }

    PatchedValue<DateTime?>? createdPatch;
    if (presentFieldNames.contains(fkCreatedDate)) {
      final created = formValues[fkCreatedDate];
      final DateTime? createdAt;
      if (created is FormDateTime) {
        createdAt = created.toDateTime();
      } else if (created is DateTime) {
        createdAt = created;
      } else {
        createdAt = null;
      }
      if (!isSameDay(document.created, createdAt)) {
        createdPatch = PatchedValue(createdAt);
        hasAnyChange = true;
      }
    }

    PatchedValue<String?>? contentPatch;
    if (presentFieldNames.contains(fkContent)) {
      final content = formValues[fkContent] as String?;
      if (isContentTouched && document.content != content) {
        contentPatch = PatchedValue(content);
        hasAnyChange = true;
      }
    }

    PatchedValue<List<CustomFieldInstanceRequest>?>? customFieldsPatch;
    if (presentFieldNames.contains(fkCustomFields)) {
      final customFields =
          formValues[fkCustomFields] as List<CustomFieldInstance>? ?? [];
      if (!const ListEquality<CustomFieldInstance>().equals(
        document.customFields ?? [],
        customFields,
      )) {
        final customFieldRequests = customFields
            .map(
              (i) => CustomFieldInstanceRequest(field: i.field, value: i.value),
            )
            .toList();
        customFieldsPatch = PatchedValue(customFieldRequests);
        hasAnyChange = true;
      }
    }

    if (!hasAnyChange) return null;

    return PatchedDocumentRequest(
      title: titlePatch,
      correspondent: correspondentPatch,
      documentType: documentTypePatch,
      storagePath: storagePathPatch,
      tags: tagsPatch,
      created: createdPatch,
      content: contentPatch,
      customFields: customFieldsPatch,
    );
  }

  static bool hasChanges({
    required Document document,
    required Map<String, dynamic> formValues,
    required Set<String> presentFieldNames,
    bool isContentTouched = false,
  }) {
    return buildPatchRequest(
          document: document,
          formValues: formValues,
          presentFieldNames: presentFieldNames,
          isContentTouched: isContentTouched,
        ) !=
        null;
  }
}

