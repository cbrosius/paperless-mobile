import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:path/path.dart' as p;

part 'document_open_in_system_state.dart';

class DocumentOpenInSystemCubit extends Cubit<DocumentOpenInSystemState> {
  final int documentId;
  final DocumentRepository _repository;
  final PaperlessDocumentsApi _api;
  DocumentOpenInSystemCubit(
    this._repository,
    this._api, {
    required this.documentId,
  }) : super(DocumentOpenInSystemInitial());

  void openDocumentInSystemViewer() async {
    final documentResult = await _repository
        .getDocumentQuery(documentId)
        .fetch();
    if (documentResult.isError) {
      return emit(DocumentOpenInSystemError(documentResult.error));
    }

    final filePath = await _repository.generateLocalFilePath(
      documentId,
      original: true,
      type: PaperlessDirectoryType.temporary,
    );
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        await file.create();
        await _api.downloadToFile(
          documentId,
          file.path,
          onProgressChanged: (progress) =>
              emit(DocumentOpenInSystemInProgress(progress)),
        );
      }
      final mimeType = resolveMimeType(filePath);
      var openResult = await OpenFile.open(file.path, type: mimeType);
      if (openResult.type == ResultType.noAppToOpen &&
          mimeType != 'text/plain') {
        openResult = await OpenFile.open(file.path, type: 'text/plain');
      }
      emit(DocumentOpenInSystemSuccess(openResult.type));
    } catch (e) {
      emit(DocumentOpenInSystemError(e));
      return;
    }
  }

  /// Resolves the MIME type for external system viewer with fallbacks
  /// for markdown and plain text formats that Android lacks intent handlers for (#333).
  static String? resolveMimeType(String filePath) {
    final mime = lookupMimeType(filePath);
    final ext = p.extension(filePath).toLowerCase();
    if (mime == 'text/markdown' ||
        ext == '.md' ||
        ext == '.markdown' ||
        ext == '.yaml' ||
        ext == '.yml') {
      return 'text/plain';
    }
    return mime;
  }
}
