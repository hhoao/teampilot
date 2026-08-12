import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';

Future<AiTranscriptBundle> jsonlBundle(String adapterId, String path) async {
  return AiTranscriptBundle(
    adapterId: adapterId,
    fragments: [
      AiTranscriptFragment(name: path.split('/').last, bytes: await File(path).readAsBytes()),
    ],
  );
}

void checkContract(String label, List<AiMessage> messages) {
  final ids = <String>{};
  var toolParts = 0;
  for (final m in messages) {
    expect(m.id, isNotEmpty, reason: '$label: 消息 id 非空');
    expect(ids.add(m.id), isTrue, reason: '$label: 消息 id 唯一 ${m.id}');
    for (final part in m.parts) {
      if (part is AiToolCallPart) {
        toolParts++;
        expect(part.toolCallId, isNotEmpty, reason: '$label: toolCallId 非空');
        expect(part.toolName, isNotEmpty, reason: '$label: toolName 非空');
        expect(part.args, anyOf(isNull, isA<Map<String, Object?>>()),
            reason: '$label: args 必须是 Map 或 null，不得是裸字符串');
        if (part.result != null) {
          expect(part.status, isNot(AiToolCallStatus.running),
              reason: '$label: 有 result 的 tool call 不得是 running');
        }
      }
      if (part is AiTextPart) {
        expect(part.text, isNotEmpty, reason: '$label: 文本 part 非空');
      }
    }
  }
  expect(toolParts, greaterThan(0), reason: '$label: 夹具应包含工具调用');
  // 消息级 status 推导为公共缺口（finalize 只规范化 part 级 status），
  // 待 Task 7 在 finalizeAiMessagesForHistory 补齐后恢复消息级严格断言。
  final finalized = finalizeAiMessagesForHistory(messages);
  for (final m in finalized) {
    for (final part in m.parts) {
      if (part is AiToolCallPart && part.status == AiToolCallStatus.running) {
        expect(m.status, AiMessageStatus.incomplete,
            reason: '$label: 有 running tool part 的消息不应为 complete');
      }
    }
  }
}

void main() {
  test('claude: 统一契约', () async {
    final bundle = await jsonlBundle(
      'claude',
      'test/fixtures/session_history/claude/truncated_bash.jsonl',
    );
    checkContract('claude', await const ClaudeAiTranscriptAdapter().parse(bundle));
  });

  test('codex: 统一契约', () async {
    final bundle = await jsonlBundle(
      'codex',
      'test/fixtures/session_history/codex/reasoning_and_tools.jsonl',
    );
    checkContract('codex', await const CodexAiTranscriptAdapter().parse(bundle));
  });

  test('cursor: 统一契约', () async {
    final bundle = await jsonlBundle(
      'cursor',
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/chat-aaaa-bbbb-cccc-dddd.jsonl',
    );
    checkContract('cursor', await const CursorAiTranscriptAdapter().parse(bundle));
  });

  test('flashskyai: 统一契约', () async {
    final bundle = await jsonlBundle(
      'flashskyai',
      'test/fixtures/session_history/flashskyai/streamed_tools.jsonl',
    );
    checkContract('flashskyai', await const FlashskyaiAiTranscriptAdapter().parse(bundle));
  });

  test('opencode: 统一契约（JSON tree 布局）', () async {
    final bundle = AiTranscriptBundle(
      adapterId: 'opencode',
      fragments: [
        AiTranscriptFragment(
          name: 'message/msg_asst1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'msg_asst1',
            'role': 'assistant',
            'time': {'created': 1720612802000},
          })),
        ),
        AiTranscriptFragment(
          name: 'part/msg_asst1/prt_text1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'prt_text1',
            'messageID': 'msg_asst1',
            'type': 'text',
            'text': 'done',
          })),
        ),
        AiTranscriptFragment(
          name: 'part/msg_asst1/prt_tool1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'prt_tool1',
            'messageID': 'msg_asst1',
            'type': 'tool',
            'toolCallID': 'call_1',
            'tool': 'edit',
            'state': {
              'status': 'completed',
              'input': {'filePath': 'a.txt', 'oldString': 'x', 'newString': 'y'},
            },
          })),
        ),
      ],
    );
    checkContract('opencode', await const OpencodeAiTranscriptAdapter().parse(bundle));
  });
}
