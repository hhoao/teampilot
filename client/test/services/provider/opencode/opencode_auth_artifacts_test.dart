import 'package:flutter_test/flutter_test.dart';
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
}
