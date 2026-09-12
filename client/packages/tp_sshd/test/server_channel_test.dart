@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

void main() {
  test('client can open a session channel', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // dartssh2 has no public open-by-type API (execute/shell would block on
    // the request reply), so the harness opens the session channel through
    // the client's own session-channel opener.
    final controller = await openClientSessionChannel(client);
    expect(controller.channel.channelId, greaterThanOrEqualTo(0));
    // The server-assigned channel number from the confirmation.
    expect(controller.remoteId, greaterThanOrEqualTo(0));
    await server.close();
    await client.close();
  });

  test('unknown channel type gets open-failure', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // forwardLocal() opens a 'direct-tcpip' channel, which this server does
    // not serve until Task 9.
    //
    // The plan text says "reason 3 (admin prohibited)", but reason 3 is
    // codeUnknownChannelType in both the fork's API and RFC 4254 §5.1, and
    // would be the wrong semantic for a recognized-but-unserved type; the
    // named constant for the stated semantic (reason 1,
    // codeAdministrativelyProhibited) wins per the controller ruling that
    // real fork API names take precedence. Both the constant and the raw
    // wire value are pinned so a future constant renumbering cannot slip
    // through silently.
    await expectLater(
      client.forwardLocal('127.0.0.1', 80),
      throwsA(
        isA<SSHChannelOpenError>()
            .having(
              (error) => error.code,
              'code',
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
            )
            .having((error) => error.code, 'wire value', 1),
      ),
    );
    await server.close();
    await client.close();
  });

  test('channel opens beyond the per-connection cap are refused', () async {
    final (client, connection) = await startDualConnection(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // The default cap is 10, OpenSSH's own: the first ten session channels
    // confirm...
    for (var i = 0; i < 10; i++) {
      await openClientSessionChannel(client);
    }
    expect(connection.channels.length, 10);

    // ...and the eleventh is refused with reason 4, resource shortage, so one
    // connection cannot pin unbounded channel state on the server. The wire
    // value is pinned alongside the constant, like the admin-prohibited test
    // above.
    await expectLater(
      openClientSessionChannel(client),
      throwsA(
        isA<SSHChannelOpenError>()
            .having(
              (error) => error.code,
              'code',
              SSH_Message_Channel_Open_Failure.codeResourceShortage,
            )
            .having((error) => error.code, 'wire value', 4),
      ),
    );
    // The refused open left the channel table untouched.
    expect(connection.channels.length, 10);

    await connection.close();
    await client.close();
  });

  test('keepalive global request is answered', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // ping() sends keepalive@openssh.com with wantReply and only completes
    // once the server replies; silence would hang the future.
    await expectLater(client.ping(), completes);
    await server.close();
    await client.close();
  });

  test('other global requests are refused', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
    );
    // tcpip-forward is Task 9; until then the Request_Failure reply makes
    // forwardRemote return null instead of throwing.
    expect(await client.forwardRemote(host: '127.0.0.1', port: 0), isNull);
    await server.close();
    await client.close();
  });

  group('SSHServerChannel', () {
    test('routes client data to the input stream', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;
      expect(serverChannel.channelType, 'session');

      final input = expectLater(
        serverChannel.input,
        emitsInOrder([
          orderedEquals([1, 2, 3]),
          orderedEquals([4, 5]),
        ]),
      );
      clientChannel.addData(Uint8List.fromList([1, 2, 3]));
      clientChannel.addData(Uint8List.fromList([4, 5]));
      await input;
      await connection.close();
      await client.close();
    });

    test('routes extended client data to the extended input stream', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;

      final input = expectLater(
        serverChannel.input,
        emitsInOrder([
          orderedEquals([7, 8]),
        ]),
      );
      final extendedInput = expectLater(
        serverChannel.extendedInput,
        emitsInOrder([
          orderedEquals([9, 10, 11]),
        ]),
      );
      clientChannel.addData(Uint8List.fromList([7, 8]));
      clientChannel.addData(Uint8List.fromList([9, 10, 11]), type: 1);
      await input;
      await extendedInput;
      await connection.close();
      await client.close();
    });

    test('writes data back to the client', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;
      // The client's channel stream is single-subscription; a StreamIterator
      // reads it across both writes.
      final clientInput = StreamIterator(clientChannel.stream);

      serverChannel.write(Uint8List.fromList([7, 8, 9]));
      expect(await clientInput.moveNext(), isTrue);
      expect(clientInput.current.bytes, orderedEquals([7, 8, 9]));
      expect(clientInput.current.isExtendedData, isFalse);

      serverChannel.writeExtended(Uint8List.fromList([1, 2]));
      expect(await clientInput.moveNext(), isTrue);
      expect(clientInput.current.bytes, orderedEquals([1, 2]));
      expect(clientInput.current.isExtendedData, isTrue);
      await clientInput.cancel();

      await connection.close();
      await client.close();
    });

    test('writes are chunked to the peer maximum packet size', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;

      // The client fails any channel whose packets exceed the 32768 bytes it
      // advertised, so every event staying under that bound (and the
      // reassembled payload matching) proves the server chunks correctly.
      final payload = Uint8List(128 * 1024 + 311);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = (i * 7) & 0xff;
      }
      final clientInput = StreamIterator(clientChannel.stream);
      final received = BytesBuilder(copy: false);
      var packets = 0;
      serverChannel.write(payload);
      while (received.length < payload.length) {
        expect(await clientInput.moveNext(), isTrue);
        final bytes = clientInput.current.bytes;
        expect(bytes.length, lessThanOrEqualTo(32768));
        received.add(bytes);
        packets += 1;
      }
      await clientInput.cancel();
      expect(packets, greaterThan(1));
      expect(received.takeBytes(), orderedEquals(payload));

      await connection.close();
      await client.close();
    });

    test('close from the server completes the client channel', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;

      // close() sends EOF then CHANNEL_CLOSE: the client's data stream ends
      // and its channel done future completes.
      final clientStreamDone = expectLater(clientChannel.stream, emitsDone);
      serverChannel.close();
      await clientChannel.done;
      await clientStreamDone;
      expect(serverChannel.isClosed, isTrue);
      expect(connection.channels, isEmpty);

      await connection.close();
      await client.close();
    });

    test('client close ends the input and is finished by the server', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientChannel = (await openClientSessionChannel(client)).channel;
      final SSHServerChannel serverChannel = connection.channels.values.single;

      // The client's close() sends EOF and waits for the server to close too
      // (dartssh2 does not send CHANNEL_CLOSE unprompted). The server honors
      // the half-close: input ends, but the channel stays open until the
      // server finishes it.
      final inputDone = expectLater(serverChannel.input, emitsDone);
      final clientClosed = clientChannel.close();
      await inputDone;
      expect(serverChannel.receivedEof, isTrue);
      expect(serverChannel.isClosed, isFalse);
      expect(connection.channels, isNotEmpty);

      serverChannel.close();
      await clientClosed;
      await serverChannel.done;
      expect(connection.channels, isEmpty);

      await connection.close();
      await client.close();
    });

    test('channel requests reach onRequest and are acknowledged', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientController = await openClientSessionChannel(client);
      final SSHServerChannel serverChannel = connection.channels.values.single;

      final requests = <String>[];
      serverChannel.onRequest = (channel, request) async {
        requests.add(request.requestType);
        return true;
      };
      final accepted = await clientController.sendEnv('FOO', 'BAR');
      expect(accepted, isTrue);
      expect(requests, ['env']);

      await connection.close();
      await client.close();
    });

    test('channel requests the session layer does not serve are refused',
        () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientController = await openClientSessionChannel(client);
      // The connection wires every channel to handleSessionRequest, which
      // serves the structured exec grammar and the pty half (pty-req, env,
      // shell, window-change, signal) plus the sftp subsystem. This pair
      // configures no sftpFileSystem, so the subsystem request is refused
      // instead of left hanging; with one configured it is served (the
      // server_sftp_test.dart dual tests cover that branch).
      final accepted = await clientController.sendSubsystem('sftp');
      expect(accepted, isFalse);

      await connection.close();
      await client.close();
    });
  });

  group('window accounting', () {
    // These drive the protocol with a raw authenticated transport, because
    // the windows and packet sizes a real client uses (2 MiB / 32 KiB) make
    // stalls and grants too slow to observe over the in-memory pair.
    test('outgoing data stalls on a spent window and resumes on adjust',
        () async {
      SSH_Message_Channel_Confirmation? confirmation;
      final dataPackets = <int>[];
      final opened = Completer<void>();
      final (connection, client) = await startRawAuthenticatedConnection(
        onServerMessage: (payload) {
          switch (SSHMessage.readMessageId(payload)) {
            case SSH_Message_Channel_Confirmation.messageId:
              confirmation = SSH_Message_Channel_Confirmation.decode(payload);
              if (!opened.isCompleted) opened.complete();
            case SSH_Message_Channel_Data.messageId:
              dataPackets
                  .add(SSH_Message_Channel_Data.decode(payload).data.length);
          }
        },
      );

      // A 10-byte window with 4-byte packets: a real client never offers
      // this, which is exactly what makes the stall observable.
      client.sendPacket(
        SSH_Message_Channel_Open.session(
          senderChannel: 7,
          initialWindowSize: 10,
          maximumPacketSize: 4,
        ).encode(),
      );
      await opened.future;

      expect(confirmation!.recipientChannel, 7);
      expect(confirmation!.senderChannel, 0); // our first channel number
      expect(
        confirmation!.initialWindowSize,
        SSHServerChannel.initialReceiveWindow,
      );
      expect(
        confirmation!.maximumPacketSize,
        SSHServerChannel.maximumPacketSize,
      );

      final SSHServerChannel channel = connection.channels.values.single;
      channel.write(Uint8List.fromList(List.generate(25, (i) => i)));

      // 4 + 4 + 2 bytes fit the granted window; the rest waits for credit.
      await waitUntil(() => dataPackets.length == 3);
      expect(dataPackets, [4, 4, 2]);
      // Still stalled: nothing more arrives while the window is spent.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(dataPackets.length, 3);

      client.sendPacket(
        SSH_Message_Channel_Window_Adjust(
          recipientChannel: channel.ourChannel,
          bytesToAdd: 15,
        ).encode(),
      );
      await waitUntil(() => dataPackets.length == 7);
      expect(dataPackets, [4, 4, 2, 4, 4, 4, 3]);

      await connection.close();
      client.close();
    });

    test('close flushes queued window-credit data before finishing', () async {
      final dataLengths = <int>[];
      var eofSeen = false;
      var closeSeen = false;
      final opened = Completer<void>();
      final (connection, client) = await startRawAuthenticatedConnection(
        onServerMessage: (payload) {
          switch (SSHMessage.readMessageId(payload)) {
            case SSH_Message_Channel_Confirmation.messageId:
              if (!opened.isCompleted) opened.complete();
            case SSH_Message_Channel_Data.messageId:
              dataLengths
                  .add(SSH_Message_Channel_Data.decode(payload).data.length);
            case SSH_Message_Channel_EOF.messageId:
              eofSeen = true;
            case SSH_Message_Channel_Close.messageId:
              closeSeen = true;
          }
        },
      );

      // A 10-byte window: a real client never offers this, which is exactly
      // what makes the close-time tail observable.
      client.sendPacket(
        SSH_Message_Channel_Open.session(
          senderChannel: 5,
          initialWindowSize: 10,
          maximumPacketSize: 32768,
        ).encode(),
      );
      await opened.future;
      final SSHServerChannel channel = connection.channels.values.single;

      // 25 bytes against that window: 10 go out immediately, the 15-byte tail
      // queues for credit.
      channel.write(Uint8List.fromList(List.generate(25, (i) => i)));
      await waitUntil(() => dataLengths.length == 1);
      expect(dataLengths, [10]);

      channel.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The close is waiting on the tail instead of dropping it: no EOF, no
      // CHANNEL_CLOSE, and the channel is still live server-side.
      expect(eofSeen, isFalse);
      expect(closeSeen, isFalse);
      expect(channel.isClosed, isFalse);

      // The client grants the window: the whole tail flushes, and only then
      // do EOF and CHANNEL_CLOSE follow — the payload is delivered in full.
      client.sendPacket(
        SSH_Message_Channel_Window_Adjust(
          recipientChannel: channel.ourChannel,
          bytesToAdd: 15,
        ).encode(),
      );
      await waitUntil(() => channel.isClosed);
      expect(dataLengths, [10, 15]);
      expect(eofSeen, isTrue);
      expect(closeSeen, isTrue);
      expect(connection.channels, isEmpty);

      await connection.close();
      client.close();
    });

    test('a window that never opens gives up after the close flush bound',
        () async {
      // Directly constructed, like the channel the connection would build
      // for a 4-byte-window peer — but with a short flush bound, so the
      // fallback is observable without waiting the product default.
      final sentIds = <int>[];
      var sentDataBytes = 0;
      SSHServerChannel? closedChannel;
      final channel = SSHServerChannel(
        recipientChannel: 9,
        ourChannel: 0,
        channelType: 'session',
        peerInitialWindowSize: 4,
        peerMaximumPacketSize: 32768,
        closeFlushTimeout: const Duration(milliseconds: 50),
        sendPacket: (payload) {
          sentIds.add(SSHMessage.readMessageId(payload));
          if (SSHMessage.readMessageId(payload) ==
              SSH_Message_Channel_Data.messageId) {
            sentDataBytes +=
                SSH_Message_Channel_Data.decode(payload).data.length;
          }
        },
        onClosed: (channel) => closedChannel = channel,
      );

      // 10 bytes against the 4-byte window: 4 go out, 6 stall.
      channel.write(Uint8List.fromList(List.generate(10, (i) => i)));
      channel.close();
      expect(sentIds, [SSH_Message_Channel_Data.messageId]);
      expect(sentDataBytes, 4);

      // No window adjustment ever arrives. After the bound the channel
      // finishes anyway — EOF and CHANNEL_CLOSE are sent, and the stalled
      // tail is dropped rather than blocking the channel forever.
      await channel.done.timeout(const Duration(seconds: 2));
      expect(
        sentIds,
        containsAll([
          SSH_Message_Channel_Data.messageId,
          SSH_Message_Channel_EOF.messageId,
          SSH_Message_Channel_Close.messageId,
        ]),
      );
      expect(sentDataBytes, 4);
      expect(closedChannel, same(channel));
    });

    test('the receive window is granted back as the client sends', () async {
      final adjusts = <int>[];
      final input = BytesBuilder(copy: false);
      final opened = Completer<void>();
      final (connection, client) = await startRawAuthenticatedConnection(
        onServerMessage: (payload) {
          switch (SSHMessage.readMessageId(payload)) {
            case SSH_Message_Channel_Confirmation.messageId:
              if (!opened.isCompleted) opened.complete();
            case SSH_Message_Channel_Window_Adjust.messageId:
              adjusts.add(
                SSH_Message_Channel_Window_Adjust.decode(payload).bytesToAdd,
              );
          }
        },
      );

      client.sendPacket(
        SSH_Message_Channel_Open.session(
          senderChannel: 3,
          initialWindowSize: 2 * 1024 * 1024,
          maximumPacketSize: 32768,
        ).encode(),
      );
      await opened.future;
      final SSHServerChannel channel = connection.channels.values.single;
      final inputSubscription = channel.input.listen(input.add);

      client.sendPacket(
        SSH_Message_Channel_Data(
          recipientChannel: channel.ourChannel,
          data: Uint8List.fromList([1, 2, 3, 4]),
        ).encode(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Small consumption does not grant yet: the refill rules wait for
      // half the window or three maximum packets.
      expect(adjusts, isEmpty);

      for (var i = 0; i < 4; i++) {
        client.sendPacket(
          SSH_Message_Channel_Data(
            recipientChannel: channel.ourChannel,
            data: Uint8List(32768),
          ).encode(),
        );
      }
      await waitUntil(() => input.length == 4 + 4 * 32768);
      // 4 + 3 * 32768 = 98308 bytes were consumed when the third bulk packet
      // crossed the three-packet threshold, and exactly that was granted.
      expect(adjusts, [98308]);
      await inputSubscription.cancel();

      await connection.close();
      client.close();
    });
  });
}
