import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:paperless_mobile/api/converters/document_date_json_converter.dart';
import 'package:paperless_mobile/api/models/custom_field_instance.dart';
import 'package:paperless_mobile/api/models/document_permissions.dart';
import 'package:paperless_mobile/api/models/note.dart';

part 'document.freezed.dart';
part 'document.g.dart';

@Freezed(toJson: true, fromJson: true)
abstract class Document with _$Document {
  factory Document({
    required int id,
    int? correspondent,
    int? documentType,
    int? storagePath,
    String? title,

    /// The raw, text-only data of the document. This field is primarily used for searching.
    String? content,
    List<int>? tags,
    @DocumentDateJsonConverter() DateTime? created,
    @DocumentDateJsonConverter()
    @Deprecated('createdDate has been deprecated')
    DateTime? createdDate,
    DateTime? modified,
    DateTime? added,
    DateTime? deletedAt,

    /// The position of this document in your physical document archive.
    // minimum: 0
    // maximum: 4294967295
    int? archiveSerialNumber,
    String? originalFileName,
    String? archivedFileName,
    int? owner,
    DocumentPermissions? permissions,
    bool? userCanChange,
    bool? isSharedByRequester,
    List<Note>? notes,
    @Default([]) List<CustomFieldInstance>? customFields,
    int? pageCount,
    String? mimeType,
  }) = _Document;

  factory Document.fromJson(Map<String, dynamic> json) =>
      _$DocumentFromJson(json);
}
