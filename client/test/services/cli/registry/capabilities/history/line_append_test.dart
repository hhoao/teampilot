import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  for (final (cli, fixture) in [
    (CliTool.claude, 'claude/basic.jsonl'),
    (CliTool.codex, 'codex/basic.jsonl'),
    (CliTool.cursor, 'cursor/agent_transcript_no_tool_id.jsonl'),
  ]) {
    test('$cli: lineAppend replays fixture identically to full parse', () async {
      final capability =
          registry.capability<AiHistoryCapability>(cli)!;
      final bytes = await File(
        'test/fixtures/session_history/$fixture',
      ).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final adapterMessages = await capability.adapter.parse(
        AiTranscriptBundle(
          adapterId: cli.name,
          fragments: [AiTranscriptFragment(name: 't.jsonl', bytes: bytes)],
        ),
      );

      final replay = <AiMessage>[];
      var seq = 0;
      for (final line in const LineSplitter().convert(content)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final event = jsonDecode(trimmed) as Map<String, dynamic>;
        capability.lineAppend!(
          replay,
          event,
          fallbackId: () => '${cli.name}-${seq++}',
        );
      }
      // adapter.parse 内部对增量结果执行 finalizeAiMessagesForHistory(合并
      // 相邻 assistant、修正未配对工具状态);逐事件 replay 是未 finalize 的
      // 原始序列,因此对 replay 应用同一 finalize 后再做内容级比较,保证
      // "增量解析 == 全量解析"零分叉。
      final finalizedReplay = finalizeAiMessagesForHistory(replay);
      expect(
        sameMessageListContent(finalizedReplay, adapterMessages),
        isTrue,
        reason: 'lineAppend replay + finalize must equal adapter.parse',
      );
    });
  }
}
