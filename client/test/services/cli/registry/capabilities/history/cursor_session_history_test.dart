import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/cursor_session_history.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cursor_session_history_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String configDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': configDir},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> copyFixtureTree() async {
    final fixtureRoot = Directory('test/fixtures/session_history/cursor');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  }

  test('parses isolated projects agent-transcripts jsonl', () async {
    await copyFixtureTree();

    final snap = await const CursorSessionHistory().loadHistory(
      ctx(
        configDir: base.path,
        persistedNativeId: 'chat-aaaa-bbbb-cccc-dddd',
      ),
    );

    expect(snap.status, SessionHistoryLoadStatus.ready);
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.user &&
            t.markdown.contains('hello cursor'),
      ),
      isTrue,
    );
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.assistant &&
            t.markdown.contains('hi from cursor'),
      ),
      isTrue,
    );
    final tools = snap.turns.where((t) => t.role == SessionHistoryRole.tool);
    expect(tools, isNotEmpty);
    expect(tools.every((t) => t.collapsedByDefault), isTrue);
    expect(tools.any((t) => t.toolName == 'Shell'), isTrue);
    expect(
      tools.where((t) => t.toolName == null),
      isEmpty,
      reason: 'tool_result must correlate tool_use_id → name',
    );
  });

  test('missing chat transcript is empty', () async {
    final snap = await const CursorSessionHistory().loadHistory(
      ctx(configDir: base.path),
    );
    expect(snap.status, SessionHistoryLoadStatus.empty);
    expect(snap.turns, isEmpty);
  });
}
