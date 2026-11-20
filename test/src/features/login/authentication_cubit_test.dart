import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/api/paperless_api.dart' hide Storage;
import 'package:paperless_mobile/core/interceptor/dio_unauthorized_interceptor.dart';
import 'package:paperless_mobile/core/security/session_manager.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/core/store/encrypted_local_store.dart';
import 'package:paperless_mobile/core/store/local_store.dart';
import 'package:paperless_mobile/core/store/slices/local_user_data.dart';
import 'package:paperless_mobile/core/store/slices/user_credentials.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/cubit/authentication_cubit.dart';
import 'package:paperless_mobile/features/login/model/client_certificate.dart';
import 'package:paperless_mobile/features/login/server_connection/model/header_entry.dart';
import 'package:paperless_mobile/features/login/services/authentication_service.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';

class _InMemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;
}

class _FakeEncryptedLocalStore implements EncryptedLocalStore {
  final Map<String, EncryptedLocalStoreState> _store = {};

  @override
  Future<void> clear(String userId) async => _store.remove(userId);

  @override
  Future<void> clearAll() async => _store.clear();

  @override
  Future<bool> contains(String userId) async => _store.containsKey(userId);

  @override
  Future<EncryptedLocalStoreState?> read(String userId) async => _store[userId];

  @override
  Future<void> write(String userId, EncryptedLocalStoreState value) async {
    _store[userId] = value;
  }
}

class _FakeSessionManager extends ChangeNotifier implements SessionManager {
  @override
  final Dio client = Dio();

  bool resetCalled = false;
  String? lastToken;
  String? lastBaseUrl;

  @override
  Future<int> getApiVersion() async => 9;

  @override
  void resetSettings({bool broadcast = true}) {
    resetCalled = true;
    lastToken = null;
    lastBaseUrl = null;
  }

  @override
  void updateSettings({
    String? baseUrl,
    String? authToken,
    ClientCertificate? clientCertificate,
    List<HeaderEntry>? additionalHeaders,
    bool broadcast = true,
  }) {
    lastBaseUrl = baseUrl;
    lastToken = authToken;
  }
}

class _FakeLocalAuthService implements LocalAuthenticationService {
  @override
  Future<bool> authenticateLocalUser(String localizedReason) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotificationService implements LocalNotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeUsersApi implements PaperlessUserApi {
  Future<UiSettingsView> Function()? onGetUiSettings;

  @override
  Future<UiSettingsView> getUiSettings() {
    if (onGetUiSettings != null) {
      return onGetUiSettings!();
    }
    return Future.value(
      UiSettingsView(user: UiSettingsViewUser(id: 1, username: 'alice')),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    logger = Logger(level: Level.off);
    HydratedBloc.storage = _InMemoryStorage();
  });

  group('DioUnauthorizedInterceptor', () {
    test(
      'wraps HTTP 401 into PaperlessUnauthorizedException with isInvalidToken=true',
      () {
        final interceptor = DioUnauthorizedInterceptor();
        final requestOptions = RequestOptions(path: '/api/ui_settings/');
        final dioError = DioException(
          requestOptions: requestOptions,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 401,
            data: {'detail': 'Invalid token.'},
          ),
          type: DioExceptionType.badResponse,
        );

        DioException? rejected;
        final handler = _CapturingErrorHandler(onReject: (e) => rejected = e);
        interceptor.onError(dioError, handler);

        expect(rejected, isNotNull);
        expect(rejected!.error, isA<PaperlessUnauthorizedException>());
        final authError = rejected!.error as PaperlessUnauthorizedException;
        expect(authError.statusCode, equals(401));
        expect(authError.isInvalidToken, isTrue);
        expect(authError.message, equals('Invalid token.'));
      },
    );

    test(
      'wraps HTTP 403 into PaperlessUnauthorizedException with isInvalidToken=false',
      () {
        final interceptor = DioUnauthorizedInterceptor();
        final requestOptions = RequestOptions(path: '/api/documents/');
        final dioError = DioException(
          requestOptions: requestOptions,
          response: Response(
            requestOptions: requestOptions,
            statusCode: 403,
            data: {'detail': 'You do not have permission.'},
          ),
          type: DioExceptionType.badResponse,
        );

        DioException? rejected;
        final handler = _CapturingErrorHandler(onReject: (e) => rejected = e);
        interceptor.onError(dioError, handler);

        expect(rejected, isNotNull);
        final authError = rejected!.error as PaperlessUnauthorizedException;
        expect(authError.statusCode, equals(403));
        expect(authError.isInvalidToken, isFalse);
      },
    );
  });

  group('AuthenticationCubit (#725)', () {
    late LocalStore store;
    late _FakeEncryptedLocalStore encryptedStore;
    late _FakeSessionManager sessionManager;
    late _FakeUsersApi usersApi;
    late AuthenticationCubit cubit;

    const userId = 'alice@https://paperless.example.com';
    const serverUrl = 'https://paperless.example.com';

    setUp(() async {
      await HydratedBloc.storage.clear();
      store = LocalStore('en');
      encryptedStore = _FakeEncryptedLocalStore();
      sessionManager = _FakeSessionManager();
      usersApi = _FakeUsersApi();

      store.setUserData(
        userId,
        LocalUserData(userId: userId, serverUrl: serverUrl, username: 'alice'),
      );
      store.setLoggedInAppUserId(userId);
      await encryptedStore.write(
        userId,
        EncryptedLocalStoreState(
          credentials: UserCredentials(token: 'expired-token'),
        ),
      );

      cubit = AuthenticationCubit(
        usersApi,
        sessionManager,
        ConnectivityStatusServiceMock(true),
        _FakeLocalAuthService(),
        _FakeNotificationService(),
        store,
        encryptedStore,
      );
    });

    tearDown(() async {
      await cubit.close();
      await store.close();
    });

    test(
      'restoreSession emits SessionExpired and clears token on HTTP 401',
      () async {
        usersApi.onGetUiSettings = () async {
          throw PaperlessUnauthorizedException(
            'Invalid token.',
            statusCode: 401,
          );
        };

        final emitted = <AuthenticationState>[];
        final sub = cubit.stream.listen(emitted.add);

        await cubit.restoreSession();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.first, isA<RestoringSession>());
        expect(emitted.last, isA<SessionExpired>());
        final expired = emitted.last as SessionExpired;
        expect(expired.serverUrl, equals(serverUrl));
        expect(expired.error, isA<PaperlessUnauthorizedException>());
        expect(store.state.loggedInAppUserId, isNull);
        expect(await encryptedStore.contains(userId), isFalse);
        expect(sessionManager.resetCalled, isTrue);
      },
    );

    test('restoreSession emits Authenticated when token is valid', () async {
      final emitted = <AuthenticationState>[];
      final sub = cubit.stream.listen(emitted.add);

      await cubit.restoreSession();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted.first, isA<RestoringSession>());
      expect(emitted.last, equals(const Authenticated(localUserId: userId)));
      expect(store.state.loggedInAppUserId, equals(userId));
    });

    test(
      're-authenticating via addUser succeeds after 401 cleared credentials',
      () async {
        usersApi.onGetUiSettings = () async {
          throw PaperlessUnauthorizedException(
            'Invalid token.',
            statusCode: 401,
          );
        };
        await cubit.restoreSession();
        expect(cubit.state, isA<SessionExpired>());

        // Now user logs in again with a new valid token.
        usersApi.onGetUiSettings = () async {
          return UiSettingsView(
            user: UiSettingsViewUser(id: 1, username: 'alice'),
          );
        };

        await cubit.addUser(serverUrl: serverUrl, token: 'new-valid-token');

        expect(cubit.state, equals(const Authenticated(localUserId: userId)));
        expect(store.state.loggedInAppUserId, equals(userId));
        final saved = await encryptedStore.read(userId);
        expect(saved?.credentials.token, equals('new-valid-token'));
      },
    );

    test(
      'handleInvalidToken is idempotent when already SessionExpired',
      () async {
        final emitted = <AuthenticationState>[];
        final sub = cubit.stream.listen(emitted.add);

        await cubit.handleInvalidToken(
          userId,
          error: PaperlessUnauthorizedException(
            'Invalid token.',
            statusCode: 401,
          ),
        );
        await cubit.handleInvalidToken(
          userId,
          error: PaperlessUnauthorizedException(
            'Invalid token.',
            statusCode: 401,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.whereType<SessionExpired>().length, equals(1));
      },
    );
  });
}

class _CapturingErrorHandler extends ErrorInterceptorHandler {
  final void Function(DioException) onReject;

  _CapturingErrorHandler({required this.onReject});

  @override
  void reject(DioException error) {
    onReject(error);
  }
}
