import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/json_usage_store.dart';

import '../../support/in_memory_filesystem.dart';

SessionUsageEvent event({
  String id = 'claude:1',
  int output = 1,
  bool final_ = false,
  String session = 's1',
  String model = 'claude-sonnet-4',
  int timestampMs = 1,
  int? costMicroUsd,
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: CliTool.claude,
    model: model,
    inputTokens: 10,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: timestampMs,
    sessionId: session,
    isFinal: final_,
    costMicroUsd: costMicroUsd,
  );
}

void main() {
  late InMemoryFilesystem fs;
  late JsonUsageStore store;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    store = JsonUsageStore(fs: fs, filePath: '/tp/usage/events.jsonl');
  });

  test('inserts a new request', () async {
    final result = await store.upsert([event()]);

    expect(result.inserted, 1);
    expect(result.updated, 0);
    expect((await store.readLatest()).single.requestId, 'claude:1');
  });

  test('a final record replaces a non-final one', () async {
    await store.upsert([event(output: 1)]);
    final result = await store.upsert([event(output: 5, final_: true)]);

    expect(result.updated, 1);
    final latest = await store.readLatest();
    expect(latest.single.outputTokens, 5);
    expect(latest.single.isFinal, isTrue);
  });

  test('a larger output replaces an equally-final record', () async {
    await store.upsert([event(output: 5, final_: true)]);
    await store.upsert([event(output: 9, final_: true)]);

    expect((await store.readLatest()).single.outputTokens, 9);
  });

  test('a smaller or non-final snapshot is skipped', () async {
    await store.upsert([event(output: 9, final_: true)]);
    final result = await store.upsert([event(output: 2, final_: true)]);

    expect(result.skipped, 1);
    expect((await store.readLatest()).single.outputTokens, 9);
  });

  test(
    'ignores a malformed trailing line on load and appends safely',
    () async {
      await fs.writeString('/tp/usage/events.jsonl', '{"rev":0,"event":{"requ');

      final result = await store.upsert([event()]);

      expect(result.inserted, 1);
      expect((await store.readLatest()).single.requestId, 'claude:1');
      expect(await fs.readString('/tp/usage/events.jsonl'), contains('\n{'));
    },
  );

  test('zero-token events are not written', () async {
    final result = await store.upsert([
      SessionUsageEvent(
        requestId: 'zero',
        cli: CliTool.claude,
        model: '',
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: 0,
        sessionId: 's1',
      ),
    ]);

    expect(result.skipped, 1);
    expect(await store.readLatest(), isEmpty);
  });

  test('cost or model updates replace a final record', () async {
    await store.upsert([event(output: 5, final_: true)]);
    final result = await store.upsert([
      event(output: 5, final_: true, costMicroUsd: 1234, model: 'new-model'),
    ]);

    expect(result.updated, 1);
    final latest = (await store.readLatest()).single;
    expect(latest.costMicroUsd, 1234);
    expect(latest.model, 'new-model');
  });

  test(
    'compacts to the latest revision without losing current events',
    () async {
      await store.upsert([event(output: 1)]);
      await store.upsert([event(output: 5, final_: true)]);
      await store.upsert([event(id: 'claude:2', output: 2)]);

      final before = await store.stats();
      final result = await store.compact();
      final after = await store.stats();

      expect(before.lineCount, 3);
      expect(result.beforeLines, 3);
      expect(result.afterEvents, 2);
      expect(result.removedLines, 1);
      expect(result.removedEvents, 0);
      expect(after.lineCount, 2);
      expect((await store.readLatest()), hasLength(2));
      final first = (await store.readLatest()).firstWhere(
        (item) => item.requestId == 'claude:1',
      );
      expect(first.outputTokens, 5);
      expect(first.isFinal, isTrue);
    },
  );

  test('retention drops old events explicitly', () async {
    await store.upsert([
      event(id: 'old', timestampMs: 100),
      event(id: 'new', timestampMs: 300),
    ]);

    final result = await store.compact(retainAfterMs: 200);

    expect(result.removedEvents, 1);
    expect((await store.readLatest()).single.requestId, 'new');
  });

  test('reloads when another store instance changes the file', () async {
    await store.upsert([event(id: 'one')]);
    expect(await store.readLatest(), hasLength(1));

    final other = JsonUsageStore(fs: fs, filePath: '/tp/usage/events.jsonl');
    await other.upsert([event(id: 'two')]);

    expect(await store.readLatest(), hasLength(2));
  });
}
