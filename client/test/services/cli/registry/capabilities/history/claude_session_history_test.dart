import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/claude_session_history.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('claude_session_history_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required List<String> transcriptRoots,
    String bucket = 'home-me-proj',
    String taskId = 'task-1',
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: taskId,
      env: const {},
      transcriptRoots: transcriptRoots,
      bucket: bucket,
    );
  }

  test('parses user assistant and collapses tools', () async {
    final projects = p.join(base.path, 'projects', 'home-me-proj');
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsString();
    await File(p.join(projects, 'task-1.jsonl')).writeAsString(fixture);

    final snap = await const ClaudeSessionHistory().loadHistory(
      ctx(transcriptRoots: [base.path]),
    );

    expect(snap.status, SessionHistoryLoadStatus.ready);
    expect(snap.turns.any((t) => t.role == SessionHistoryRole.user), isTrue);
    expect(
      snap.turns.any((t) => t.role == SessionHistoryRole.assistant),
      isTrue,
    );
    expect(
      snap.turns.where((t) => t.role == SessionHistoryRole.tool).every(
        (t) => t.collapsedByDefault,
      ),
      isTrue,
    );
    expect(
      snap.turns.where((t) => t.role == SessionHistoryRole.tool),
      isNotEmpty,
    );
    final toolNames = snap.turns
        .where((t) => t.role == SessionHistoryRole.tool)
        .map((t) => t.toolName)
        .toList();
    expect(toolNames, isNot(contains('result')));
    expect(toolNames.where((n) => n == 'Bash').length, greaterThanOrEqualTo(2));
  });

  test('missing transcript file is empty', () async {
    final snap = await const ClaudeSessionHistory().loadHistory(
      ctx(transcriptRoots: [base.path]),
    );
    expect(snap.status, SessionHistoryLoadStatus.empty);
    expect(snap.turns, isEmpty);
  });
}
