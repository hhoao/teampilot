import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_action_result.dart';
import 'package:teampilot/services/provider/opencode/opencode_auth_artifacts.dart';

void main() {
  group('OpencodeAuthArtifacts', () {
    test('accepts api credential entry', () {
      expect(
        OpencodeAuthArtifacts.authJsonIndicatesReady(
          '{"openai":{"type":"api","key":"sk-test"}}',
          'openai',
        ),
        isTrue,
      );
    });

    test('accepts oauth credential entry', () {
      expect(
        OpencodeAuthArtifacts.authJsonIndicatesReady(
          '{"anthropic":{"type":"oauth","access":"token","refresh":"r","expires":999}}',
          'anthropic',
        ),
        isTrue,
      );
    });

    test('rejects missing provider key', () {
      expect(
        OpencodeAuthArtifacts.authJsonIndicatesReady(
          '{"openai":{"type":"api","key":"sk-test"}}',
          'google',
        ),
        isFalse,
      );
    });
  });

  group('CredentialActionResult', () {
    test('failure carries code and path', () {
      final result = CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.sourceMissing,
          path: '/tmp/auth.json',
        ),
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.sourceMissing);
      expect(result.failure?.path, '/tmp/auth.json');
    });
  });
}
