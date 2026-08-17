import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_login_url_detector.dart';

void main() {
  const detector = CredentialLoginUrlDetector();

  test('extracts https URL and strips trailing punctuation', () {
    final uris = detector.extractAll(
      'Visit https://authenticator.cursor.sh/login?code=abc).',
    );
    expect(
      uris.single.toString(),
      'https://authenticator.cursor.sh/login?code=abc',
    );
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

  test('strips ANSI before extracting URL and device code', () {
    final text =
        'Open \x1b[94mhttps://auth.openai.com/codex/device\x1b[0m\n'
        'code \x1b[94m5HB1-3GASL\x1b[0m\n';
    expect(detector.extractAll(text).single.host, 'auth.openai.com');
    expect(detector.extractDeviceCodes(text), ['5HB1-3GASL']);
  });

  test('extracts Codex device-auth banner with indented code and URL', () {
    const text = '''
Welcome to Codex [v0.147.0]
OpenAI's command-line coding agent

Follow these steps to sign in with ChatGPT using device code authorization:

1. Open this link in your browser and sign in to your account
   https://auth.openai.com/codex/device

2. Enter this one-time code (expires in 15 minutes)
   WO3M-X8OIF

Continue only if you started this login in Codex. If a website or another person gave you this code, cancel.
''';
    expect(
      detector.extractAll(text).single.toString(),
      'https://auth.openai.com/codex/device',
    );
    expect(detector.extractDeviceCodes(text), ['WO3M-X8OIF']);
  });

  test('extracts Codex device code when newlines collapse into following text', () {
    const text =
        'Follow these steps to sign in with ChatGPT using device code authorization:'
        'Open this link in your browser and sign in to your account\n'
        'https://auth.openai.com/codex/deviceEnter this one-time code (expires in 15 minutes)\n'
        'WO3M-X8OIFContinue only if you started this login in Codex.';
    expect(
      detector.extractAll(text).single.toString(),
      'https://auth.openai.com/codex/device',
    );
    expect(detector.extractDeviceCodes(text), ['WO3M-X8OIF']);
  });
}
