import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/codex/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('codex_ai_transcript_');
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
    ).readAsBytes();
    await File(
      p.join(
        dayDir,
        'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
      ),
    ).writeAsBytes(fixture);
  }

  test(
    'CodexAiTranscriptAdapter parses event_msg and correlates function_call',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/codex/basic.jsonl',
      ).readAsBytes();
      final adapter = const CodexAiTranscriptAdapter();
      final messages = await adapter.parse(
        AiTranscriptBundle(
          adapterId: adapter.id,
          fragments: [
            AiTranscriptFragment(name: 'rollout.jsonl', bytes: bytes),
          ],
        ),
      );

      expect(adapter.id, 'codex');
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'list files');
      expect(user.createdAt, DateTime.parse('2026-07-10T12:00:04.000Z'));

      final assistant = messages[1];
      expect(assistant.role, AiRole.assistant);
      expect(assistant.parts[0], isA<AiToolCallPart>());
      expect(assistant.parts[1], isA<AiTextPart>());
      final tool = assistant.parts[0] as AiToolCallPart;
      expect(tool.toolCallId, 'call_1');
      expect(tool.toolName, 'exec_command');
      expect(tool.args, {'cmd': 'ls'});
      // argsText 是 arguments 原始字符串的忠实副本（统一 G2 语义）。
      expect(tool.argsText, '{"cmd":"ls"}');
      expect(tool.result, 'a.txt\nb.txt');
      expect((assistant.parts[1] as AiTextPart).text, 'Here are the files.');

      expect(
        messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('environment_context'),
          ),
        ),
        isFalse,
      );
      expect(
        messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('developer noise'),
          ),
        ),
        isFalse,
      );
      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test('locateCodexTranscript returns rollout bytes under CODEX_HOME', () async {
    await writeRollout(base.path);
    final fixture = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();

    final bundle = await locateCodexTranscript(
      ctx(
        codexHome: base.path,
        persistedNativeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      ),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'codex');
    expect(bundle.fragments, hasLength(1));
    expect(
      bundle.fragments.single.name,
      'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
    );
    expect(bundle.fragments.single.bytes, fixture);
  });

  test('locateCodexTranscript returns null when missing', () async {
    final bundle = await locateCodexTranscript(ctx(codexHome: base.path));
    expect(bundle, isNull);
  });

  test(
    'locateCodexTranscript stays on the root rollout when a newer '
    'spawn_agent child exists',
    () async {
      await _writeParentAndChildRollouts(base.path);

      final bundle = await locateCodexTranscript(ctx(codexHome: base.path));

      expect(bundle, isNotNull);
      expect(
        bundle!.fragments.single.name,
        'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
      );
    },
  );

  test(
    'locateCodexTranscript ignores a persisted child uuid and keeps the root',
    () async {
      await _writeParentAndChildRollouts(base.path);

      final bundle = await locateCodexTranscript(
        ctx(
          codexHome: base.path,
          persistedNativeId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        ),
      );

      expect(bundle, isNotNull);
      expect(
        bundle!.fragments.single.name,
        'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
      );
    },
  );

  test(
    'detectNativeId captures the root uuid when a newer spawn_agent child exists',
    () async {
      await _writeParentAndChildRollouts(base.path);

      final got = await const CodexAiHistoryCapability().detectNativeId(
        ResumeContext(
          fs: fs,
          toolValue: 'codex',
          taskId: 'task-1',
          env: {'CODEX_HOME': base.path},
          transcriptRoots: const [],
          bucket: '',
        ),
      );

      expect(got, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    },
  );

  test(
    'detectNativeId ignores a persisted child uuid and captures the root',
    () async {
      await _writeParentAndChildRollouts(base.path);

      final got = await const CodexAiHistoryCapability().detectNativeId(
        ResumeContext(
          fs: fs,
          toolValue: 'codex',
          taskId: 'task-1',
          env: {'CODEX_HOME': base.path},
          transcriptRoots: const [],
          bucket: '',
          persistedNativeId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        ),
      );

      expect(got, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    },
  );

  test(
      'parses user/assistant text from response_item.message (codex >=0.147 '
      'rollout format)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/response_item_messages.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'response_item_messages.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));

    final user = messages[0];
    expect(user.role, AiRole.user);
    expect((user.parts.single as AiTextPart).text, 'hello');

    final assistant = messages[1];
    expect(assistant.role, AiRole.assistant);
    expect(assistant.parts[0], isA<AiReasoningPart>());
    expect(assistant.parts[1], isA<AiToolCallPart>());
    expect(assistant.parts[2], isA<AiTextPart>());
    final tool = assistant.parts[1] as AiToolCallPart;
    expect(tool.toolCallId, 'call_1');
    expect(tool.toolName, 'exec_command');
    expect(tool.result, 'a.txt\nb.txt');
    expect(
      (assistant.parts[2] as AiTextPart).text,
      'Hello! Here are the files.',
    );

    // System/developer and AGENTS.md+environment_context noise stay filtered.
    expect(
      messages.any(
        (m) => m.parts.any(
          (p) => p is AiTextPart && p.text.contains('environment_context'),
        ),
      ),
      isFalse,
    );
    expect(
      messages.any(
        (m) => m.parts.any(
          (p) => p is AiTextPart && p.text.contains('developer noise'),
        ),
      ),
      isFalse,
    );
  });

  test(
      'response_item.message echo does not duplicate event_msg user/agent '
      'text (older codex wrote both)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/response_item_message_echo.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'response_item_message_echo.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'list files');
    expect(messages[1].role, AiRole.assistant);
    expect(
      (messages[1].parts.single as AiTextPart).text,
      'Here are the files.',
    );
  });

  test('parses reasoning summary and shell_command from real rollout shape',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/reasoning_and_tools.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'reasoning_and_tools.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'create issue tracker');

    final assistant = messages[1];
    expect(assistant.role, AiRole.assistant);
    expect(assistant.parts[0], isA<AiReasoningPart>());
    expect(assistant.parts[1], isA<AiToolCallPart>());
    expect(assistant.parts[2], isA<AiTextPart>());

    final reasoning = assistant.parts[0] as AiReasoningPart;
    expect(reasoning.text, contains('Issue management'));

    final tool = assistant.parts[1] as AiToolCallPart;
    expect(tool.toolName, 'shell_command');
    expect(tool.toolCallId, 'call_demo1');
    expect(tool.result, contains('/tmp/demo'));

    expect(
      (assistant.parts[2] as AiTextPart).text,
      'I will inspect the plan first.',
    );
  });

  test(
      'custom_tool_call String input that is JSON decodes into args, '
      'argsText keeps the raw copy (G2)',
      () {
    final messages = <AiMessage>[];
    final consumed = appendCodexJsonlEvent(
      messages,
      {
        'type': 'response_item',
        'timestamp': '2026-08-08T00:00:00.000Z',
        'payload': {
          'type': 'custom_tool_call',
          'name': 'spawn_agent',
          'call_id': 'call_custom_1',
          'input': '{"agentId":"agent-1","task":"doc"}',
        },
      },
      fallbackId: () => 'codex-0',
    );
    expect(consumed, isTrue);
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.toolCallId, 'call_custom_1');
    expect(tool.toolName, 'spawn_agent');
    // 统一 G2 语义：字符串先 jsonDecode 成 Map args，argsText 保留原始字符串。
    expect(tool.args, {'agentId': 'agent-1', 'task': 'doc'});
    expect(tool.argsText, '{"agentId":"agent-1","task":"doc"}');
  });

  test(
    'SubAgentActivity started binds agent_thread_id onto spawn_agent args',
    () {
      final messages = <AiMessage>[];
      String id() => 'codex-${messages.length}';

      expect(
        appendCodexJsonlEvent(
          messages,
          {
            'type': 'response_item',
            'timestamp': '2026-08-25T11:23:14.000Z',
            'payload': {
              'type': 'function_call',
              'name': 'spawn_agent',
              'call_id': 'call_spawn_1',
              'arguments':
                  '{"task_name":"task6_review","fork_turns":"none","message":"cipher"}',
            },
          },
          fallbackId: id,
        ),
        isTrue,
      );

      expect(
        appendCodexJsonlEvent(
          messages,
          {
            'type': 'event_msg',
            'timestamp': '2026-08-25T11:23:14.100Z',
            'payload': {
              'type': 'item_completed',
              'item': {
                'type': 'SubAgentActivity',
                'id': 'call_spawn_1',
                'kind': 'started',
                'agent_thread_id': '01a038a8-fd40-77a2-bb5a-59452ffa9bf0',
                'agent_path': '/root/task6_review',
              },
            },
          },
          fallbackId: id,
        ),
        isTrue,
      );

      final tool = messages.single.parts.single as AiToolCallPart;
      expect(tool.toolName, 'spawn_agent');
      expect(
        tool.args?['agent_id'],
        '01a038a8-fd40-77a2-bb5a-59452ffa9bf0',
      );
      expect(tool.args?['task_name'], 'task6_review');
      expect(subagentAgentIdFromPart(tool), '01a038a8-fd40-77a2-bb5a-59452ffa9bf0');
    },
  );

  test(
    'SubAgentActivity on send_message does not rewrite non-spawn tool args',
    () {
      final messages = <AiMessage>[];
      String id() => 'codex-${messages.length}';

      appendCodexJsonlEvent(
        messages,
        {
          'type': 'response_item',
          'timestamp': '2026-08-25T11:23:14.000Z',
          'payload': {
            'type': 'function_call',
            'name': 'send_message',
            'call_id': 'call_send_1',
            'arguments': '{"target":"/root/task6_review","message":"hi"}',
          },
        },
        fallbackId: id,
      );
      expect(
        appendCodexJsonlEvent(
          messages,
          {
            'type': 'event_msg',
            'timestamp': '2026-08-25T11:23:14.100Z',
            'payload': {
              'type': 'item_completed',
              'item': {
                'type': 'SubAgentActivity',
                'id': 'call_send_1',
                'kind': 'interacted',
                'agent_thread_id': '01a038a8-fd40-77a2-bb5a-59452ffa9bf0',
              },
            },
          },
          fallbackId: id,
        ),
        isFalse,
      );

      final tool = messages.single.parts.single as AiToolCallPart;
      expect(tool.args?.containsKey('agent_id'), isFalse);
      expect(subagentAgentIdFromPart(tool), isNull);
    },
  );

  test(
      'custom_tool_call non-JSON String input keeps args=null and '
      'argsText as faithful copy (G2)',
      () {
    final messages = <AiMessage>[];
    final consumed = appendCodexJsonlEvent(
      messages,
      {
        'type': 'response_item',
        'timestamp': '2026-08-08T00:00:00.000Z',
        'payload': {
          'type': 'custom_tool_call',
          'name': 'apply_patch',
          'call_id': 'call_custom_2',
          'input': '*** Begin Patch\n+line',
        },
      },
      fallbackId: () => 'codex-1',
    );
    expect(consumed, isTrue);
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.args, isNull);
    expect(tool.argsText, '*** Begin Patch\n+line');
  });

  test(
      'custom_tool_call Map input decodes into args, argsText stays null (G2)',
      () {
    final messages = <AiMessage>[];
    final consumed = appendCodexJsonlEvent(
      messages,
      {
        'type': 'response_item',
        'timestamp': '2026-08-08T00:00:00.000Z',
        'payload': {
          'type': 'custom_tool_call',
          'name': 'agent',
          'call_id': 'call_custom_3',
          'input': {'agentId': 'agent-2'},
        },
      },
      fallbackId: () => 'codex-2',
    );
    expect(consumed, isTrue);
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.args, {'agentId': 'agent-2'});
    expect(tool.argsText, isNull);
  });

  test(
      'custom_tool_call dual-form fixture parses end-to-end: String patch '
      'text → argsText; Map input → args (G2)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/custom_tool_call_dual_form.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'custom_tool_call_dual_form.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'fix the flaky test');

    final tools = messages
        .expand((m) => m.parts)
        .whereType<AiToolCallPart>()
        .toList();
    expect(tools, hasLength(2));

    // 真实 codex 形态：custom_tool_call.input 是 apply_patch 补丁文本
    // （String）→ args=null，argsText 保留原样；output 按 call_id 关联。
    final patch = tools[0];
    expect(patch.toolName, 'apply_patch');
    expect(patch.toolCallId, 'call_patch1');
    expect(patch.args, isNull);
    expect(
      patch.argsText,
      '*** Begin Patch\n'
      '*** Update File: /home/me/proj/src/app.dart\n'
      '@@\n'
      '-old code\n'
      '+new code\n'
      '*** End Patch',
    );
    expect(patch.result, 'Patch applied to 1 file');
    expect(patch.status, AiToolCallStatus.complete);

    // 防御形态：Map input → args Map，argsText 保持 null。
    final agent = tools[1];
    expect(agent.toolName, 'spawn_agent');
    expect(agent.toolCallId, 'call_agent1');
    expect(agent.args, {'agentId': 'agent-1', 'task': 'review the patch'});
    expect(agent.argsText, isNull);
    expect(agent.result, 'review passed');
    expect(agent.status, AiToolCallStatus.complete);
  });

  test(
      'fallback message ids are lazy codex-{seq} and unique (G1)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(name: 'rollout.jsonl', bytes: bytes),
        ],
      ),
    );
    final ids = messages.map((m) => m.id).toList();
    // 惰性 fallback：被丢弃的事件（session_meta / turn_context / 环境噪音 /
    // token_count / task_complete）不消耗序号；function_call 与紧随的
    // agent_message 合并后保留前者 id（codex-1）。
    expect(ids, orderedEquals(['codex-0', 'codex-1']));
    expect(ids.toSet().length, ids.length);
  });

  test(
      'function_call_output / custom_tool_call_output have no error flag: '
      'isError stays false even for failure-looking output (G6)',
      () {
    final messages = <AiMessage>[];
    var seq = 0;
    expect(
      appendCodexJsonlEvent(
        messages,
        {
          'type': 'response_item',
          'timestamp': '2026-08-08T00:00:00.000Z',
          'payload': {
            'type': 'function_call',
            'name': 'exec_command',
            'call_id': 'call_fail1',
            'arguments': '{"cmd":"ls /nope"}',
          },
        },
        fallbackId: () => 'codex-${seq++}',
      ),
      isTrue,
    );
    expect(
      appendCodexJsonlEvent(
        messages,
        {
          'type': 'response_item',
          'timestamp': '2026-08-08T00:00:01.000Z',
          'payload': {
            'type': 'function_call_output',
            'call_id': 'call_fail1',
            'output': 'Exit code: 1\nNo such file',
          },
        },
        fallbackId: () => 'codex-${seq++}',
      ),
      isTrue,
    );
    final tool = (messages.single.parts.single as AiToolCallPart);
    expect(tool.result, 'Exit code: 1\nNo such file');
    expect(tool.status, AiToolCallStatus.complete);
    // Codex rollout 的 function_call_output 只有 call_id + output（夹具与
    // 真实 rollout 均无 is_error/error 字段；失败形态以纯文本进 result）。
    // 故 isError 恒 false 是既定语义，不推导。
    expect(tool.isError, isFalse);
  });

  test(
      'empty call_id is dropped without consuming fallback seq (G4 既定语义)',
      () {
    // Codex rollout 的 function_call/custom_tool_call/custom_tool_call_output
    // 均恒带非空 call_id（夹具 + 真实 rollout 实测全部非空）；空 call_id 属
    // 损坏数据。与 cursor 不同（其 transcript 缺 id 是常态，需合成 id），codex
    // 的 call→output 关联靠两侧独立 call_id 相等，合成单侧 id 无法恢复关联，
    // 故丢弃事件（且不消耗 fallback 序号）是既定语义。
    final messages = <AiMessage>[];
    var seq = 0;
    String fallbackId() => 'codex-${seq++}';

    expect(
      appendCodexJsonlEvent(
        messages,
        {
          'type': 'response_item',
          'timestamp': '2026-08-08T00:00:00.000Z',
          'payload': {
            'type': 'function_call',
            'name': 'exec_command',
            'call_id': '',
            'arguments': '{"cmd":"ls"}',
          },
        },
        fallbackId: fallbackId,
      ),
      isFalse,
    );
    expect(messages, isEmpty);
    expect(seq, 0, reason: '丢弃的事件不消耗 fallback 序号');
  });

  test(
      'appendCodexJsonlEvent line-parse matches adapter (tailer dialect)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();
    final content = String.fromCharCodes(bytes);

    final adapter = const CodexAiTranscriptAdapter();
    final adapterMessages = await adapter.parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(name: 'rollout.jsonl', bytes: bytes),
        ],
      ),
    );

    final raw = <AiMessage>[];
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final event = _tryDecode(trimmed);
      if (event == null) continue;
      appendCodexJsonlEvent(raw, event, fallbackId: () => 't');
    }
    final lineMessages = finalizeAiMessagesForHistory(raw);

    expect(lineMessages, hasLength(adapterMessages.length));
    for (var i = 0; i < adapterMessages.length; i++) {
      expect(lineMessages[i].role, adapterMessages[i].role);
      expect(
        lineMessages[i].parts.length,
        adapterMessages[i].parts.length,
      );
      final a = lineMessages[i].parts;
      final b = adapterMessages[i].parts;
      for (var j = 0; j < a.length; j++) {
        if (a[j] is AiTextPart && b[j] is AiTextPart) {
          expect((a[j] as AiTextPart).text, (b[j] as AiTextPart).text);
        }
        if (a[j] is AiToolCallPart && b[j] is AiToolCallPart) {
          expect((a[j] as AiToolCallPart).toolName, (b[j] as AiToolCallPart).toolName);
          expect(
            (a[j] as AiToolCallPart).toolCallId,
            (b[j] as AiToolCallPart).toolCallId,
          );
        }
      }
    }
  });
}

Map<String, dynamic>? _tryDecode(String line) {
  try {
    final d = jsonDecode(line);
    return d is Map<String, dynamic> ? d : (d is Map ? Map<String, dynamic>.from(d) : null);
  } on FormatException {
    return null;
  }
}

/// Parent + a lexicographically newer spawn_agent child in the same day dir.
/// Current locate (newest filename) binds the child; the seat must stay on
/// the root (`source=cli`, no `parent_thread_id`).
Future<void> _writeParentAndChildRollouts(String codexHome) async {
  final dayDir = p.join(codexHome, 'sessions', '2026', '07', '10');
  await Directory(dayDir).create(recursive: true);
  final fixture = await File(
    'test/fixtures/session_history/codex/basic.jsonl',
  ).readAsBytes();
  await File(
    p.join(
      dayDir,
      'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
    ),
  ).writeAsBytes(fixture);
  await File(
    p.join(
      dayDir,
      'rollout-2026-07-10T13-00-00-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl',
    ),
  ).writeAsString(
    jsonEncode({
      'timestamp': '2026-07-10T13:00:00.000Z',
      'type': 'session_meta',
      'payload': {
        'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'parent_thread_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'source': {
          'subagent': {
            'thread_spawn': {
              'parent_thread_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
              'depth': 1,
            },
          },
        },
        'thread_source': 'subagent',
      },
    }),
  );
}
