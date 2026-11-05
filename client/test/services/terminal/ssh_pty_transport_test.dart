import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/chat/runtime/pty/ssh_pty_transport.dart';

void main() {
  test(
    'forwards non-blocking terminal input, resize, output, and exit code',
    () async {
      final channel = _FakePtyChannel();
      final transport = SshPtyTransport(channel: channel);
      final output = <Uint8List>[];
      final subscription = transport.output.listen(output.add);

      transport.write(Uint8List.fromList([1, 2]));
      transport.resize(24, 80);
      channel.outputController.add(Uint8List.fromList([3, 4]));
      channel.doneCompleter.complete(9);
      await channel.outputController.close();

      expect(channel.writes.single, [1, 2]);
      expect(channel.resizes.single, (24, 80));
      expect(output.single, [3, 4]);
      expect(await transport.done, 9);
      await subscription.cancel();
    },
  );
}

final class _FakePtyChannel implements SshWorkerPtyChannel {
  final outputController = StreamController<Uint8List>();
  final doneCompleter = Completer<int>();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  var closeCount = 0;

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  void close() => closeCount++;

  @override
  void resize(int rows, int columns) => resizes.add((rows, columns));

  @override
  void write(Uint8List data) => writes.add(data);
}
