import 'dart:async';
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history_parse_worker.dart';

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
