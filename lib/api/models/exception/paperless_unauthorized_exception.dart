class PaperlessUnauthorizedException implements Exception {
  final String? message;
  final int? statusCode;

  PaperlessUnauthorizedException(this.message, {this.statusCode});

  bool get isInvalidToken => statusCode == 401;

  @override
  String toString() => 'PaperlessUnauthorizedException: $message';
}
