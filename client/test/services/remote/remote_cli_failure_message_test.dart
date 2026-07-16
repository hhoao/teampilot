import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';

void main() {
  test('remoteCliFailureMessage strips Bad state prefix from StateError', () {
    expect(
      remoteCliFailureMessage(
        StateError('Remote Node/npm install failed (exit 1): curl: 403'),
      ),
      'Remote Node/npm install failed (exit 1): curl: 403',
    );
  });

  test('remoteCliFailureMessage keeps other errors as toString', () {
    expect(remoteCliFailureMessage(Exception('boom')), 'Exception: boom');
  });
}
