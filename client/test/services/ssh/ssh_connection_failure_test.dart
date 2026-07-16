import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/services/ssh/ssh_connection_failure.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('unwraps SSHAuthAbortError reason for logging and UI', () {
    final error = SSHAuthAbortError(
      'Connection closed before authentication',
      SSHHostkeyError('Hostkey verification failed'),
    );

    expect(sshConnectionFailureCause(error), isA<SSHHostkeyError>());
    expect(
      sshConnectionFailureLogMessage(error),
      contains('cause: SSHHostkeyError'),
    );
    expect(
      sshConnectionFailureUserMessage(error, l10n),
      l10n.sshProfileTestFailedHostKey,
    );
  });

  test('maps auth fail errors to auth user message', () {
    final error = SSHAuthFailError('bad password');
    expect(
      sshConnectionFailureUserMessage(error, l10n),
      l10n.sshProfileTestFailedAuth,
    );
  });
}
