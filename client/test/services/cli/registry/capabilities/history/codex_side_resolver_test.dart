import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/codex_side_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();
  const resolver = CodexSideResolver();

  const agentId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

  setUp(() async {
    base = await Directory.systemTemp.createTemp('codex_side_resolver_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({required String? codexHome}) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: codexHome == null ? const {} : {'CODEX_HOME': codexHome},
      transcriptRoots: const [],
      bucket: '',
    );
  }

  Future<String> writeRollout({
    required String relativeDir,
    required String rolloutName,
  }) async {
    final dir = p.join(base.path, 'sessions', relativeDir);
    await Directory(dir).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();
    final path = p.join(dir, rolloutName);
    await File(path).writeAsBytes(fixture);
    return path;
  }

  AiToolCallPart spawnAgentPart({
    Map<String, Object?>? args,
    Object? result,
  }) {
    return AiToolCallPart(
      toolCallId: 'call_spawn_1',
      toolName: 'spawn_agent',
      args: args,
      result: result,
    );
  }

  test('resolves rollout by agent_id from spawn_agent args', () async {
    final sidePath = await writeRollout(
      relativeDir: p.join('2026', '07', '10'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );

    final result = await resolver.resolve(
      part: spawnAgentPart(args: {'agent_id': agentId}),
      ctx: ctx(codexHome: base.path),
      parentHandle: null,
      rootTranscriptPath: null,
    );

    expect(result, isNotNull);
    expect(result!.handle, isA<SubagentFileHandle>());
    expect((result.handle as SubagentFileHandle).path, sidePath);
    expect(result.messages, isNotEmpty);
    expect(result.messages.first.role, AiRole.user);
  });

  test('resolves rollout by agentId from spawn_agent result map', () async {
    final sidePath = await writeRollout(
      relativeDir: p.join('2026', '07', '11'),
      rolloutName: 'rollout-2026-07-11T08-00-00-$agentId.jsonl',
    );

    final result = await resolver.resolve(
      part: spawnAgentPart(result: {'agentId': agentId}),
      ctx: ctx(codexHome: base.path),
      parentHandle: null,
      rootTranscriptPath: null,
    );

    expect(result, isNotNull);
    expect((result!.handle as SubagentFileHandle).path, sidePath);
  });

  test('returns null when rollout is missing or agent id absent', () async {
    expect(
      await resolver.resolve(
        part: spawnAgentPart(args: {'agent_id': agentId}),
        ctx: ctx(codexHome: base.path),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );

    await writeRollout(
      relativeDir: p.join('2026', '07', '10'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );

    expect(
      await resolver.resolve(
        part: spawnAgentPart(),
        ctx: ctx(codexHome: base.path),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );
  });

  test('does not read Claude subagents/ rollouts', () async {
    await writeRollout(
      relativeDir: p.join('subagents'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );

    expect(
      await resolver.resolve(
        part: spawnAgentPart(args: {'agent_id': agentId}),
        ctx: ctx(codexHome: base.path),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );
  });

  test('prefers rollout outside subagents when both exist', () async {
    await writeRollout(
      relativeDir: p.join('subagents'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );
    final outsidePath = await writeRollout(
      relativeDir: p.join('2026', '07', '10'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );

    final result = await resolver.resolve(
      part: spawnAgentPart(args: {'agent_id': agentId}),
      ctx: ctx(codexHome: base.path),
      parentHandle: null,
      rootTranscriptPath: null,
    );

    expect(result, isNotNull);
    expect((result!.handle as SubagentFileHandle).path, outsidePath);
  });

  test('returns null when CODEX_HOME is missing', () async {
    await writeRollout(
      relativeDir: p.join('2026', '07', '10'),
      rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
    );

    expect(
      await resolver.resolve(
        part: spawnAgentPart(args: {'agent_id': agentId}),
        ctx: ctx(codexHome: null),
        parentHandle: null,
        rootTranscriptPath: null,
      ),
      isNull,
    );
  });

  test(
    'scopes rollout search to parent session dir when parent path is known',
    () async {
      const parentId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final parentDir = p.join('2026', '07', '10');
      final otherDir = p.join('2026', '07', '11');

      final parentPath = await writeRollout(
        relativeDir: parentDir,
        rolloutName: 'rollout-2026-07-10T11-00-00-$parentId.jsonl',
      );
      final scopedChildPath = await writeRollout(
        relativeDir: parentDir,
        rolloutName: 'rollout-2026-07-10T12-00-00-$agentId.jsonl',
      );
      await writeRollout(
        relativeDir: otherDir,
        rolloutName: 'rollout-2026-07-11T23-59-59-$agentId.jsonl',
      );

      final result = await resolver.resolve(
        part: spawnAgentPart(args: {'agent_id': agentId}),
        ctx: ctx(codexHome: base.path),
        parentHandle: SubagentFileHandle(parentPath),
        rootTranscriptPath: null,
      );

      expect(result, isNotNull);
      expect((result!.handle as SubagentFileHandle).path, scopedChildPath);
    },
  );

  test(
    'uses rootTranscriptPath to scope rollout search when parentHandle is null',
    () async {
      const parentId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
      final parentDir = p.join('2026', '07', '12');
      final otherDir = p.join('2026', '07', '13');

      final parentPath = await writeRollout(
        relativeDir: parentDir,
        rolloutName: 'rollout-2026-07-12T09-00-00-$parentId.jsonl',
      );
      final scopedChildPath = await writeRollout(
        relativeDir: parentDir,
        rolloutName: 'rollout-2026-07-12T10-00-00-$agentId.jsonl',
      );
      await writeRollout(
        relativeDir: otherDir,
        rolloutName: 'rollout-2026-07-13T23-59-59-$agentId.jsonl',
      );

      final result = await resolver.resolve(
        part: spawnAgentPart(args: {'agent_id': agentId}),
        ctx: ctx(codexHome: base.path),
        parentHandle: null,
        rootTranscriptPath: parentPath,
      );

      expect(result, isNotNull);
      expect((result!.handle as SubagentFileHandle).path, scopedChildPath);
    },
  );
}
