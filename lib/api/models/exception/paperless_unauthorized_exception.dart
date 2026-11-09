class PaperlessUnauthorizedException implements Exception {
  final String? message;

  PaperlessUnauthorizedException(this.message);

  @override
  String toString() => (message != null && message!.isNotEmpty)
      ? 'PaperlessUnauthorizedException: $message'
      : 'PaperlessUnauthorizedException';
}
