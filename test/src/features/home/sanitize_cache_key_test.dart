import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/features/home/view/home_shell_widget.dart';

void main() {
  group('HomeShellWidget.sanitizeCacheKey (#675)', () {
    test('sanitizes email and URL characters for safe cache directories', () {
      expect(
        HomeShellWidget.sanitizeCacheKey('demo@paperless.example.com'),
        equals('demo_paperless_example_com'),
      );
      expect(
        HomeShellWidget.sanitizeCacheKey('user@https://server.domain.com:8000'),
        equals('user_https___server_domain_com_8000'),
      );
      expect(
        HomeShellWidget.sanitizeCacheKey('valid-user_123'),
        equals('valid-user_123'),
      );
    });
  });
}
