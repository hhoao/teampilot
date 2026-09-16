import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/connect_shell_result.dart';
import 'package:teampilot/services/launch/session_ssh_profile_reconnect.dart';

void main() {
  group('throwIfReconnectConnectFailed', () {
    test('failed connect result is a reconnect error', () {
      expect(
        () => throwIfReconnectConnectFailed(ConnectShellResult.failed),
        throwsA(isA<StateError>()),
      );
    });

    test('attached connect result is success', () {
      throwIfReconnectConnectFailed(ConnectShellResult.attached);
    });
  });
}
