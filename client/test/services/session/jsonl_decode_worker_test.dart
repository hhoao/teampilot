import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/jsonl_decode_worker.dart';

void main() {
  tearDown(() {
    JsonlDecodeWorker.instance.dispose();
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
