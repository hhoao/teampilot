import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late String toolRoot;
  const capability = ClaudeAiHistoryCapability();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('claude_persisted_id_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    toolRoot = fs.pathContext.join(tmp.path, 'claude-config');
  });

  Future<void> writeTranscript(String id, {String bucket = 'b1'}) async {
    final dir = fs.pathContext.join(toolRoot, 'projects', bucket);
    await fs.ensureDir(dir);
    await fs.writeString(
      fs.pathContext.join(dir, '$id.jsonl'),
      '{"type":"user","message":{"content":"hi"}}\n',
    );
  }

  ResumeContext resumeCtx({String? persisted}) => ResumeContext(
        fs: fs,
        toolValue: 'claude',
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  SessionHistoryContext historyCtx({String? persisted}) =>
      SessionHistoryContext(
        fs: fs,
        taskId: 'new-task-id',
        env: const {},
        transcriptRoots: [toolRoot],
        bucket: 'b1',
        persistedNativeId: persisted,
      );

  test('detect prefers a persisted id whose transcript exists', () async {
    await writeTranscript('old-session-id');
    final id = await capability.detectNativeId(
      resumeCtx(persisted: 'old-session-id'),
    );
    expect(id, 'old-session-id');
  });

  test('detect falls back to taskId probe when persisted transcript misses',
      () async {
    await writeTranscript('new-task-id');
    final id = await capability.detectNativeId(resumeCtx(persisted: 'gone'));
    expect(id, 'new-task-id');
  });

  test('detect returns null when neither id has a transcript', () async {
    final id = await capability.detectNativeId(resumeCtx(persisted: 'gone'));
    expect(id, isNull);
  });

  test('taskId-only behavior unchanged when no persisted id', () async {
    await writeTranscript('new-task-id');
    final id = await capability.detectNativeId(resumeCtx());
    expect(id, 'new-task-id');
  });

  test('locate prefers the persisted transcript', () async {
    await writeTranscript('old-session-id');
    final bundle = await locateClaudeTranscript(historyCtx(
      persisted: 'old-session-id',
    ));
    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.name, 'old-session-id.jsonl');
  });

  test('locate falls back to taskId when persisted transcript misses',
      () async {
    await writeTranscript('new-task-id');
    final bundle = await locateClaudeTranscript(historyCtx(persisted: 'gone'));
    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.name, 'new-task-id.jsonl');
  });
}
