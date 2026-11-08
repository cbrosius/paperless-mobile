import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/interceptor/api_version_header.interceptor.dart';
import 'package:paperless_mobile/core/security/session_manager_impl.dart';
import 'package:paperless_mobile/core/service/connectivity_status_service.dart';
import 'package:paperless_mobile/features/logging/data/logger.dart';
import 'package:paperless_mobile/features/login/model/reachability_status.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  )
  onFetch;

  _FakeHttpClientAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return onFetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value([ConnectivityResult.wifi]);
}

void main() {
  setUpAll(() {
    logger = Logger(level: Level.off);
  });

  group('Lightweight reachability & API version probes (#704, #709)', () {
    test(
      'isPaperlessServerReachable sends HEAD /api/ with pure application/json Accept header and skipApiVersion',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        String? capturedAcceptHeader;
        String? capturedMethod;
        server.listen((HttpRequest request) async {
          if (request.uri.path == '/api/') {
            capturedMethod = request.method;
            capturedAcceptHeader = request.headers.value(
              HttpHeaders.acceptHeader,
            );
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"documents": "/api/documents/"}');
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final status = await service.isPaperlessServerReachable(
          'http://${server.address.address}:${server.port}',
        );

        expect(status, ReachabilityStatus.reachable);
        expect(capturedMethod, 'HEAD');
        expect(capturedAcceptHeader, 'application/json');
      },
    );

    test(
      'isPaperlessServerReachable treats 302 redirect from HEAD /api/ as reachable without following redirect',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final requestedPaths = <String>[];
        server.listen((HttpRequest request) async {
          requestedPaths.add('${request.method} ${request.uri.path}');
          if (request.uri.path == '/api/') {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              'schema/view/',
            );
            await request.response.close();
          } else if (request.uri.path == '/api/schema/view/') {
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final status = await service.isPaperlessServerReachable(
          'http://${server.address.address}:${server.port}',
        );

        expect(status, ReachabilityStatus.reachable);
        // followRedirects: false ensures only 1 single HTTP request is sent
        expect(requestedPaths, ['HEAD /api/']);
      },
    );

    test(
      'isPaperlessServerReachable falls back to HEAD /api/schema/ when /api/ returns 406',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final requestedPaths = <String>[];
        server.listen((HttpRequest request) async {
          requestedPaths.add('${request.method} ${request.uri.path}');
          if (request.uri.path == '/api/') {
            request.response.statusCode = HttpStatus.notAcceptable;
            await request.response.close();
          } else if (request.uri.path == '/api/schema/') {
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final status = await service.isPaperlessServerReachable(
          'http://${server.address.address}:${server.port}',
        );

        expect(status, ReachabilityStatus.reachable);
        expect(requestedPaths, ['HEAD /api/', 'HEAD /api/schema/']);
      },
    );

    test(
      'isPaperlessServerReachable falls back to HEAD /api/schema/ when /api/ returns 404',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final requestedPaths = <String>[];
        server.listen((HttpRequest request) async {
          requestedPaths.add('${request.method} ${request.uri.path}');
          if (request.uri.path == '/api/') {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          } else if (request.uri.path == '/api/schema/') {
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final status = await service.isPaperlessServerReachable(
          'http://${server.address.address}:${server.port}',
        );

        expect(status, ReachabilityStatus.reachable);
        expect(requestedPaths, ['HEAD /api/', 'HEAD /api/schema/']);
      },
    );

    test(
      'isPaperlessServerReachable returns notReachable when both /api/ (406) and fallback /api/schema/ (500) fail',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/api/') {
            request.response.statusCode = HttpStatus.notAcceptable;
            await request.response.close();
          } else if (request.uri.path == '/api/schema/') {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final service = ConnectivityStatusServiceImpl(_FakeConnectivity());
        final status = await service.isPaperlessServerReachable(
          'http://${server.address.address}:${server.port}',
        );

        expect(status, ReachabilityStatus.notReachable);
      },
    );

    test(
      'ApiVersionHeaderInterceptor preserves pure application/json Accept header when skipApiVersion: true',
      () async {
        final dio = Dio();
        dio.interceptors.add(ApiVersionHeaderInterceptor(() => 9));

        RequestOptions? capturedOptions;
        dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
          capturedOptions = options;
          return ResponseBody.fromString('', HttpStatus.ok);
        });

        await dio.get(
          'https://example.com/api/',
          options: Options(
            headers: {HttpHeaders.acceptHeader: 'application/json'},
            extra: {'skipApiVersion': true},
          ),
        );

        expect(capturedOptions, isNotNull);
        expect(
          capturedOptions!.headers[HttpHeaders.acceptHeader],
          'application/json',
        );
      },
    );

    test(
      'getApiVersion requests HEAD /api/profile/ instead of /api/schema/ and parses x-api-version',
      () async {
        final sessionManager = SessionManagerImpl();
        addTearDown(sessionManager.resetSettings);

        RequestOptions? capturedOptions;
        sessionManager.client.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          _,
          _,
        ) async {
          capturedOptions = options;
          return ResponseBody.fromString(
            '',
            HttpStatus.ok,
            headers: {
              'x-api-version': ['9'],
            },
          );
        });

        final version = await sessionManager.getApiVersion();

        expect(version, 9);
        expect(capturedOptions, isNotNull);
        expect(capturedOptions!.method, 'HEAD');
        expect(capturedOptions!.path, '/api/profile/');
      },
    );

    test(
      'getApiVersion falls back to minSupportedApiVersion when header is missing',
      () async {
        final sessionManager = SessionManagerImpl();
        addTearDown(sessionManager.resetSettings);

        sessionManager.client.httpClientAdapter = _FakeHttpClientAdapter((
          options,
          _,
          _,
        ) async {
          return ResponseBody.fromString('', HttpStatus.ok);
        });

        expect(await sessionManager.getApiVersion(), minSupportedApiVersion);
      },
    );
  });
}
