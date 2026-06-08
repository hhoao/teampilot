import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/codex/codex_auth_artifacts.dart';

void main() {
  group('CodexAuthArtifacts', () {
    test('accepts non-proxy API key', () {
      expect(
        CodexAuthArtifacts.authJsonIndicatesReady(
          '{"OPENAI_API_KEY":"sk-test"}',
        ),
        isTrue,
      );
    });

    test('rejects proxy managed token only', () {
      expect(
        CodexAuthArtifacts.authJsonIndicatesReady(
          '{"OPENAI_API_KEY":"PROXY_MANAGED"}',
        ),
        isFalse,
      );
    });

    test('accepts oauth style payload', () {
      expect(
        CodexAuthArtifacts.authJsonIndicatesReady(
          '{"tokens":{"access_token":"abc"}}',
        ),
        isTrue,
      );
    });
  });
}
