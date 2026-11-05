import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_metrics.dart';

void main() {
  test('metrics records request latency and queue high-water mark', () {
    final metrics = SshWorkerMetrics(enabled: true);

    metrics.requestStarted('r1', DateTime.utc(2026, 1, 1));
    metrics.pendingMessagesChanged(4);
    metrics.requestCompleted('r1', DateTime.utc(2026, 1, 1, 0, 0, 0, 12));

    expect(metrics.snapshot.pendingMessageHighWaterMark, 4);
    expect(metrics.snapshot.completedRequestLatencies, [
      const Duration(milliseconds: 12),
    ]);
  });

  test('disabled metrics retain no measurements', () {
    final metrics = SshWorkerMetrics(enabled: false);

    metrics.workerStarted(
      const SshWorkerMetricContext(profileId: 'profile-1', generation: 1),
    );
    metrics.pendingMessagesChanged(3);
    metrics.terminalFrame(
      const SshWorkerMetricContext(
        profileId: 'profile-1',
        generation: 1,
        streamId: 'pty-1',
      ),
      1024,
    );

    expect(metrics.snapshot.activeWorkers, 0);
    expect(metrics.snapshot.pendingMessageHighWaterMark, 0);
    expect(metrics.snapshot.terminalBytesPerFrame, isEmpty);
  });

  test('metrics keep same request ids from different workers separate', () {
    final metrics = SshWorkerMetrics(enabled: true);
    const first = SshWorkerMetricContext(profileId: 'profile-1', generation: 1);
    const second = SshWorkerMetricContext(
      profileId: 'profile-2',
      generation: 1,
    );
    final started = DateTime.utc(2026, 1, 1);

    metrics.requestStarted('storage-0', started, context: first);
    metrics.requestStarted(
      'storage-0',
      started.add(const Duration(milliseconds: 1)),
      context: second,
    );
    metrics.requestCompleted(
      'storage-0',
      started.add(const Duration(milliseconds: 3)),
      context: first,
    );
    metrics.requestCompleted(
      'storage-0',
      started.add(const Duration(milliseconds: 5)),
      context: second,
    );

    expect(metrics.snapshot.completedRequestLatencies, [
      const Duration(milliseconds: 3),
      const Duration(milliseconds: 4),
    ]);
  });

  test(
    'metrics separates connect, reconnect, terminal, SFTP, and shutdown',
    () {
      final metrics = SshWorkerMetrics(enabled: true);
      const storage = SshWorkerMetricContext(
        profileId: 'profile-1',
        generation: 1,
        plane: SshWorkerMetricPlane.storage,
        requestId: 'connect-1',
      );
      const terminal = SshWorkerMetricContext(
        profileId: 'profile-1',
        generation: 1,
        plane: SshWorkerMetricPlane.member,
        streamId: 'pty-1',
      );
      final started = DateTime.utc(2026, 1, 1);

      metrics.connectStarted(storage, started);
      metrics.connectCompleted(
        storage,
        started.add(const Duration(milliseconds: 4)),
        connectionId: 'storage-1',
      );
      metrics.connectionClosed(storage, connectionId: 'storage-1');
      metrics.connectStarted(
        storage.withRequestId('connect-2'),
        started.add(const Duration(milliseconds: 10)),
      );
      metrics.connectCompleted(
        storage.withRequestId('connect-2'),
        started.add(const Duration(milliseconds: 16)),
        connectionId: 'storage-1',
      );
      metrics.terminalFrame(terminal, 128);
      metrics.sftpChunk(storage.withStreamId('read-1'), 512);
      metrics.workerShutdownStarted(storage, started);
      metrics.workerShutdownCompleted(
        storage,
        started.add(const Duration(milliseconds: 7)),
      );

      expect(metrics.snapshot.connectLatencies, [
        const Duration(milliseconds: 4),
      ]);
      expect(metrics.snapshot.reconnectLatencies, [
        const Duration(milliseconds: 6),
      ]);
      expect(metrics.snapshot.terminalBytesPerFrame, [128]);
      expect(metrics.snapshot.sftpBytesPerChunk, [512]);
      expect(metrics.snapshot.workerShutdownDurations, [
        const Duration(milliseconds: 7),
      ]);
      expect(metrics.snapshot.diagnosticContexts, isNotEmpty);
    },
  );

  test('independent sessions connect while a closed identity reconnects', () {
    final metrics = SshWorkerMetrics(enabled: true);
    const first = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 1,
      plane: SshWorkerMetricPlane.member,
      requestId: 'open-a',
    );
    final started = DateTime.utc(2026, 1, 1);

    metrics.connectStarted(first, started);
    metrics.connectCompleted(
      first,
      started.add(const Duration(milliseconds: 1)),
      connectionId: 'session-a',
    );
    metrics.connectStarted(
      first.withRequestId('open-b'),
      started.add(const Duration(milliseconds: 2)),
    );
    metrics.connectCompleted(
      first.withRequestId('open-b'),
      started.add(const Duration(milliseconds: 4)),
      connectionId: 'session-b',
    );
    metrics.connectionClosed(first, connectionId: 'session-a');
    metrics.connectStarted(
      first.withRequestId('open-a-replacement'),
      started.add(const Duration(milliseconds: 5)),
    );
    metrics.connectCompleted(
      first.withRequestId('open-a-replacement'),
      started.add(const Duration(milliseconds: 8)),
      connectionId: 'session-a',
    );

    expect(metrics.snapshot.connectLatencies, [
      const Duration(milliseconds: 1),
      const Duration(milliseconds: 2),
    ]);
    expect(metrics.snapshot.reconnectLatencies, [
      const Duration(milliseconds: 3),
    ]);
  });

  test('a new session is a reconnect only after another session closes', () {
    final metrics = SshWorkerMetrics(enabled: true);
    const first = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 1,
      plane: SshWorkerMetricPlane.member,
      requestId: 'open-a',
    );
    final started = DateTime.utc(2026, 1, 1);

    metrics.connectStarted(first, started);
    metrics.connectCompleted(
      first,
      started.add(const Duration(milliseconds: 1)),
      connectionId: 'session-a',
    );
    metrics.connectStarted(
      first.withRequestId('open-b'),
      started.add(const Duration(milliseconds: 2)),
    );
    metrics.connectCompleted(
      first.withRequestId('open-b'),
      started.add(const Duration(milliseconds: 4)),
      connectionId: 'session-b',
    );
    metrics.connectionClosed(first, connectionId: 'session-a');
    metrics.connectStarted(
      first.withRequestId('open-c'),
      started.add(const Duration(milliseconds: 5)),
    );
    metrics.connectCompleted(
      first.withRequestId('open-c'),
      started.add(const Duration(milliseconds: 8)),
      connectionId: 'session-c',
    );

    expect(metrics.snapshot.connectLatencies, [
      const Duration(milliseconds: 1),
      const Duration(milliseconds: 2),
    ]);
    expect(metrics.snapshot.reconnectLatencies, [
      const Duration(milliseconds: 3),
    ]);
  });

  test('a replacement generation reconnects after its predecessor closes', () {
    final metrics = SshWorkerMetrics(enabled: true);
    const first = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 1,
      plane: SshWorkerMetricPlane.member,
      requestId: 'open-1',
    );
    const second = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 2,
      plane: SshWorkerMetricPlane.member,
      requestId: 'open-2',
    );
    final started = DateTime.utc(2026, 1, 1);

    metrics.connectStarted(first, started);
    metrics.connectCompleted(
      first,
      started.add(const Duration(milliseconds: 1)),
      connectionId: 'member-1-0',
    );
    metrics.workerGenerationClosed(first);
    metrics.connectStarted(
      second,
      started.add(const Duration(milliseconds: 2)),
    );
    metrics.connectCompleted(
      second,
      started.add(const Duration(milliseconds: 5)),
      connectionId: 'member-2-0',
    );

    expect(metrics.snapshot.connectLatencies, [
      const Duration(milliseconds: 1),
    ]);
    expect(metrics.snapshot.reconnectLatencies, [
      const Duration(milliseconds: 3),
    ]);
  });

  test('diagnostic contexts are sanitized, observable, and bounded', () {
    final metrics = SshWorkerMetrics(enabled: true, sampleCapacity: 2);
    const first = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 3,
      plane: SshWorkerMetricPlane.storage,
      requestId: 'request-1',
      streamId: 'stream-1',
    );

    metrics.requestStarted(
      'request-1',
      DateTime.utc(2026, 1, 1),
      context: first,
    );
    metrics.terminalFrame(
      const SshWorkerMetricContext(
        profileId: 'profile-1',
        generation: 3,
        plane: SshWorkerMetricPlane.member,
        streamId: 'stream-2',
      ),
      4,
    );
    metrics.sftpChunk(
      const SshWorkerMetricContext(
        profileId: 'profile-1',
        generation: 3,
        plane: SshWorkerMetricPlane.storage,
        streamId: 'stream-3',
      ),
      8,
    );

    final contexts = metrics.snapshot.diagnosticContexts;
    expect(contexts, hasLength(2));
    expect(contexts.first.streamId, 'stream-2');
    expect(contexts.last.profileId, 'profile-1');
    expect(contexts.last.generation, 3);
    expect(contexts.last.plane, SshWorkerMetricPlane.storage);
    expect(contexts.last.requestId, isNull);
    expect(contexts.last.streamId, 'stream-3');
  });

  test('aggregate log exposes bounded latency samples for live capture', () {
    final messages = <String>[];
    final metrics = SshWorkerMetrics(
      enabled: true,
      logDiagnostic: messages.add,
    );
    const context = SshWorkerMetricContext(
      profileId: 'profile-1',
      generation: 1,
      plane: SshWorkerMetricPlane.storage,
      requestId: 'connect-1',
    );
    final started = DateTime.utc(2026, 1, 1);

    metrics.requestStarted('connect-1', started, context: context);
    metrics.requestCompleted(
      'connect-1',
      started.add(const Duration(milliseconds: 2)),
      context: context,
    );
    metrics.connectStarted(context, started);
    metrics.connectCompleted(
      context,
      started.add(const Duration(milliseconds: 3)),
      connectionId: 'storage',
    );
    metrics.emitSnapshot(context);

    expect(messages, hasLength(1));
    expect(messages.single, contains('requestLatencyUs=2000'));
    expect(messages.single, contains('connectLatencyUs=3000'));
    expect(messages.single, contains('reconnectLatencyUs=none'));
  });
}
