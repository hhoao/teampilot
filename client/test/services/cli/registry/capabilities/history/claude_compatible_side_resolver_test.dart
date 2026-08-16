import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_side_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

/// Memo 行为测试:ClaudeCompatibleSideResolver 必须在子会话(side 文件)
/// 未变化时返回同一消息列表实例,让 loader/seat 的 identical 快速路径生效;
/// side 文件增长后必须重新解析出最新内容。
void main() {
  const resolver = ClaudeCompatibleSideResolver();

  late Directory base;
  late LocalFilesystem fs;
  late String parentPath;
  late String subagentsDir;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('claude_side_resolver_');
    fs = LocalFilesystem();
    parentPath = p.join(base.path, 'projects', 'bucket', 'sess.jsonl');
    await File(parentPath).create(recursive: true);
    subagentsDir = p.join(base.path, 'projects', 'bucket', 'sess', 'subagents');
    await Directory(subagentsDir).create(recursive: true);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext runCtx() => SessionHistoryContext(
    fs: fs,
    taskId: 'task-1',
    env: const {},
    transcriptRoots: const [],
    bucket: '',
  );

  AiToolCallPart agentPart() => const AiToolCallPart(
    toolCallId: 'toolu_1',
    toolName: 'Agent',
    status: AiToolCallStatus.incomplete,
  );

  String sideJsonl({required int lines}) {
    final roles = ['assistant', 'user'];
    return [
      for (var i = 0; i < lines; i++)
        jsonEncode({
          'type': roles[i % 2],
          'message': {
            'role': roles[i % 2],
            'content': [
              {'type': 'text', 'text': 'progress $i'},
            ],
          },
          'uuid': 's-$i',
          'timestamp': '2026-07-10T10:00:0${i + 2}.000Z',
        }),
    ].join('\n');
  }

  void writeMeta() {
    File(p.join(subagentsDir, 'agent-abc.meta.json')).writeAsStringSync(
      jsonEncode({'toolUseId': 'toolu_1'}),
    );
  }

  void writeSideFile(String content) {
    File(p.join(subagentsDir, 'agent-abc.jsonl')).writeAsStringSync(content);
  }

  test(
    'unchanged side file re-resolve returns the identical message list (memo)',
    () async {
      writeMeta();
      writeSideFile(sideJsonl(lines: 1));
      final ctx = runCtx();

      final first = await resolver.resolve(
        part: agentPart(),
        ctx: ctx,
        parentHandle: null,
        rootTranscriptPath: parentPath,
      );
      expect(first, isNotNull);
      expect(first!.messages, hasLength(1));

      final second = await resolver.resolve(
        part: agentPart(),
        ctx: ctx,
        parentHandle: null,
        rootTranscriptPath: parentPath,
      );

      expect(
        identical(first.messages, second!.messages),
        isTrue,
        reason: 'side 文件未变化时重复 resolve 必须复用同一消息列表实例——'
            'seat 的 identical 快速路径依赖它,否则每次刷新都要做内容比较'
            '(性能回归)',
      );
    },
  );

  test('side file growth re-parses only after size/mtime moves', () async {
    writeMeta();
    writeSideFile(sideJsonl(lines: 1));
    final ctx = runCtx();

    final first = await resolver.resolve(
      part: agentPart(),
      ctx: ctx,
      parentHandle: null,
      rootTranscriptPath: parentPath,
    );
    expect(first!.messages, hasLength(1));

    // 运行中的子 agent 追加内容:size 变化 → 指纹移动 → 重新解析。
    writeSideFile(sideJsonl(lines: 2));
    final second = await resolver.resolve(
      part: agentPart(),
      ctx: ctx,
      parentHandle: null,
      rootTranscriptPath: parentPath,
    );

    expect(second, isNotNull);
    expect(second!.messages, hasLength(2));
    expect(
      (second.messages.last.parts.single as AiTextPart).text,
      'progress 1',
    );
  });

  test('memo evicts and re-parses when the side file changes size only',
      () async {
    writeMeta();
    writeSideFile(sideJsonl(lines: 2));
    final ctx = runCtx();

    final first = await resolver.resolve(
      part: agentPart(),
      ctx: ctx,
      parentHandle: null,
      rootTranscriptPath: parentPath,
    );
    expect(first!.messages, hasLength(2));

    // 覆盖写为更短内容(size 变小,mtime 前进)→ 必须重新解析。
    writeSideFile(sideJsonl(lines: 1));
    final second = await resolver.resolve(
      part: agentPart(),
      ctx: ctx,
      parentHandle: null,
      rootTranscriptPath: parentPath,
    );

    expect(second, isNotNull);
    expect(second!.messages, hasLength(1));
  });
}
