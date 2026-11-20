import 'package:dio/dio.dart';
import 'package:paperless_mobile/api/paperless_api.dart';

class DioUnauthorizedInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      final data = err.response!.data;
      String? message;
      if (PaperlessServerMessageException.canParse(data)) {
        final exception = PaperlessServerMessageException.fromJson(data);
        message = exception.detail;
      }
      handler.reject(
        DioException(
          message: message,
          requestOptions: err.requestOptions,
          error: PaperlessUnauthorizedException(
            message,
            statusCode: statusCode,
          ),
          response: err.response,
          type: DioExceptionType.badResponse,
        ),
      );
    } else {
      handler.next(err);
    }
  }
}
