@Tags(['integration', 'performance'])
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/worker/ssh_profile_worker_manager.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_entry.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_metrics.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

void main() {
  test('captures aggregate worker traffic without an SSH host', () async {
    final launcher = _PerformanceWorkerLauncher();
    final metrics = SshWorkerMetrics(enabled: true, logDiagnostic: (_) {});
    final manager = SshProfileWorkerManager(
      launcher: launcher,
      metrics: metrics,
    );
    const profile = SshProfile(
      id: 'performance-profile',
      name: 'Performance profile',
      host: 'example.test',
      username: 'tester',
    );

    final lease = await manager.acquire(profile);
    await lease.send(
      const SshWorkerRequest(
        requestId: 'connect',
        operation: SshWorkerOperation.connectStorage,
      ),
    );
    await lease.send(
      SshWorkerRequest(
        requestId: 'write',
        operation: SshWorkerOperation.writeSftpChunk,
        payload: Uint8List(4096),
      ),
    );
    launcher.events.add(
      SshWorkerEvent.execOutput(
        streamId: 'exec-1',
        sequence: 0,
        stream: SshWorkerExecStream.stdout,
        bytes: Uint8List(8192),
      ).toWire(),
    );
    await Future<void>.delayed(Duration.zero);

    await lease.release();
    await manager.flushIdleShutdowns();

    final snapshot = metrics.snapshot;
    expect(snapshot.activeWorkers, 0);
    expect(snapshot.connectLatencies, hasLength(1));
    expect(snapshot.sftpBytesTotal, 4096);
    expect(snapshot.terminalBytesTotal, 8192);
    expect(snapshot.workerShutdownDurations, hasLength(1));
    await manager.close();
  });
}

final class _PerformanceWorkerLauncher implements SshWorkerLauncher {
  final events = StreamController<Object?>.broadcast();

  @override
  Future<SshWorkerLaunch> spawn({
    required SshProfile profile,
    required int generation,
    required String debugName,
  }) async {
    final commands = ReceivePort();
    commands.listen((wire) {
      final request = SshWorkerRequest.fromWire(wire);
      events.add(SshWorkerReply.success(request.requestId).toWire());
    });
    return SshWorkerLaunch(
      workerIdentity: Object(),
      commands: commands.sendPort,
      messages: events.stream,
      close: () async => commands.close(),
    );
  }
}
