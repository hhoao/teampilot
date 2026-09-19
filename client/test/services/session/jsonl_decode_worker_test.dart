import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/history/jsonl_decode_worker.dart';
import 'package:teampilot/services/chat/session/history/jsonl_page_worker.dart';
import 'package:teampilot/services/chat/session/history/jsonl_transcript_page_parser.dart';

void main() {
  tearDown(() {
    JsonlDecodeWorker.instance.dispose();
    JsonlPageWorker.instance.dispose();
  });

  test('page worker decodes and assembles with the selected adapter', () async {
    final page = await JsonlPageWorker.instance.parse(
      adapterId: 'claude',
      lines: [
        JsonlTranscriptLine(
          offset: 0,
          bytes: utf8.encode(
            '{"type":"user","uuid":"u1","message":'
            '{"id":"u1","content":"hello"}}',
          ),
        ),
        JsonlTranscriptLine(
          offset: 76,
          bytes: utf8.encode(
            '{"type":"user","uuid":"u2","message":'
            '{"id":"u2","content":"world"}}',
          ),
        ),
      ],
      sourceToken: 'worker-token',
      rebuilt: true,
      limit: 1,
    );

    expect(page, isNotNull);
    expect(page!.messages, hasLength(1));
    expect((page.messages.single.parts.single as AiTextPart).text, 'world');
    expect(page.hasOlder, isTrue);
  });

  test('decodes a batch of jsonl lines via the resident worker', () async {
    final lines = [
      utf8.encode('{"id": "m1", "role": "user"}'),
      utf8.encode('not-json'),
      utf8.encode('{"id": "m2", "role": "assistant"}'),
    ];
    final decoded = await decodeJsonlLines(lines);
    expect(decoded, hasLength(3));
    expect(decoded[0]?['id'], 'm1');
    expect(decoded[1], isNull);
    expect(decoded[2]?['role'], 'assistant');
  });

  test('empty batch returns immediately without a worker round-trip', () async {
    final decoded = await decodeJsonlLines(const []);
    expect(decoded, isEmpty);
  });

  test('idle worker exits and respawns on the next decode', () async {
    final worker = JsonlDecodeWorker.instance;
    worker.idleTimeout = const Duration(milliseconds: 80);
    try {
      final first = await decodeJsonlLines([utf8.encode('{"a": 1}')]);
      expect(first.single?['a'], 1);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      final second = await decodeJsonlLines([utf8.encode('{"b": 2}')]);
      expect(second.single?['b'], 2);
    } finally {
      worker.idleTimeout = const Duration(seconds: 30);
    }
  });

  test('decodeJsonlLinesSync decodes on the calling isolate', () {
    final decoded = decodeJsonlLinesSync([
      utf8.encode('{"id": "m1"}'),
      utf8.encode('not-json'),
      utf8.encode('{"id": "m2"}'),
    ]);
    expect(decoded, hasLength(3));
    expect(decoded[0]?['id'], 'm1');
    expect(decoded[1], isNull);
    expect(decoded[2]?['id'], 'm2');
  });

  test(
    'ready timeout discards zombie worker and falls back to local decode',
    () async {
      final worker = JsonlDecodeWorker.instance;
      worker.readyTimeout = const Duration(milliseconds: 40);
      worker.debugInstallZombieWorker();
      try {
        final first = await decodeJsonlLines([utf8.encode('{"x": 1}')]);
        expect(first, hasLength(1));
        expect(first.single?['x'], 1);

        // Zombie must not stick: a later call still succeeds (fresh worker or
        // local fallback), never empty-list RangeError fuel.
        final second = await decodeJsonlLines([utf8.encode('{"y": 2}')]);
        expect(second, hasLength(1));
        expect(second.single?['y'], 2);
      } finally {
        worker.readyTimeout = const Duration(seconds: 10);
      }
    },
  );
}
