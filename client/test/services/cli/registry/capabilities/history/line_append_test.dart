import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

/// Per-fixture expected consumed flags (true = produced or mutated a message).
const _expectedConsumed = {
  CliTool.claude: [true, true, true, true],
  CliTool.codex: [
    false, // session_meta
    false, // turn_context
    false, // user_message with environment_context
    false, // response_item.message role=developer
    true, // user_message "list files"
    true, // function_call
    true, // function_call_output (applies to call_1)
    true, // agent_message
    false, // token_count
    false, // task_complete
  ],
  CliTool.cursor: [
    true, // user text
    true, // assistant tool_use
    true, // assistant text (merges into previous)
    false, // turn_ended
  ],
};

Future<String> _fixtureContent(String fixture) async {
  final bytes = await File(
    'test/fixtures/session_history/$fixture',
  ).readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

/// Replays every event of [content] through [capability].lineAppend into
/// [messages], returning the per-line consumed flags. Tolerant decode: lines
/// that are not JSON objects are skipped (like the adapters do).
List<bool> _replay(
  AiHistoryCapability capability,
  List<AiMessage> messages,
  String content,
) {
  final consumed = <bool>[];
  var seq = 0;
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final event = tryDecodeJsonlLine(trimmed);
    if (event == null) continue;
    final ok = capability.lineAppend!(
      messages,
      event,
      fallbackId: () => '${capability.adapter.id}-${seq++}',
    );
    consumed.add(ok);
  }
  return consumed;
}

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
      final content = await _fixtureContent(fixture);
      final bytes = utf8.encode(content);
      final adapterMessages = await capability.adapter.parse(
        AiTranscriptBundle(
          adapterId: cli.name,
          fragments: [AiTranscriptFragment(name: 't.jsonl', bytes: bytes)],
        ),
      );

      final replay = <AiMessage>[];
      _replay(capability, replay, content);
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

    test('$cli: consumed flags match event semantics', () async {
      final capability =
          registry.capability<AiHistoryCapability>(cli)!;
      final replay = <AiMessage>[];
      final consumed = _replay(
        capability,
        replay,
        await _fixtureContent(fixture),
      );
      expect(
        consumed,
        _expectedConsumed[cli],
        reason: 'events producing/mutating messages must return true, '
            'meta/no-content events false',
      );
    });

    test('$cli: replaying the fixture twice is idempotent', () async {
      final capability =
          registry.capability<AiHistoryCapability>(cli)!;
      final content = await _fixtureContent(fixture);
      final replay = <AiMessage>[];
      final second = <AiMessage>[];
      _replay(capability, replay, content);
      _replay(capability, second, content);

      expect(
        sameMessageListContent(
          finalizeAiMessagesForHistory(replay),
          finalizeAiMessagesForHistory(second),
        ),
        isTrue,
        reason: 'second replay must not duplicate or drift messages',
      );
    });
  }

  test(
      'claude: tool_result-only event mutates without adding and is idempotent',
      () async {
    final capability =
        registry.capability<AiHistoryCapability>(CliTool.claude)!;
    final messages = <AiMessage>[];
    var seq = 0;
    expect(
      capability.lineAppend!(
        messages,
        {
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'id': 't1', 'name': 'Bash'},
            ],
          },
        },
        fallbackId: () => 'claude-${seq++}',
      ),
      isTrue,
    );
    final toolResultEvent = {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'},
        ],
      },
    };

    expect(
      capability.lineAppend!(messages, toolResultEvent,
          fallbackId: () => 'claude-${seq++}'),
      isTrue,
      reason: 'tool_result-only event mutates a previous message',
    );
    expect(messages, hasLength(1),
        reason: 'tool_result-only event must not add a message');
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.result, 'ok');

    final before = finalizeAiMessagesForHistory(messages);
    expect(
      capability.lineAppend!(messages, toolResultEvent,
          fallbackId: () => 'claude-${seq++}'),
      isTrue,
      reason: 're-applying a tool_result is still consumed',
    );
    expect(
      sameMessageListContent(before, finalizeAiMessagesForHistory(messages)),
      isTrue,
      reason: 're-applying the same tool_result must not duplicate',
    );
  });

  test(
      'cursor: tool_result-only event mutates without adding and is idempotent',
      () async {
    final capability =
        registry.capability<AiHistoryCapability>(CliTool.cursor)!;
    final messages = <AiMessage>[];
    var seq = 0;
    expect(
      capability.lineAppend!(
        messages,
        {
          'role': 'assistant',
          'message': {
            'content': [
              {'type': 'tool_use', 'id': 't1', 'name': 'Read'},
            ],
          },
        },
        fallbackId: () => 'cursor-${seq++}',
      ),
      isTrue,
    );
    final toolResultEvent = {
      'role': 'user',
      'message': {
        'content': [
          {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'},
        ],
      },
    };

    expect(
      capability.lineAppend!(messages, toolResultEvent,
          fallbackId: () => 'cursor-${seq++}'),
      isTrue,
      reason: 'tool_result-only event mutates a previous message',
    );
    expect(messages, hasLength(1),
        reason: 'tool_result-only event must not add a message');
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.result, 'ok');

    final before = finalizeAiMessagesForHistory(messages);
    expect(
      capability.lineAppend!(messages, toolResultEvent,
          fallbackId: () => 'cursor-${seq++}'),
      isTrue,
      reason: 're-applying a tool_result is still consumed',
    );
    expect(
      sameMessageListContent(before, finalizeAiMessagesForHistory(messages)),
      isTrue,
      reason: 're-applying the same tool_result must not duplicate',
    );
  });

  test('claude: discarded id-less events do not consume fallback ids',
      () async {
    final capability =
        registry.capability<AiHistoryCapability>(CliTool.claude)!;
    final messages = <AiMessage>[];
    var seq = 0;
    expect(
      capability.lineAppend!(
        messages,
        {
          'type': 'user',
          'message': {'role': 'user', 'content': '   '},
        },
        fallbackId: () => 'claude-${seq++}',
      ),
      isFalse,
    );
    expect(seq, 0, reason: 'discarded event must not consume a fallback id');
  });

  test('cursor: discarded id-less events do not consume fallback ids',
      () async {
    final capability =
        registry.capability<AiHistoryCapability>(CliTool.cursor)!;
    final messages = <AiMessage>[];
    var seq = 0;
    expect(
      capability.lineAppend!(
        messages,
        {
          'role': 'user',
          'message': {'content': '[REDACTED]'},
        },
        fallbackId: () => 'cursor-${seq++}',
      ),
      isFalse,
    );
    expect(seq, 0, reason: 'discarded event must not consume a fallback id');
  });
}
