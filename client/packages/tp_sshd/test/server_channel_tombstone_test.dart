// VM-only: reads the connection's private tombstone sets through
// dart:mirrors to assert they stay bounded across channel churn.
@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  final connectionLibrary =
      reflectClass(SSHServerConnection).owner as LibraryMirror;

  Set<int> privateSet(SSHServerConnection connection, String name) {
    return reflect(connection)
        .getField(MirrorSystem.getSymbol(name, connectionLibrary))
        .reflectee as Set<int>;
  }

  test('churning many channels keeps the tombstone sets bounded', () async {
    // Final-review finding 2: every finished channel leaves an id in
    // _closingChannels/_reapedChannels until connection teardown, so a
    // long-lived pairing session with busy forwarding would grow the sets
    // by one entry per channel forever. The sets must compact.
    const churn = 300;
    final serverChannelIds = <int>[];
    final serverCloses = <int>[];
    final (connection, client) = await startRawAuthenticatedConnection(
      onServerMessage: (payload) {
        switch (SSHMessage.readMessageId(payload)) {
          case SSH_Message_Channel_Confirmation.messageId:
            final message = SSH_Message_Channel_Confirmation.decode(payload);
            serverChannelIds.add(message.senderChannel);
          case SSH_Message_Channel_Close.messageId:
            final message = SSH_Message_Channel_Close.decode(payload);
            serverCloses.add(message.recipientChannel);
        }
      },
    );

    // Open a session channel, close it, wait for the server's echoing
    // CHANNEL_CLOSE: one fully reaped tombstone per round.
    for (var i = 0; i < churn; i++) {
      client.sendPacket(
        SSH_Message_Channel_Open.session(
          senderChannel: i,
          initialWindowSize: 1024,
          maximumPacketSize: 1024,
        ).encode(),
      );
      await waitUntil(() => serverChannelIds.length > i);
      client.sendPacket(
        SSH_Message_Channel_Close(recipientChannel: serverChannelIds[i])
            .encode(),
      );
      await waitUntil(() => serverCloses.length > i);
    }

    final closing = privateSet(connection, '_closingChannels');
    final reaped = privateSet(connection, '_reapedChannels');
    // The cap holds: 300 finished channels did not leave 300 tombstones
    // behind.
    expect(closing.length + reaped.length, lessThanOrEqualTo(256));
    // The compaction dropped the oldest ids and kept the recent ones, so
    // the races of the channels that just finished stay tolerated.
    expect(reaped, contains(serverChannelIds[churn - 1]));
    expect(reaped, isNot(contains(serverChannelIds[0])));

    // The connection is still healthy after the compaction: one more
    // channel opens and closes cleanly.
    client.sendPacket(
      SSH_Message_Channel_Open.session(
        senderChannel: churn,
        initialWindowSize: 1024,
        maximumPacketSize: 1024,
      ).encode(),
    );
    await waitUntil(() => serverChannelIds.length > churn);
    client.sendPacket(
      SSH_Message_Channel_Close(recipientChannel: serverChannelIds[churn])
          .encode(),
    );
    await waitUntil(() => serverCloses.length > churn);

    await connection.close();
    client.close();
  });
}
