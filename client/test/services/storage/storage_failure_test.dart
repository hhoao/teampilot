import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';
import 'package:teampilot/services/storage/storage_failure.dart';

void main() {
  test('worker transport codes count as transport failures', () {
    for (final code in [
      'transport_closed',
      'transport_error',
      'transport_timeout',
      'storage_not_connected',
      'socket_error',
      'handshake_error',
      'connection_refused',
    ]) {
      expect(
        isStorageTransportFailure(
          SshWorkerTransportException('failed', code: code),
        ),
        isTrue,
        reason: code,
      );
    }
  });

  test('missing-file SFTP errors are not transport failures', () {
    expect(
      isStorageTransportFailure(
        const SshWorkerTransportException('missing', code: 'sftp_no_such_file'),
      ),
      isFalse,
    );
    expect(
      isStorageTransportFailure(
        StateError('SSH profile worker message channel is closed'),
      ),
      isTrue,
    );
  });
}
