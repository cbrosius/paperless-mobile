// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:paperless_mobile/api/converters/document_date_json_converter.dart';
import 'package:paperless_mobile/api/models/correspondent_request_set_permissions.dart';
import 'package:paperless_mobile/api/models/custom_field_instance_request.dart';

part 'document_request.freezed.dart';
part 'document_request.g.dart';

@Freezed(toJson: true, fromJson: false)
abstract class DocumentRequest with _$DocumentRequest {
  factory DocumentRequest({
    @JsonKey(includeIfNull: true) required int? correspondent,
    @JsonKey(includeIfNull: true) required int? documentType,
    @JsonKey(includeIfNull: true) required int? storagePath,
    String? title,

    /// The raw, text-only data of the document. This field is primarily used for searching.
    String? content,
    required List<int> tags,
    @DocumentDateJsonConverter() DateTime? created,
    @DocumentDateJsonConverter()
    @Deprecated('createdDate has been deprecated')
    DateTime? createdDate,
    DateTime? deletedAt,

    /// The position of this document in your physical document archive.
    // minimum: 0
    // maximum: 4294967295
    int? archiveSerialNumber,
    int? owner,
    CorrespondentRequestSetPermissions? setPermissions,
    List<CustomFieldInstanceRequest>? customFields,
    @Default(false) bool? removeInboxTags,
  }) = _DocumentRequest;
}
