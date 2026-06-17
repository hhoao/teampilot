import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/resume/codex_resume_strategy.dart';
import 'package:teampilot/services/cli/registry/capabilities/resume/cursor_resume_strategy.dart';
import 'package:teampilot/services/cli/registry/capabilities/resume/opencode_resume_strategy.dart';
import 'package:teampilot/services/cli/registry/capabilities/resume/transcript_resume_strategy.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_resume_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('resume_strategy_');
  });
  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  ResumeContext ctx({
    Map<String, String> env = const {},
    List<String> transcriptRoots = const [],
    String bucket = '',
    String taskId = 'task-1',
    String? persistedNativeId,
  }) {
    return ResumeContext(
      fs: fs,
      toolValue: 'x',
      taskId: taskId,
      env: env,
      transcriptRoots: transcriptRoots,
      bucket: bucket,
      persistedNativeId: persistedNativeId,
    );
  }

  group('CodexResumeStrategy', () {
    test('captures the rollout uuid from the isolated CODEX_HOME', () async {
      const id = '7f9f9a2e-1b3c-4c7a-9b0e-0123456789ab';
      final dir = p.join(base.path, 'sessions', '2026', '06', '17');
      await Directory(dir).create(recursive: true);
      await File(
        p.join(dir, 'rollout-2026-06-17T10-00-00-$id.jsonl'),
      ).writeAsString('{}');

      final got = await const CodexResumeStrategy()
          .detectNativeId(ctx(env: {'CODEX_HOME': base.path}));
      expect(got, id);
    });

    test('persisted id wins without scanning', () async {
      final got = await const CodexResumeStrategy().detectNativeId(
        ctx(env: {'CODEX_HOME': base.path}, persistedNativeId: 'kept'),
      );
      expect(got, 'kept');
    });

    test('returns null when nothing is stored', () async {
      final got = await const CodexResumeStrategy()
          .detectNativeId(ctx(env: {'CODEX_HOME': base.path}));
      expect(got, isNull);
    });
  });

  group('OpencodeResumeStrategy', () {
    test('captures ses_ id from the isolated data dir', () async {
      final dir = p.join(base.path, 'storage', 'session', 'projhash');
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'ses_abc123.json')).writeAsString('{}');

      final got = await const OpencodeResumeStrategy()
          .detectNativeId(ctx(env: {'OPENCODE_DATA_DIR': base.path}));
      expect(got, 'ses_abc123');
    });
  });

  group('CursorResumeStrategy', () {
    Future<void> writeChat(
      String chatId, {
      required bool hasConversation,
      required int updatedAtMs,
    }) async {
      final dir = p.join(base.path, 'chats', 'wshash', chatId);
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'meta.json')).writeAsString(
        '{"schemaVersion":1,"hasConversation":$hasConversation,'
        '"updatedAtMs":$updatedAtMs}',
      );
    }

    test('captures the newest chat that has a real conversation', () async {
      // An empty pre-created chat must be ignored in favor of the real one.
      await writeChat('empty', hasConversation: false, updatedAtMs: 200);
      await writeChat('real-old', hasConversation: true, updatedAtMs: 100);
      await writeChat('real-new', hasConversation: true, updatedAtMs: 150);

      final got = await const CursorResumeStrategy()
          .detectNativeId(ctx(env: {'CURSOR_CONFIG_DIR': base.path}));
      expect(got, 'real-new');
    });

    test('returns null when only empty chats exist', () async {
      await writeChat('empty', hasConversation: false, updatedAtMs: 200);
      final got = await const CursorResumeStrategy()
          .detectNativeId(ctx(env: {'CURSOR_CONFIG_DIR': base.path}));
      expect(got, isNull);
    });

    test('returns null when there is no chats dir', () async {
      final got = await const CursorResumeStrategy()
          .detectNativeId(ctx(env: {'CURSOR_CONFIG_DIR': base.path}));
      expect(got, isNull);
    });
  });

  group('TranscriptResumeStrategy', () {
    test('detects the pinned transcript file and returns the taskId', () async {
      final projects = p.join(base.path, 'projects', 'home-me-proj');
      await Directory(projects).create(recursive: true);
      await File(p.join(projects, 'task-1.jsonl')).writeAsString('{}');

      final got = await const TranscriptResumeStrategy().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, 'task-1');
    });

    test('returns null when no transcript exists', () async {
      final got = await const TranscriptResumeStrategy().detectNativeId(
        ctx(transcriptRoots: [base.path], bucket: 'home-me-proj'),
      );
      expect(got, isNull);
    });
  });
}
