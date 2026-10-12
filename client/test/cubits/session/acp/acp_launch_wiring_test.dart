import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';

void main() {
  test(
    'process exit during authenticate is AcpAuthenticateException, not a flag reject',
    () {
      final error = classifyHandshakeProcessExit(
        exitCode: 1,
        authenticating: true,
      );
      expect(error, isA<AcpAuthenticateException>());
    },
  );

  test(
    'non-zero exit before handshake without authenticate is AcpFlagRejected',
    () {
      final error = classifyHandshakeProcessExit(
        exitCode: 1,
        authenticating: false,
      );
      expect(error, isA<AcpFlagRejected>());
    },
  );

  test('clean exit before handshake is StateError', () {
    final error = classifyHandshakeProcessExit(
      exitCode: 0,
      authenticating: false,
    );
    expect(error, isA<StateError>());
  });
}
