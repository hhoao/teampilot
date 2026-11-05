import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_connection_failure.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_errors.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('classifies host-key, auth, penalty, and refused failures', () {
    expect(
      sshWorkerErrorCode(SSHHostkeyError('rejected')),
      sshWorkerErrorHostKeyRejected,
    );
    expect(
      sshWorkerErrorCode(SSHAuthFailError('failed')),
      sshWorkerErrorAuthFailed,
    );
    expect(
      sshWorkerErrorCode(
        SSHAuthAbortError('aborted', SSHHostkeyError('rejected')),
      ),
      sshWorkerErrorHostKeyRejected,
    );
    expect(
      sshWorkerErrorCode(
        SSHHandshakeError('Invalid version: Not allowed at this time'),
      ),
      sshWorkerErrorSshdPenalty,
    );
    expect(
      sshWorkerErrorCode(
        SSHSocketError(
          SocketException('refused', osError: OSError('refused', 111)),
        ),
      ),
      sshWorkerErrorConnectionRefused,
    );
  });

  test('UI failure helpers understand worker-flattened codes', () {
    const hostKey = SshWorkerTransportException(
      'failed',
      code: sshWorkerErrorHostKeyRejected,
    );
    const auth = SshWorkerTransportException(
      'failed',
      code: sshWorkerErrorAuthFailed,
    );
    const penalty = SshWorkerTransportException(
      'failed',
      code: sshWorkerErrorSshdPenalty,
    );
    const refused = SshWorkerTransportException(
      'failed',
      code: sshWorkerErrorConnectionRefused,
    );

    expect(isSshHostKeyFailure(hostKey), isTrue);
    expect(isSshHostKeyFailure(auth), isFalse);
    expect(isSshAuthFailure(auth), isTrue);
    expect(isSshAuthFailure(hostKey), isTrue);
    expect(isSshdPenaltyRefusal(penalty), isTrue);
    expect(isTcpConnectionRefused(refused), isTrue);
  });
}
