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
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: CliTool.claude,
    model: 'claude-sonnet-4',
    inputTokens: 10,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: 1,
    sessionId: session,
    isFinal: final_,
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

  test('ignores a malformed trailing line on load and appends safely', () async {
    await fs.writeString('/tp/usage/events.jsonl', '{"rev":0,"event":{"requ');

    final result = await store.upsert([event()]);

    expect(result.inserted, 1);
    expect((await store.readLatest()).single.requestId, 'claude:1');
    expect(await fs.readString('/tp/usage/events.jsonl'), contains('\n{'));
  });

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
}
