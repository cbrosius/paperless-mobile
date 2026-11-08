import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:paperless_mobile/constants.dart';

class ApiVersionHeaderInterceptor extends Interceptor {
  final int? Function() getApiVersion;
  ApiVersionHeaderInterceptor(this.getApiVersion);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['skipApiVersion'] == true) {
      handler.next(options);
      return;
    }

    final apiVersion = getApiVersion();
    if (apiVersion != null) {
      final effectiveApiVersion = min(
        max(minSupportedApiVersion, apiVersion),
        latestSupportedApiVersion,
      );

      options.headers.addEntries([
        MapEntry(
          HttpHeaders.acceptHeader,
          'application/json; version=$effectiveApiVersion',
        ),
      ]);
    } else {
      options.headers.addEntries([
        MapEntry(HttpHeaders.acceptHeader, 'application/json'),
      ]);
    }

    handler.next(options);
  }
}
