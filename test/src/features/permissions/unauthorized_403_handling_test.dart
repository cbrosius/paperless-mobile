import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/interceptor/dio_unauthorized_interceptor.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/message_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserPermissionExtension (#512)', () {
    test('matches both plain and Django app-prefixed permissions', () {
      final uiSettingsWithDjangoPrefix = UiSettingsView(
        permissions: [
          'documents.view_document',
          'documents.view_correspondent',
          'documents.view_documenttype',
          'documents.view_tag',
          'documents.view_storagepath',
          'documents.view_customfield',
        ],
        user: UiSettingsViewUser(
          id: 1,
          username: 'standard_user',
          isSuperuser: false,
        ),
      );

      expect(uiSettingsWithDjangoPrefix.canViewDocuments, isTrue);
      expect(uiSettingsWithDjangoPrefix.canViewCorrespondents, isTrue);
      expect(uiSettingsWithDjangoPrefix.canViewDocumentTypes, isTrue);
      expect(uiSettingsWithDjangoPrefix.canViewTags, isTrue);
      expect(uiSettingsWithDjangoPrefix.canViewStoragePaths, isTrue);
      expect(uiSettingsWithDjangoPrefix.canViewCustomFields, isTrue);

      final uiSettingsWithPlainNames = UiSettingsView(
        permissions: [
          'view_document',
          'view_correspondent',
        ],
        user: UiSettingsViewUser(
          id: 2,
          username: 'plain_user',
          isSuperuser: false,
        ),
      );

      expect(uiSettingsWithPlainNames.canViewDocuments, isTrue);
      expect(uiSettingsWithPlainNames.canViewCorrespondents, isTrue);
      expect(uiSettingsWithPlainNames.canViewStoragePaths, isFalse);
      expect(uiSettingsWithPlainNames.canViewCustomFields, isFalse);
    });

    test('superuser always has permissions even if permissions list is empty', () {
      final superuserSettings = UiSettingsView(
        permissions: [],
        user: UiSettingsViewUser(
          id: 1,
          username: 'admin',
          isSuperuser: true,
        ),
      );

      expect(superuserSettings.canViewStoragePaths, isTrue);
      expect(superuserSettings.canViewCustomFields, isTrue);
      expect(
        superuserSettings.hasPermissions(
          [PermissionAction.view, PermissionAction.add],
          [PermissionTarget.storagePath, PermissionTarget.customField],
        ),
        isTrue,
      );
    });

    test('hasPermissions properly evaluates multiple actions and targets', () {
      final userSettings = UiSettingsView(
        permissions: [
          'documents.view_document',
          'documents.change_document',
        ],
        user: UiSettingsViewUser(
          id: 3,
          username: 'editor',
          isSuperuser: false,
        ),
      );

      expect(
        userSettings.hasPermissions(
          [PermissionAction.view, PermissionAction.change],
          [PermissionTarget.document],
        ),
        isTrue,
      );

      expect(
        userSettings.hasPermissions(
          [PermissionAction.view, PermissionAction.delete],
          [PermissionTarget.document],
        ),
        isFalse,
      );
    });
  });

  group('PaperlessUnauthorizedException (#512)', () {
    test('toString() produces clean string without null', () {
      final withMessage = PaperlessUnauthorizedException('Forbidden access');
      expect(withMessage.toString(), 'PaperlessUnauthorizedException: Forbidden access');

      final withoutMessage = PaperlessUnauthorizedException(null);
      expect(withoutMessage.toString(), 'PaperlessUnauthorizedException');
      expect(withoutMessage.toString().contains('null'), isFalse);
    });

    test('DioUnauthorizedInterceptor wraps 403 into PaperlessUnauthorizedException', () {
      final interceptor = DioUnauthorizedInterceptor();
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/storage_paths/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/storage_paths/'),
          statusCode: 403,
          data: {'detail': 'You do not have permission to perform this action.'},
        ),
      );

      final handler = _TestErrorInterceptorHandler();
      interceptor.onError(dioException, handler);

      expect(handler.rejectedError, isNotNull);
      expect(handler.rejectedError!.error, isA<PaperlessUnauthorizedException>());
      expect(
        (handler.rejectedError!.error as PaperlessUnauthorizedException).message,
        'You do not have permission to perform this action.',
      );
    });
  });

  group('showGenericError 403 and DioException handling (#512)', () {
    testWidgets('shows localized unauthorized error message when error is PaperlessUnauthorizedException without detail',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showGenericError(context, PaperlessUnauthorizedException(null));
                  },
                  child: const Text('Trigger Error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Error'));
      await tester.pump();

      // Must never show raw exception or 'Instance of'
      expect(find.textContaining("Instance of 'PaperlessUnauthorizedException'"), findsNothing);
      expect(find.textContaining('PaperlessUnauthorizedException: null'), findsNothing);

      // Must show the localized user-friendly message
      expect(
        find.textContaining(
          'You are not authorized to perform this action. Please contact your admin or make sure you have the necessary permissions.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unwraps DioException containing PaperlessUnauthorizedException and displays localized message',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    final dioException = DioException(
                      requestOptions: RequestOptions(path: '/api/custom_fields/'),
                      error: PaperlessUnauthorizedException(null),
                      type: DioExceptionType.badResponse,
                    );
                    showGenericError(context, dioException);
                  },
                  child: const Text('Trigger Dio Error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Dio Error'));
      await tester.pump();

      // Must never show raw DioException or exception string
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining("Instance of 'PaperlessUnauthorizedException'"), findsNothing);

      // Must show the localized user-friendly message
      expect(
        find.textContaining(
          'You are not authorized to perform this action. Please contact your admin or make sure you have the necessary permissions.',
        ),
        findsOneWidget,
      );
    });
  });
}

class _TestErrorInterceptorHandler extends ErrorInterceptorHandler {
  DioException? rejectedError;

  @override
  void next(DioException err) {
    fail('Should not call next on 403');
  }

  @override
  void reject(DioException err, [bool isHandlerCycle = false]) {
    rejectedError = err;
  }
}
