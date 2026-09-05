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

  test('detects sshd PerSourcePenalties refusals', () {
    final penalty = SSHHandshakeError('Invalid version: Not allowed at this time');
    expect(isSshdPenaltyRefusal(penalty), isTrue);
    expect(
      sshConnectionFailureUserMessage(penalty, l10n),
      l10n.sshPenaltyRefused,
    );

    final otherHandshake = SSHHandshakeError('Invalid version: HTTP/1.1 400');
    expect(isSshdPenaltyRefusal(otherHandshake), isFalse);
    expect(isSshdPenaltyRefusal(SSHAuthFailError('no')), isFalse);
  });

  test('maps stored penalty detail strings for display', () {
    expect(
      sshErrorDetailUserMessage(
        'SSHHandshakeError(Invalid version: Not allowed at this time)',
        l10n,
      ),
      l10n.sshPenaltyRefused,
    );
    expect(
      sshErrorDetailUserMessage('SocketException: connection refused', l10n),
      'SocketException: connection refused',
    );
    expect(sshErrorDetailUserMessage(null, l10n), '');
  });
}
