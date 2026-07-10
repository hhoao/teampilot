import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/opencode_session_history.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('opencode_session_history_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String dataDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'OPENCODE_DATA_DIR': dataDir},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> copyFixtureTree() async {
    final fixtureRoot = Directory('test/fixtures/session_history/opencode');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  }

  test('parses disk messages and tool parts', () async {
    await copyFixtureTree();

    final snap = await const OpencodeSessionHistory().loadHistory(
      ctx(dataDir: base.path, persistedNativeId: 'ses_demo001'),
    );

    expect(snap.status, SessionHistoryLoadStatus.ready);
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.user &&
            t.markdown.contains('hello opencode'),
      ),
      isTrue,
    );
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.assistant &&
            t.markdown.contains('listing files'),
      ),
      isTrue,
    );
    final tools = snap.turns.where((t) => t.role == SessionHistoryRole.tool);
    expect(tools, isNotEmpty);
    expect(tools.every((t) => t.collapsedByDefault), isTrue);
    expect(tools.every((t) => t.toolName == 'bash'), isTrue);
  });

  test('missing session store is empty', () async {
    final snap = await const OpencodeSessionHistory().loadHistory(
      ctx(dataDir: base.path),
    );
    expect(snap.status, SessionHistoryLoadStatus.empty);
    expect(snap.turns, isEmpty);
  });
}
