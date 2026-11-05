import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/event_transport_ssh_channel.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_forward_core.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_forward_proxy.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_forward_pump.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/chat/team_bus/remote/reverse_tunnel.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'worker reverse tunnel delivers remote channels and cleans up once',
    () async {
      final launcher = _ForwardWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final factory = _factory(manager);
      final tunnel = factory.newMemberReverseTunnel(_profile);

      expect(await tunnel.open(), 51001);
      final inbound = tunnel.channels.first;
      launcher.emitRemoteChannel();
      final channel = await inbound;
      final input = channel.input.toList();
      channel.add([3]);
      launcher.emitChannelBytes([1, 2]);
      launcher.finishChannel();

      expect(await input, [
        [1, 2],
      ]);
      await Future<void>.delayed(Duration.zero);
      await channel.close();
      await channel.close();
      await tunnel.close();
      await tunnel.close();

      expect(launcher.writes, [
        [3],
      ]);
      expect(
        launcher.operations,
        containsAll([
          SshWorkerOperation.openForwardRemote,
          SshWorkerOperation.writeForwardChannel,
          SshWorkerOperation.closeForwardChannel,
          SshWorkerOperation.closeForward,
        ]),
      );
      expect(
        launcher.operations,
        isNot(contains(SshWorkerOperation.openMember)),
      );
      await manager.flushIdleShutdowns();
    },
  );

  test('production worker dispatch closes a late remote forward', () async {
    final gate = Completer<void>();
    final remote = _TestRemoteForward(port: 51001);
    final launcher = _ProductionForwardWorkerLauncher(
      client: _TestForwardClient(remote: remote, remoteGate: gate),
    );
    final launch = await launcher.spawn(
      profile: _profile,
      generation: 1,
      debugName: 'test-worker',
    );
    final worker = SshProfileWorkerClient(
      profileId: _profile.id,
      generation: 1,
      launch: launch,
    );
    final args = {
      'forwardId': 'forward-production-race',
      'profile': _profile.toJson(),
      'target': const SshWorkerDialTarget(host: '127.0.0.1', port: 22).toWire(),
      'timeoutMs': 1000,
      'bindHost': '127.0.0.1',
    };
    final opening = worker.send(
      SshWorkerRequest(
        requestId: 'open-production-race',
        operation: SshWorkerOperation.openForwardRemote,
        args: args,
      ),
    );
    await launcher.openRequested.future.timeout(const Duration(seconds: 2));
    var closeDone = false;
    final closing = worker
        .send(
          const SshWorkerRequest(
            requestId: 'close-production-race',
            operation: SshWorkerOperation.closeForward,
            args: {'forwardId': 'forward-production-race'},
          ),
        )
        .then((_) => closeDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeDone, isFalse);

    gate.complete();
    final openReply = await opening.timeout(const Duration(seconds: 2));
    expect(openReply.error?.code, 'forward_closed');
    await closing.timeout(const Duration(seconds: 2));
    expect(remote.closeCount, 1);
    expect(launcher.client.disconnectCount, 1);
    await worker.close().timeout(const Duration(seconds: 2));
  });

  test('production worker shutdown closes a late remote forward', () async {
    final gate = Completer<void>();
    final remote = _TestRemoteForward(port: 51001);
    final launcher = _ProductionForwardWorkerLauncher(
      client: _TestForwardClient(remote: remote, remoteGate: gate),
    );
    final launch = await launcher.spawn(
      profile: _profile,
      generation: 1,
      debugName: 'test-worker',
    );
    final worker = SshProfileWorkerClient(
      profileId: _profile.id,
      generation: 1,
      launch: launch,
    );
    final opening = worker.send(
      SshWorkerRequest(
        requestId: 'open-production-shutdown-race',
        operation: SshWorkerOperation.openForwardRemote,
        args: {
          'forwardId': 'forward-production-shutdown-race',
          'profile': _profile.toJson(),
          'target': const SshWorkerDialTarget(
            host: '127.0.0.1',
            port: 22,
          ).toWire(),
          'timeoutMs': 1000,
          'bindHost': '127.0.0.1',
        },
      ),
    );
    await launcher.openRequested.future.timeout(const Duration(seconds: 2));

    final shutdown = worker.close();
    await Future<void>.delayed(Duration.zero);
    expect(remote.closeCount, 0);

    gate.complete();
    final openReply = await opening.timeout(const Duration(seconds: 2));
    expect(openReply.error?.code, 'worker_shutting_down');
    await shutdown.timeout(const Duration(seconds: 2));
    expect(remote.closeCount, 1);
    expect(launcher.client.disconnectCount, 1);
  });

  test('production worker pump error reaches the UI proxy stream', () async {
    final channel = _TestForwardChannel();
    final launcher = _ProductionForwardWorkerLauncher(
      client: _TestForwardClient(local: channel),
    );
    final manager = SshProfileWorkerManager(launcher: launcher);
    final forward = await _factory(
      manager,
    ).openForwardChannel(_profile, '127.0.0.1', 62000);
    final incoming = forward.incoming.toList();

    channel.fail(StateError('worker input failed'));

    await expectLater(
      incoming,
      throwsA(
        isA<SshWorkerForwardException>().having(
          (error) => error.code,
          'code',
          'transport_error',
        ),
      ),
    );
    await manager.flushIdleShutdowns();
  });

  test('forward close follows child final output events', () async {
    final channel = _TestForwardChannel();
    final events = <SshWorkerEvent>[];
    final core = SshWorkerForwardCore(
      profileId: _profile.id,
      openClient:
          ({required profile, required target, required timeout}) async =>
              _TestForwardClient(local: channel),
      sendEvent: events.add,
    );
    final open = await core.handle(
      SshWorkerRequest(
        requestId: 'open-ordering',
        operation: SshWorkerOperation.openForwardLocal,
        args: {
          'forwardId': 'forward-ordering',
          'profile': _profile.toJson(),
          'target': const SshWorkerDialTarget(
            host: '127.0.0.1',
            port: 22,
          ).toWire(),
          'timeoutMs': 1000,
          'host': '127.0.0.1',
          'port': 62000,
        },
      ),
    );
    expect(open.kind, SshWorkerReplyKind.success);
    channel.emit([1, 2, 3]);
    await Future<void>.delayed(Duration.zero);

    final close = await core.handle(
      const SshWorkerRequest(
        requestId: 'close-ordering',
        operation: SshWorkerOperation.closeForward,
        args: {'forwardId': 'forward-ordering'},
      ),
    );

    expect(close.kind, SshWorkerReplyKind.success);
    expect(events.last.kind, SshWorkerEventKind.forwardClosed);
    expect(
      events
          .where((event) => event.kind == SshWorkerEventKind.outputChunk)
          .last
          .isFinal,
      isTrue,
    );
  });

  test(
    'worker local forward carries bytes, writes, close, and failures',
    () async {
      final launcher = _ForwardWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final factory = _factory(manager);
      final channel = await factory.openForwardChannel(
        _profile,
        '127.0.0.1',
        62000,
        timeout: const Duration(milliseconds: 73),
      );
      final incoming = channel.incoming.toList();
      channel.add([6]);
      launcher.emitChannelBytes([4, 5]);
      launcher.finishLocalForward();

      expect(await incoming, [
        [4, 5],
      ]);
      await Future<void>.delayed(Duration.zero);
      await channel.close();
      await channel.close();
      expect(launcher.writes, [
        [6],
      ]);
      expect(launcher.forwardTimeouts, [73]);
      expect(
        launcher.operations,
        contains(SshWorkerOperation.openForwardLocal),
      );
      expect(
        launcher.operations,
        isNot(contains(SshWorkerOperation.openMember)),
      );
      await manager.flushIdleShutdowns();

      final failingFactory = _factory(
        SshProfileWorkerManager(
          launcher: _ForwardWorkerLauncher(failOpen: true),
        ),
      );
      await expectLater(
        failingFactory.openForwardChannel(_profile, '127.0.0.1', 62000),
        throwsA(isA<SshWorkerForwardException>()),
      );
    },
  );

  test(
    'event transport opens through the factory worker forward path',
    () async {
      final launcher = _ForwardWorkerLauncher();
      final manager = SshProfileWorkerManager(launcher: launcher);
      final factory = _factory(manager);
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      await fs.writeString(storage.paths.eventTransportJson, '{"port":62001}');

      final channel = await openSshEventTransportChannel(
        homeStorage: storage,
        sshClientFactory: factory,
        homeProfile: () => _profile,
      );
      final incoming = channel.incoming.toList();
      launcher.emitChannelBytes([7]);
      launcher.finishLocalForward();

      expect(await incoming, [
        [7],
      ]);
      expect(
        launcher.operations,
        contains(SshWorkerOperation.openForwardLocal),
      );
      expect(
        launcher.operations,
        isNot(contains(SshWorkerOperation.openMember)),
      );
      await channel.close();
      await manager.flushIdleShutdowns();
    },
  );

  test('simultaneous reverse tunnels use unique forward ids', () async {
    final launcher = _ForwardWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final factory = _factory(manager);
    final first = factory.newMemberReverseTunnel(_profile);
    final second = factory.newMemberReverseTunnel(_profile);

    await Future.wait([first.open(), second.open()]);

    expect(launcher.forwardIds.toSet(), hasLength(2));
    await Future.wait([first.close(), second.close()]);
    await manager.flushIdleShutdowns();
  });

  test('close during open rejects and releases the worker session', () async {
    final gate = Completer<void>();
    final launcher = _ForwardWorkerLauncher(openGate: gate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final tunnel = _factory(manager).newMemberReverseTunnel(_profile);
    final opening = tunnel.open();
    await launcher.openRequested.future;

    final closing = tunnel.close();
    gate.complete();
    await closing;
    await expectLater(opening, throwsStateError);
    await manager.flushIdleShutdowns();
  });

  test('worker shutdown during open rejects the pending forward', () async {
    final gate = Completer<void>();
    final launcher = _ForwardWorkerLauncher(openGate: gate);
    final manager = SshProfileWorkerManager(launcher: launcher);
    final tunnel = _factory(manager).newMemberReverseTunnel(_profile);
    final opening = tunnel.open();
    await launcher.openRequested.future;

    final disconnecting = manager.disconnectProfile(_profile.id);
    await launcher.shutdownRequested.future;
    expect(launcher.shutdownAcknowledged, isFalse);
    gate.complete();
    await expectLater(
      opening,
      throwsA(
        isA<SshWorkerForwardException>().having(
          (error) => error.code,
          'code',
          'worker_shutting_down',
        ),
      ),
    );
    await disconnecting;
    expect(launcher.activeForwardIds, isEmpty);
    expect(launcher.shutdownAcknowledged, isTrue);
  });

  test('channel error reaches the UI stream as an error', () async {
    final launcher = _ForwardWorkerLauncher();
    final manager = SshProfileWorkerManager(launcher: launcher);
    final channel = await _factory(
      manager,
    ).openForwardChannel(_profile, '127.0.0.1', 62000);
    final incoming = channel.incoming.toList();
    launcher.emitChannelError();

    await expectLater(incoming, throwsA(isA<SshWorkerForwardException>()));
    await manager.flushIdleShutdowns();
  });

  test('injected reverse tunnel factory remains selected', () async {
    final injected = _InjectedReverseTunnel();
    final manager = SshProfileWorkerManager(launcher: _ForwardWorkerLauncher());
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      workerManager: manager,
      memberReverseTunnelFactory: (_, {required bindHost}) => injected,
    );

    expect(factory.newMemberReverseTunnel(_profile), same(injected));
    await manager.close();
  });
}

SshClientFactory _factory(SshProfileWorkerManager manager) => SshClientFactory(
  credentialStore: InMemorySshCredentialStore(),
  knownHostRepository: InMemorySshKnownHostRepository(),
  workerManager: manager,
);

const _profile = SshProfile(
  id: 'p1',
  name: 'Forward test',
  host: 'example.test',
  username: 'tester',
);

final class _ForwardWorkerLauncher implements SshWorkerLauncher {
  _ForwardWorkerLauncher({this.failOpen = false, this.openGate});

  final bool failOpen;
  final Completer<void>? openGate;
  final operations = <SshWorkerOperation>[];
  final writes = <List<int>>[];
  final forwardTimeouts = <int>[];
  final forwardIds = <String>[];
  final activeForwardIds = <String>{};
  final openRequested = Completer<void>();
  final shutdownRequested = Completer<void>();
  final _messages = StreamController<Object?>.broadcast();
  final _inFlightOpens = <Completer<void>>[];
  String? _forwardId;
  String? _channelId;
  var _sequence = 0;
  var _stopping = false;
  var shutdownAcknowledged = false;

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final commands = ReceivePort();
    commands.listen((wire) async {
      final request = SshWorkerRequest.fromWire(wire);
      if (request.operation == SshWorkerOperation.shutdown) {
        _stopping = true;
        if (!shutdownRequested.isCompleted) shutdownRequested.complete();
        await Future.wait(_inFlightOpens.map((open) => open.future));
        activeForwardIds.clear();
        shutdownAcknowledged = true;
        _success(request);
        return;
      }
      operations.add(request.operation);
      switch (request.operation) {
        case SshWorkerOperation.openForwardLocal:
        case SshWorkerOperation.openForwardRemote:
          final forwardId = request.args['forwardId']! as String;
          _forwardId = forwardId;
          forwardIds.add(forwardId);
          if (!openRequested.isCompleted) openRequested.complete();
          _channelId = request.operation == SshWorkerOperation.openForwardLocal
              ? forwardId
              : null;
          forwardTimeouts.add(request.args['timeoutMs']! as int);
          final open = Completer<void>();
          _inFlightOpens.add(open);
          try {
            if (failOpen) {
              _messages.add(
                SshWorkerReply.failure(
                  request.requestId,
                  const SshWorkerErrorRecord(
                    code: 'transport_error',
                    message: 'forward failed',
                  ),
                ).toWire(),
              );
            } else {
              if (openGate != null) await openGate!.future;
              if (_messages.isClosed) return;
              if (_stopping) {
                _messages.add(
                  SshWorkerReply.failure(
                    request.requestId,
                    const SshWorkerErrorRecord(
                      code: 'worker_shutting_down',
                      message: 'Worker is shutting down',
                    ),
                  ).toWire(),
                );
              } else {
                activeForwardIds.add(forwardId);
                _messages.add(
                  SshWorkerReply.success(
                    request.requestId,
                    result:
                        request.operation ==
                            SshWorkerOperation.openForwardRemote
                        ? {'port': 51001}
                        : {'channelId': forwardId},
                  ).toWire(),
                );
              }
            }
          } finally {
            _inFlightOpens.remove(open);
            if (!open.isCompleted) open.complete();
          }
        case SshWorkerOperation.writeForwardChannel:
          writes.add(List<int>.from(request.payload!));
          _success(request);
        case SshWorkerOperation.closeForward:
          activeForwardIds.remove(request.args['forwardId']);
          _success(request);
        default:
          _success(request);
      }
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: _messages.stream,
      close: () async {
        commands.close();
        await _messages.close();
      },
    );
  }

  void emitRemoteChannel() {
    final forwardId = _forwardId!;
    final channelId = '$forwardId/channel-0';
    _channelId = channelId;
    _messages.add(
      SshWorkerEvent.forwardChannelOpened(
        forwardId: forwardId,
        channelId: channelId,
      ).toWire(),
    );
  }

  void emitChannelBytes(List<int> bytes) {
    _messages.add(
      SshWorkerEvent.outputChunk(
        streamId: _channelId!,
        sequence: _sequence++,
        bytes: Uint8List.fromList(bytes),
        isFinal: false,
      ).toWire(),
    );
  }

  void finishChannel() {
    _messages.add(
      SshWorkerEvent.outputChunk(
        streamId: _channelId!,
        sequence: _sequence++,
        bytes: Uint8List(0),
        isFinal: true,
      ).toWire(),
    );
  }

  void finishLocalForward() {
    finishChannel();
    _messages.add(
      SshWorkerEvent.forwardClosed(forwardId: _forwardId!).toWire(),
    );
  }

  void emitChannelError() {
    _messages.add(
      SshWorkerEvent.outputChunk(
        streamId: _channelId!,
        sequence: _sequence++,
        bytes: Uint8List(0),
        isFinal: true,
        errorCode: 'transport_error',
      ).toWire(),
    );
  }

  void _success(SshWorkerRequest request) {
    _messages.add(SshWorkerReply.success(request.requestId).toWire());
  }
}

final class _ProductionForwardWorkerLauncher implements SshWorkerLauncher {
  _ProductionForwardWorkerLauncher({required this.client});

  final _TestForwardClient client;
  final openRequested = Completer<void>();

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final messages = StreamController<Object?>.broadcast();
    final commandPort = Completer<SendPort>();
    final unusedUiPort = ReceivePort();
    final worker = SshProfileWorker(
      bootstrap: SshWorkerBootstrap(
        profileId: profile.id,
        uiPort: unusedUiPort.sendPort,
      ),
      send: (message) {
        if (message is Map && message['type'] == 'ready') {
          if (!commandPort.isCompleted) {
            commandPort.complete(message['commandPort'] as SendPort);
          }
          return;
        }
        messages.add(message);
      },
      forwardClientOpener:
          ({required profile, required target, required timeout}) async {
            if (!openRequested.isCompleted) openRequested.complete();
            return client;
          },
    )..start();
    final commands = await commandPort.future;
    return SshWorkerLaunch(
      workerIdentity: worker,
      commands: commands,
      messages: messages.stream,
      close: () async {
        unusedUiPort.close();
        await messages.close();
      },
    );
  }
}

final class _TestForwardClient implements SshWorkerForwardClient {
  _TestForwardClient({this.local, this.remote, this.remoteGate});

  final _TestForwardChannel? local;
  final _TestRemoteForward? remote;
  final Completer<void>? remoteGate;
  var disconnectCount = 0;
  var _closed = false;
  final _done = Completer<void>();

  @override
  Future<void> get authenticated async {}

  @override
  Future<void> get done => _done.future;

  @override
  Future<SshWorkerForwardChannel> forwardLocal(String host, int port) async =>
      local!;

  @override
  Future<SshWorkerRemoteForward?> forwardRemote({
    required String host,
    required int port,
  }) async {
    if (remoteGate != null) await remoteGate!.future;
    return remote;
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _closed = true;
    if (!_done.isCompleted) _done.complete();
  }
}

final class _TestForwardChannel implements SshWorkerForwardChannel {
  final _stream = StreamController<Uint8List>();
  var closeCount = 0;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  void add(Uint8List data) {}

  @override
  Future<void> close() async {
    closeCount++;
    await _stream.close();
  }

  void fail(Object error) => _stream.addError(error);

  void emit(List<int> bytes) => _stream.add(Uint8List.fromList(bytes));
}

final class _TestRemoteForward implements SshWorkerRemoteForward {
  _TestRemoteForward({required this.port});

  @override
  final int port;
  final _connections = StreamController<SshWorkerForwardChannel>.broadcast();
  var closeCount = 0;

  @override
  Stream<SshWorkerForwardChannel> get connections => _connections.stream;

  @override
  Future<void> close() async {
    closeCount++;
    await _connections.close();
  }
}

final class _InjectedReverseTunnel implements ReverseTunnel {
  @override
  Stream<TunnelChannel> get channels => const Stream.empty();

  @override
  Future<int> open() async => 1;

  @override
  Future<void> close() async {}
}
