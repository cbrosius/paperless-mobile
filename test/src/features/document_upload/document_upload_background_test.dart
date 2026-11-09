import 'dart:async';
import 'dart:typed_data';

import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/modules/paperless_documents_api.dart';
import 'package:paperless_mobile/core/repository/document_repository.dart';
import 'package:paperless_mobile/features/document_upload/view/document_upload_preparation_page.dart';

class FakePaperlessDocumentsApi implements PaperlessDocumentsApi {
  CancelToken? lastCancelToken;
  bool shouldThrowCancel = false;

  @override
  Future<String> create(
    Uint8List documentBytes, {
    required String filename,
    String? title,
    DateTime? createdAt,
    int? documentType,
    int? correspondent,
    int? storagePath,
    Iterable<int> customFields = const [],
    Iterable<int> tags = const [],
    int? archiveSerialNumber,
    void Function(double progress)? onProgressChanged,
    CancelToken? cancelToken,
  }) async {
    lastCancelToken = cancelToken;
    if (shouldThrowCancel) {
      cancelToken?.cancel('user_cancelled');
      throw DioException(
        requestOptions: RequestOptions(path: '/api/documents/post_document/'),
        type: DioExceptionType.cancel,
      );
    }
    return 'task-456';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DocumentUploadResult', () {
    test('defaults continuedInBackground to false', () {
      final result = DocumentUploadResult(true, 'task-1');
      expect(result.success, isTrue);
      expect(result.taskId, 'task-1');
      expect(result.continuedInBackground, isFalse);
    });

    test('accepts continuedInBackground = true', () {
      final result = DocumentUploadResult(
        false,
        null,
        continuedInBackground: true,
      );
      expect(result.success, isFalse);
      expect(result.taskId, isNull);
      expect(result.continuedInBackground, isTrue);
    });
  });

  group('DocumentRepository.createDocumentMutation with CancelToken', () {
    late FakePaperlessDocumentsApi fakeApi;
    late DocumentRepository repository;

    setUp(() {
      fakeApi = FakePaperlessDocumentsApi();
      repository = DocumentRepository(fakeApi);
    });

    test('forwards cancelToken to PaperlessDocumentsApi.create', () async {
      final token = CancelToken();
      final bytes = Uint8List.fromList([1, 2, 3]);

      final mutation = repository.createDocumentMutation(
        bytes,
        filename: 'test.pdf',
        title: 'test',
        cancelToken: token,
      );

      final state = await mutation.mutate();
      expect(state.data, 'task-456');
      expect(state, isA<MutationSuccess<String?>>());
      expect(fakeApi.lastCancelToken, equals(token));
    });

    test('returns MutationError when cancelToken cancels the upload', () async {
      final token = CancelToken();
      final bytes = Uint8List.fromList([1, 2, 3]);
      fakeApi.shouldThrowCancel = true;

      final mutation = repository.createDocumentMutation(
        bytes,
        filename: 'test_cancelled.pdf',
        title: 'test',
        cancelToken: token,
      );

      final state = await mutation.mutate();
      expect(state, isA<MutationError<String?>>());
      final error = (state as MutationError<String?>).error;
      expect(error, isA<DioException>());
      expect((error as DioException).type, DioExceptionType.cancel);
      expect(token.isCancelled, isTrue);
    });
  });
}
