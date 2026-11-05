import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_exec_proxy.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

void main() {
  test('exec proxy serializes and chunks large stdin writes', () async {
    final sizes = <int>[];
    var stdinClosed = false;
    final closeSeen = Completer<void>();
    final proxy = SshWorkerExecProxy(
      id: 'exec-1',
      acknowledgeRemote: (_) async {},
      writeRemote: (data) async => sizes.add(data.length),
      closeStdinRemote: () async {
        stdinClosed = true;
        closeSeen.complete();
      },
      killRemote: () async {},
      closeRemote: () async {},
      onFinished: () {},
    );

    proxy.write(Uint8List(sshWorkerMaxChunkSize + 10));
    proxy.closeStdin();
    await closeSeen.future.timeout(const Duration(seconds: 1));

    expect(sizes, [sshWorkerMaxChunkSize, 10]);
    expect(stdinClosed, isTrue);
  });
}
