import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/codex_session_history.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('codex_session_history_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String codexHome,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CODEX_HOME': codexHome},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> writeRollout(String codexHome) async {
    final dayDir = p.join(codexHome, 'sessions', '2026', '07', '10');
    await Directory(dayDir).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsString();
    await File(
      p.join(
        dayDir,
        'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
      ),
    ).writeAsString(fixture);
  }

  test('parses event_msg text and function_call tools', () async {
    await writeRollout(base.path);

    final snap = await const CodexSessionHistory().loadHistory(
      ctx(
        codexHome: base.path,
        persistedNativeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      ),
    );

    expect(snap.status, SessionHistoryLoadStatus.ready);
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.user && t.markdown.contains('list files'),
      ),
      isTrue,
    );
    expect(
      snap.turns.any(
        (t) =>
            t.role == SessionHistoryRole.assistant &&
            t.markdown.contains('Here are the files'),
      ),
      isTrue,
    );
    expect(
      snap.turns.any((t) => t.markdown.contains('environment_context')),
      isFalse,
    );
    expect(
      snap.turns.any((t) => t.markdown.contains('developer noise')),
      isFalse,
    );
    final tools = snap.turns.where((t) => t.role == SessionHistoryRole.tool);
    expect(tools, isNotEmpty);
    expect(tools.every((t) => t.collapsedByDefault), isTrue);
    expect(tools.any((t) => t.toolName == 'exec_command'), isTrue);
    expect(
      tools.where((t) => t.toolName == null),
      isEmpty,
      reason: 'function_call_output must correlate call_id → name',
    );
  });

  test('missing rollout is empty', () async {
    final snap = await const CodexSessionHistory().loadHistory(
      ctx(codexHome: base.path),
    );
    expect(snap.status, SessionHistoryLoadStatus.empty);
    expect(snap.turns, isEmpty);
  });
}
