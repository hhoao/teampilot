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
    await expectLater(
      client.forwardLocal('127.0.0.1', 80),
      throwsA(
        isA<SSHChannelOpenError>().having(
          (error) => error.code,
          'code',
          SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        ),
      ),
    );
    await server.close();
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
      serverChannel.onRequest = (channel) async {
        requests.add(channel.currentRequest!.requestType);
      };
      final accepted = await clientController.sendEnv('FOO', 'BAR');
      expect(accepted, isTrue);
      expect(requests, ['env']);

      await connection.close();
      await client.close();
    });

    test('unhandled channel requests are refused', () async {
      final (client, connection) = await startDualConnection(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
      );
      final clientController = await openClientSessionChannel(client);
      // No onRequest handler is installed: the request must be refused, not
      // left hanging, until Tasks 6-7 implement the session requests.
      final accepted = await clientController.sendEnv('FOO', 'BAR');
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
