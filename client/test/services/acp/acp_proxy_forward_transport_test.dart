import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_proxy_forward_transport.dart';
import 'package:teampilot/services/ssh/ssh_forward_channel.dart';

class _Channel implements SshForwardByteChannel {
  final incomingController = StreamController<List<int>>.broadcast();
  final written = <List<int>>[];
  var closeCount = 0;

  @override
  Stream<List<int>> get incoming => incomingController.stream;

  @override
  void add(List<int> data) => written.add(List<int>.of(data));

  @override
  Future<void> close() async {
    closeCount++;
  }
}

void main() {
  test('close drops the forward socket and ignores a second close', () async {
    final channel = _Channel();
    final transport = AcpProxyForwardTransport(
      channel: channel,
      argv: const ['gemini', '--acp'],
      env: const {'HOME': '/home/u'},
    );
    transport.authenticateMethodId = 'oauth';

    expect(transport.launch.argv, const ['gemini', '--acp']);
    expect(transport.launch.env, const {'HOME': '/home/u'});
    expect(transport.launch.authenticateMethodId, 'oauth');

    transport.write('{"jsonrpc":"2.0","method":"initialize"}');
    expect(utf8.decode(channel.written.single), endsWith('\n'));

    await transport.close();
    expect(channel.closeCount, 1);
    expect(transport.isClosed, isTrue);

    transport.write('{"method":"session/prompt"}');
    expect(channel.written, hasLength(1));

    await transport.close();
    expect(channel.closeCount, 1);
  });
}
