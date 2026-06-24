import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/remote/reverse_tunnel.dart';

/// SshReverseTunnel is a thin wrapper over dartssh2 forwardRemote; the part with
/// logic is the channel mapping, captured by StreamTunnelChannel (which
/// SshReverseTunnel uses to adapt each SSHForwardChannel). Test the mapping with
/// in-memory primitives (no real SSH).
void main() {
  test('StreamTunnelChannel maps input stream, add sink and close', () async {
    final incoming = StreamController<List<int>>();
    final added = <List<int>>[];
    var closed = false;

    final channel = StreamTunnelChannel(
      input: incoming.stream,
      onAdd: added.add,
      onClose: () async => closed = true,
    );

    final received = <List<int>>[];
    channel.input.listen(received.add);

    incoming.add([1, 2, 3]);
    channel.add([9, 8]);
    await Future<void>.delayed(Duration.zero);

    expect(received, [
      [1, 2, 3],
    ]);
    expect(added, [
      [9, 8],
    ]);

    await channel.close();
    expect(closed, isTrue);
    await incoming.close();
  });
}
