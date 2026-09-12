@Tags(['integration', 'cross-platform'])
@Timeout(Duration(minutes: 5))
library;

/// The phone→desktop event push, end to end over real direct-tcpip channels
/// through the embedded SSH server:
///
///   phone (dartssh2 SSHClient, registered device key)
///     → ssh.forwardLocal('127.0.0.1', `<EventTransportServer port>`)
///       (a `direct-tcpip` channel request to the embedded sshd)
///     → EmbeddedSshServer (loopback, ephemeral port, forwarding injected)
///     → EventTransportServer socket → AsyncDispatcher + AgentPresenceProjection
///     → subscribe handshake / snapshot wire reply back through the channel
///
/// The presence entry is pre-seeded on the desktop and the test asserts the
/// subscribed/snapshot JSON that lands on the phone carries `op:set`,
/// `kind:working` and `sessionId:s1` — the exact wire the phone's
/// openSshEventTransportChannel consumes. No fakes past the loopback socket:
/// both servers bind real dart:io listeners under temp roots.
///
/// Run:
///   dart run tool/run_tests.dart --tags integration \
///     test/integration/embedded_event_transport_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart'
    show SSHClient, SSHKeyPair, SSHSocket;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_process_factories.dart';
import 'package:teampilot/services/connect/embedded_ssh_server.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_device_key.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';
import 'package:teampilot/services/event/agent_presence_transport_codec.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/event_transport_codec.dart';
import 'package:teampilot/services/event/event_transport_server.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('phone forwardLocal receives the presence push from EventTransportServer',
      () async {
    // 1) Embedded sshd (real loopback + registered device key).
    final deviceKey = SshDeviceKey.generate();
    final appDataRoot = await Directory.systemTemp.createTemp(
      'teampilot-event-appdata-',
    );
    final homeDir = await Directory.systemTemp.createTemp('teampilot-event-home-');
    addTearDown(
      () async {
        try {
          await appDataRoot.delete(recursive: true);
          await homeDir.delete(recursive: true);
        } on Object {
          // Best-effort cleanup of the temp roots.
        }
      },
    );

    final fs = LocalFilesystem();
    final deviceStore = PairedDeviceStore(fs: fs, appDataRoot: appDataRoot.path);
    await deviceStore.issueDevice(
      deviceId: SshDeviceKey.deviceIdFor(deviceKey.openSshPublic),
      publicKey: deviceKey.openSshPublic,
      deviceName: 'integration-phone',
    );
    final server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: appDataRoot.path,
      deviceStore: deviceStore,
      username: 'dev-user',
      homePath: homeDir.path,
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: 0,
      ptySpawner: _pipePtySpawner,
    );
    await server.start();
    addTearDown(server.stop);

    // 2) Desktop event server: AsyncDispatcher + AgentPresenceProjection,
    //    real loopback bind + advertisement file.
    final dispatcher = AsyncDispatcher()..start();
    addTearDown(dispatcher.stop);
    final presence = AgentPresenceProjection();
    dispatcher.registerFamily<AgentPresenceKind>(
      AgentPresenceKind.working.runtimeType,
      presence,
    );
    final eventServerRoot = Directory.systemTemp.createTempSync('tp-event-home-');
    addTearDown(
      () => eventServerRoot
          .delete(recursive: true)
          .catchError((_) => eventServerRoot),
    );
    final transportServer = EventTransportServer(
      dispatcher: dispatcher,
      presence: presence,
      fs: fs,
      advertisementPath: '${eventServerRoot.path}/event-transport.json',
      codecs: [AgentPresenceTransportCodec()],
    );
    await transportServer.start();
    addTearDown(transportServer.stop);

    // 3) Pre-seed one presence entry; the snapshot on subscribe carries it.
    presence.handle(
      AgentPresenceEvent(
        seat: const PresenceSeatKey(sessionId: 's1', memberId: 'm1'),
        eventKind: AgentPresenceKind.working,
        timestamp: _epoch,
      ),
    );

    // 4) Phone side: dartssh2 through the embedded sshd forwardLocal, then the
    //    subscribe handshake. The line must carry the `v` envelope the real
    //    EventTransportClient sends — the server rejects subscribe lines
    //    without `v:1` (tryDecodeTransportLine).
    final ssh = SSHClient(
      await SSHSocket.connect('127.0.0.1', server.port),
      username: 'dev-user',
      identities: [SSHKeyPair.fromPem(deviceKey.pem).single],
      onVerifyHostKey: (_, __) => true,
    );
    // close(), the pairing test's teardown — not disconnect(): sending a
    // protocol-level disconnect surfaces an uncaught SSHDisconnectError on the
    // server side (embedded_ssh_server's unawaited connection.done listener).
    addTearDown(ssh.close);
    await ssh.authenticated;

    final advertisement =
        jsonDecode(
              await File('${eventServerRoot.path}/event-transport.json')
                  .readAsString(),
            )
            as Map<String, Object?>;
    final port = (advertisement['port'] as num).toInt();
    final forward = await ssh.forwardLocal('127.0.0.1', port);
    addTearDown(() => forward.close().catchError((_) {}));
    // Attach the reader before sending: dartssh2's channel stream drops data
    // already received while nothing is subscribed, so a late join would miss
    // the whole snapshot. Line-split first — the four NDJSON lines arrive in
    // one channel chunk, and a bare decoder takeWhile would stop at the single
    // chunk containing snapshotEnd and join to nothing. Then send the v1
    // subscribe envelope the real EventTransportClient sends (the server
    // rejects a line without `v`).
    final pushed = utf8.decoder
        .bind(forward.stream)
        .transform(const LineSplitter())
        .takeWhile((line) => line.trim() != snapshotEndLine)
        .join()
        .timeout(const Duration(seconds: 20));
    forward.sink.add(
      utf8.encode(
        encodeTransportLine({
          'v': eventTransportProtocolVersion,
          'type': 'subscribe',
          'families': [eventTransportFamilyAgentPresence],
        }),
      ),
    );

    // 5) The snapshot push arrives over direct-tcpip (AgentPresenceTransportCodec
    //    wire: op:set, kind:working, seat.sessionId). Sum until snapshotEnd and
    //    bound the wait — never hang the suite.
    final lines = await pushed;
    expect(
      lines,
      contains('"op":"set"'),
      reason: 'no s1 presence entry in the pushed snapshot',
    );
    expect(
      lines,
      contains('"kind":"working"'),
      reason: 'snapshot must carry kind working, not availability',
    );
    expect(lines, contains('"sessionId":"s1"'));
  });
}

final _epoch = DateTime.utc(2026);

const snapshotEndLine = '{"v":1,"type":"snapshotEnd","family":"agentPresence"}';

/// A dart:io [Process] with pipes standing in for an OS pseudo-terminal —
/// identical to the pairing integration test's spawner, so no embedded-connect
/// test shell stage is ever the reason the Flutter engine is required.
Future<PtyLike> _pipePtySpawner({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required int columns,
  required int rows,
  String? workingDirectory,
}) async {
  return _PipePty(
    await Process.start(
      executable,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
    ),
  );
}

class _PipePty implements PtyLike {
  _PipePty(this._process);

  final Process _process;

  @override
  Stream<Uint8List> get output => _process.stdout.cast<Uint8List>();

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(Uint8List data) => _process.stdin.add(data);

  @override
  void resize(int columns, int rows) {
    // Pipes have no window to resize.
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}