import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('the client waits past its own budget for the worker verdict', () async {
    var onTimeoutCalls = 0;
    final transport = SshWorkerLeaseStorageTransport.forTesting(
      (request) {
        // The worker answers just after the client's nominal budget.
        return Future.delayed(
          const Duration(milliseconds: 30),
          () => SshWorkerReply.failure(
            request.requestId,
            const SshWorkerErrorRecord(
              code: 'command_timeout',
              message: 'timed out',
            ),
          ),
        );
      },
      requestTimeout: const Duration(milliseconds: 10),
      onTimeout: () => onTimeoutCalls++,
    );
    final client = SshWorkerStorageClient(
      transport,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      client.run('sleep 1', timeout: const Duration(milliseconds: 10)),
      throwsA(
        isA<SshWorkerTransportException>().having(
          (error) => error.code,
          'code',
          'command_timeout',
        ),
      ),
    );
    expect(onTimeoutCalls, 0);
  });
}
