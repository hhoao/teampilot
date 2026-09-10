@TestOn('vm')
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart';
import 'package:dartssh2/src/ssh_channel.dart' show SSHChannel, SSHChannelData;
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'memory_sftp_filesystem.dart';

/// Hand-driven SFTP wire on one session channel: frames outgoing packets and
/// reassembles the length-prefixed replies out of the channel's data stream,
/// for requests the fork's client never sends (a READ asking for a whole
/// uint32 of bytes).
class _RawSftpWire {
  _RawSftpWire(this._channel) {
    _channel.stream.listen(_onData);
  }

  final SSHChannel _channel;
  final _pending = BytesBuilder(copy: false);
  final _replies = Queue<Uint8List>();
  Completer<Uint8List>? _replyWaiter;

  /// Frames [packet] and sends it as channel data.
  void send(SftpPacket packet) {
    final payload = packet.encode();
    final framed = BytesBuilder(copy: false)
      ..add(_lengthPrefix(payload.length))
      ..add(payload);
    _channel.addData(framed.takeBytes());
  }

  /// Completes with the next reply payload (type byte first, no length
  /// prefix).
  Future<Uint8List> receive() {
    if (_replies.isNotEmpty) return Future.value(_replies.removeFirst());
    _replyWaiter = Completer<Uint8List>();
    return _replyWaiter!.future;
  }

  void _onData(SSHChannelData data) {
    var bytes = (BytesBuilder(copy: false)
          ..add(_pending.takeBytes())
          ..add(data.bytes))
        .takeBytes();
    while (bytes.length >= 4) {
      final length = ByteData.sublistView(bytes, 0, 4).getUint32(0);
      if (bytes.length < 4 + length) break;
      _emitReply(Uint8List.sublistView(bytes, 4, 4 + length));
      bytes = Uint8List.sublistView(bytes, 4 + length);
    }
    _pending.add(bytes);
  }

  void _emitReply(Uint8List packet) {
    final waiter = _replyWaiter;
    if (waiter != null) {
      _replyWaiter = null;
      waiter.complete(packet);
    } else {
      _replies.add(packet);
    }
  }

  Uint8List _lengthPrefix(int length) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, length);
    return bytes;
  }
}

void main() {
  late MemorySftpFileSystem fs;

  setUp(() => fs = MemorySftpFileSystem());

  Future<(SSHClient, SSHServer)> connect() => startDualPair(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
        sftpFileSystem: fs,
      );

  test('subsystem request for sftp is served when a filesystem is configured',
      () async {
    final (client, server) = await connect();
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendSubsystem('sftp'), isTrue);

    client.close();
    await server.close();
  });

  test('subsystem request for an unknown name is refused', () async {
    final (client, server) = await connect();
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendSubsystem('not-sftp'), isFalse);

    client.close();
    await server.close();
  });

  test('mkdir / write / read / stat / list round trip', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/demo');
    final file = await sftp.open(
      '/demo/hello.txt',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    await file.writeBytes(Uint8List.fromList('hello tp_sshd'.codeUnits));
    await file.close();

    final attrs = await sftp.stat('/demo/hello.txt');
    expect(attrs.size, 13);

    final reader = await sftp.open('/demo/hello.txt');
    final readBack = await reader.readBytes();
    await reader.close();
    expect(String.fromCharCodes(readBack), 'hello tp_sshd');

    final names = await sftp.listdir('/demo');
    expect(names.map((n) => n.filename), contains('hello.txt'));
    client.close();
    await server.close();
  });

  test('rename, remove, rmdir', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/a');
    final f = await sftp.open(
      '/a/x',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    await f.writeBytes(Uint8List.fromList([1, 2, 3]));
    await f.close();
    await sftp.rename('/a/x', '/a/y');
    await sftp.remove('/a/y');
    await sftp.rmdir('/a');
    await expectLater(sftp.stat('/a/y'), throwsA(anything));
    client.close();
    await server.close();
  });

  test('missing file returns SSH_FX_NO_SUCH_FILE status, not a crash',
      () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await expectLater(sftp.stat('/nope'), throwsA(isA<SftpStatusError>()));
    client.close();
    await server.close();
  });

  // The in-memory listing is one-shot and returns the whole directory in a
  // single batch, so a directory big enough to encode over the 256 KiB SFTP
  // packet limit forces the server to page: every NAME packet must stay
  // under the limit (the fork's client destroys the channel otherwise), and
  // the client's listdir loop must still see every entry across the batches
  // until the EOF status ends it.
  test(
      'large directory is served as multiple READDIR batches under the packet limit',
      () async {
    const entryCount = 6000;
    fs.createDirectory('/big');
    for (var i = 0; i < entryCount; i++) {
      fs.createFile('/big/dir-entry-$i');
    }
    // The whole-directory NAME packet would be far over the limit; without
    // paging the channel dies and listdir never completes.
    final (client, server) = await connect();
    final sftp = await client.sftp();
    final names = await sftp.listdir('/big');
    // A set both checks membership cheaply and, compared against the raw
    // count, proves no entry was served twice across the batches.
    final filenames = names.map((n) => n.filename).toSet();
    expect(names.length, entryCount + 2);
    expect(filenames.length, entryCount + 2);
    expect(filenames, containsAll(const ['.', '..']));
    for (var i = 0; i < entryCount; i++) {
      expect(filenames, contains('dir-entry-$i'));
    }
    client.close();
    await server.close();
  });

  // A READ whose requested length is a whole uint32 must be clamped to what
  // one outgoing packet can carry before the filesystem is asked for
  // anything: without the clamp the filesystem would materialize up to 4 GiB
  // of data that the outgoing-packet guard would then discard along with the
  // channel. The reply is a clamped DATA packet — not an error status — and
  // the channel stays alive for further requests.
  test('a READ asking for more than one packet is clamped, not an error',
      () async {
    fs.createFile('/big.bin', bytes: Uint8List(512 * 1024));
    final (client, server) = await connect();
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendSubsystem('sftp'), isTrue);
    final wire = _RawSftpWire(controller.channel);

    wire.send(SftpInitPacket(3));
    expect((await wire.receive())[0], SftpVersionPacket.packetType);

    wire.send(SftpOpenPacket(
      1,
      '/big.bin',
      SftpFileOpenMode.read.flag,
      SftpFileAttrs(),
    ));
    final openReply = await wire.receive();
    expect(openReply[0], SftpHandlePacket.packetType);
    final handle = SftpHandlePacket.decode(openReply).handle;

    wire.send(SftpReadPacket(
      requestId: 2,
      handle: handle,
      offset: 0,
      length: 0xffffffff,
    ));
    final readReply = await wire.receive();
    expect(readReply[0], SftpDataPacket.packetType);
    // The 256 KiB SFTP packet limit minus the DATA header (type byte,
    // request id, and the data's 4-byte length prefix).
    const clampedLength = 256 * 1024 - 9;
    expect(SftpDataPacket.decode(readReply).data.length, clampedLength);
    // The clamp happened before the filesystem: the server asked it for the
    // clamped length, not the 4 GiB the wire requested.
    expect(fs.fileReadLengths, [clampedLength]);

    // The channel survived — a further read at the clamp boundary is served.
    wire.send(SftpReadPacket(
      requestId: 3,
      handle: handle,
      offset: clampedLength,
      length: 16,
    ));
    final nextReply = await wire.receive();
    expect(nextReply[0], SftpDataPacket.packetType);
    expect(SftpDataPacket.decode(nextReply).data.length, 16);

    client.close();
    await server.close();
  });
}
