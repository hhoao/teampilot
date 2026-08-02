import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_login_url_detector.dart';

void main() {
  const detector = CredentialLoginUrlDetector();

  test('extracts https URL and strips trailing punctuation', () {
    final uris = detector.extractAll(
      'Visit https://authenticator.cursor.sh/login?code=abc).',
    );
    expect(uris.single.toString(), 'https://authenticator.cursor.sh/login?code=abc');
  });

  test('prefers auth-like host when multiple https URLs present', () {
    final uris = detector.extractAll(
      'Docs https://example.com/docs then https://claude.ai/oauth/authorize?x=1',
    );
    expect(uris.first.host, 'claude.ai');
  });

  test('returns empty when no https URL', () {
    expect(detector.extractAll('no link http://insecure.example'), isEmpty);
  });
}
