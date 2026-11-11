import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

part 'document_share_state.dart';

class DocumentShareCubit extends Cubit<DocumentShareState> {
  final int documentId;
  final DocumentRepository _documentRepository;
  final PaperlessDocumentsApi _api;

  DocumentShareCubit(
    this._api,
    this._documentRepository, {
    required this.documentId,
  }) : super(const DocumentShareInitial());

  Future<void> shareDocument({bool shareOriginal = false}) async {
    emit(const DocumentShareInProgress(0.0));
    try {
      final documentResult = await _documentRepository
          .getDocumentQuery(documentId)
          .fetch();
      if (documentResult.isError) {
        return emit(DocumentShareError(documentResult.error));
      }
      final document = documentResult.data!;
      final filePath = await _documentRepository.generateLocalFilePath(
        documentId,
        original: shareOriginal,
        type: PaperlessDirectoryType.temporary,
      );
      await _api.downloadToFile(
        documentId,
        filePath,
        original: shareOriginal,
        onProgressChanged: (progress) =>
            emit(DocumentShareInProgress(progress)),
      );
      final mimeType = shareOriginal
          ? (lookupMimeType(filePath) ?? "application/octet-stream")
          : "application/pdf";
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              filePath,
              name: p.basename(filePath),
              mimeType: mimeType,
              lastModified: document.modified,
            ),
          ],
          subject: document.title,
        ),
      );
      emit(const DocumentShareSuccess());
    } catch (error) {
      emit(DocumentShareError(error));
    }
  }
}
