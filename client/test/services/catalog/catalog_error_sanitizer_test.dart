import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_error_sanitizer.dart';

void main() {
  test('redacts bearer tokens and API keys', () {
    const raw =
        'request failed: Authorization: Bearer bearer-secret-123 '
        'x-api-key: api-secret-456 sk-live-secret-value';

    final sanitized = CatalogErrorSanitizer.sanitize(raw);

    expect(sanitized, contains('Authorization: Bearer [REDACTED]'));
    expect(sanitized, contains('x-api-key: [REDACTED]'));
    expect(sanitized, isNot(contains('bearer-secret-123')));
    expect(sanitized, isNot(contains('api-secret-456')));
    expect(sanitized, isNot(contains('sk-live-secret-value')));
  });

  test(
    'removes response-body fragments instead of exposing their contents',
    () {
      const raw =
          'HTTP 502 from catalog; response body: '
          '{"message":"private upstream details","token":"body-secret"}';

      final sanitized = CatalogErrorSanitizer.sanitize(raw);

      expect(sanitized, contains('HTTP 502 from catalog'));
      expect(sanitized, contains('[RESPONSE BODY OMITTED]'));
      expect(sanitized, isNot(contains('private upstream details')));
      expect(sanitized, isNot(contains('body-secret')));
    },
  );
}
