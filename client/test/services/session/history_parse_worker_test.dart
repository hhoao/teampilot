import 'dart:async';
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/history/history_parse_worker.dart';

void main() {
  test('reuses one resident worker for sequential parses', () async {
    final worker = HistoryParseWorker(
      idleTimeout: const Duration(seconds: 1),
      readyTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(worker.dispose);

    final first = await worker.parse(
      adapterId: 'claude',
      bundle: claudeBundle('u1', 'a1'),
    );
    final second = await worker.parse(
      adapterId: 'claude',
      bundle: claudeBundle('u2', 'a2'),
    );

    expect(first.messages.last.id, 'a1');
    expect(second.messages.last.id, 'a2');
    expect(worker.debugSpawnCount, 1);
  });

  test('worker timeout fails without synchronous parsing', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 20),
    )..debugInstallZombieWorker();
    addTearDown(worker.dispose);

    await expectLater(
      worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('disposed worker can be created and used again', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
    );
    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
    await worker.dispose();

    await expectLater(
      worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2')),
      completion(isA<HistoryParseResult>()),
    );
    await worker.dispose();
  });

  test('request timeout discards a stalled resident worker', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 30),
      requestTimeout: const Duration(milliseconds: 30),
      debugBehavior: HistoryParseWorkerDebugBehavior.stallRequests,
    );
    addTearDown(worker.dispose);

    await expectLater(
      worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1')),
      throwsA(isA<TimeoutException>()),
    );

    expect(worker.debugHasResidentWorker, isFalse);
  });

  test(
    'idle expiry discards the worker before the next parse respawns it',
    () async {
      final worker = HistoryParseWorker(
        idleTimeout: const Duration(milliseconds: 20),
        readyTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(worker.dispose);

      await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
      await waitForWorkerDiscard(worker);

      expect(worker.debugHasResidentWorker, isFalse);
      final result = await worker.parse(
        adapterId: 'claude',
        bundle: claudeBundle('u2', 'a2'),
      );
      expect(result.messages.last.id, 'a2');
      expect(worker.debugSpawnCount, 2);
    },
  );

  test('matches concurrent responses by request ID', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
      debugBehavior: HistoryParseWorkerDebugBehavior.delayFirstResponse,
    );
    addTearDown(worker.dispose);

    final results = await Future.wait([
      worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1')),
      worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2')),
    ]);

    expect(results[0].messages.last.id, 'a1');
    expect(results[1].messages.last.id, 'a2');
  });

  test(
    'queued requests use a request timeout separate from readiness',
    () async {
      final worker = HistoryParseWorker(
        readyTimeout: const Duration(milliseconds: 20),
        requestTimeout: const Duration(milliseconds: 200),
        debugBehavior: HistoryParseWorkerDebugBehavior.delayFirstResponse,
      );
      addTearDown(worker.dispose);

      final results = await Future.wait([
        worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1')),
        worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2')),
      ]);

      expect(results[0].messages.last.id, 'a1');
      expect(results[1].messages.last.id, 'a2');
      expect(worker.debugSpawnCount, 1);
    },
  );

  test('disposal fails a pending request and releases the worker', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
      debugBehavior: HistoryParseWorkerDebugBehavior.stallRequests,
    );
    addTearDown(worker.dispose);

    final pending = worker.parse(
      adapterId: 'claude',
      bundle: claudeBundle('u1', 'a1'),
    );
    final pendingError = expectLater(pending, throwsA(isA<StateError>()));
    await worker.debugWaitForPendingRequest();
    await worker.dispose();

    await pendingError;
    expect(worker.debugHasResidentWorker, isFalse);
  });

  test('isolate error discards an idle worker before the next parse', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(worker.dispose);

    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
    await worker.debugTriggerIsolateError();
    await waitForWorkerDiscard(worker);

    expect(worker.debugHasResidentWorker, isFalse);
    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2'));
    expect(worker.debugSpawnCount, 2);
  });

  test('isolate exit discards an idle worker before the next parse', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(worker.dispose);

    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
    await worker.debugTriggerIsolateExit();
    await waitForWorkerDiscard(worker);

    expect(worker.debugHasResidentWorker, isFalse);
    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2'));
    expect(worker.debugSpawnCount, 2);
  });

  test('response port closure discards an idle worker', () async {
    final worker = HistoryParseWorker(
      readyTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(worker.dispose);

    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u1', 'a1'));
    worker.debugCloseResponsePort();
    await waitForWorkerDiscard(worker);

    expect(worker.debugHasResidentWorker, isFalse);
    await worker.parse(adapterId: 'claude', bundle: claudeBundle('u2', 'a2'));
    expect(worker.debugSpawnCount, 2);
  });
}

Future<void> waitForWorkerDiscard(HistoryParseWorker worker) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (!worker.debugHasResidentWorker) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('worker was not discarded');
}

AiTranscriptBundle claudeBundle(String userId, String assistantId) {
  return AiTranscriptBundle(
    adapterId: 'claude',
    fragments: [
      AiTranscriptFragment(
        name: 'transcript.jsonl',
        bytes: utf8.encode(
          '{"type":"user","message":{"role":"user","content":"hello"},'
          '"uuid":"$userId","timestamp":"2026-09-15T00:00:00.000Z"}\n'
          '{"type":"assistant","message":{"role":"assistant","content":['
          '{"type":"text","text":"hi"}]},"uuid":"$assistantId",'
          '"timestamp":"2026-09-15T00:00:01.000Z"}',
        ),
      ),
    ],
  );
}
