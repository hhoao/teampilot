import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/subagent_attachment_inflater.dart';
import 'package:teampilot/services/session/subagent_side_transcript_path.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  const parentPath = '/projects/enc/uuid.jsonl';
  final subagentsDir = claudeSubagentsDirFor(parentPath);

  test('meta match prefers side transcript', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: subagentsDir, agentId: 'abc'),
      jsonEncode({'toolUseId': 'toolu_1'}),
    );
    await fs.writeString(
      claudeSubagentTranscriptPath(subagentsDir: subagentsDir, agentId: 'abc'),
      _userAssistantJsonl(user: 'explore', assistant: 'found auth'),
    );

    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_1',
            toolName: 'Agent',
            args: {'description': 'Explore auth'},
            result: 'summary',
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    final attachment = index['toolu_1'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.sideTranscript);
    expect(attachment.sidePath, endsWith('agent-abc.jsonl'));
    expect(attachment.title, 'Explore auth');
    expect(attachment.messages, isNotEmpty);
    // Real parser was used on side bytes.
    expect(
      parseClaudeCompatibleJsonl(
        await fs.readString(attachment.sidePath!) ?? '',
        fallbackId: () => 'fb',
      ),
      isNotEmpty,
    );
  });

  test('args agentId fallback hits side transcript without meta', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      claudeSubagentTranscriptPath(subagentsDir: subagentsDir, agentId: 'abc'),
      _userAssistantJsonl(user: 'do it', assistant: 'done'),
    );

    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_args',
            toolName: 'Agent',
            args: {'agentId': 'abc', 'description': 'via args'},
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    final attachment = index['toolu_args'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.sideTranscript);
    expect(attachment.sidePath, endsWith('agent-abc.jsonl'));
  });

  test('miss degrades to toolResult with result text', () async {
    final fs = InMemoryFilesystem();
    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_miss',
            toolName: 'Agent',
            args: {'description': 'missing side'},
            result: 'fallback body',
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    final attachment = index['toolu_miss'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(attachment.sidePath, isNull);
    expect(attachment.messages, hasLength(1));
    expect(
      (attachment.messages.single.parts.single as AiTextPart).text,
      'fallback body',
    );
  });

  test('miss with blank result keeps openable empty attachment', () async {
    final fs = InMemoryFilesystem();
    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_blank',
            toolName: 'Task',
            result: '   ',
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    final attachment = index['toolu_blank'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(attachment.messages, isEmpty);
  });

  test('null parentTranscriptPath is degrade-only without side FS', () async {
    final fs = _CountingListDirFilesystem();
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: subagentsDir, agentId: 'abc'),
      jsonEncode({'toolUseId': 'toolu_null_parent'}),
    );
    await fs.writeString(
      claudeSubagentTranscriptPath(subagentsDir: subagentsDir, agentId: 'abc'),
      _userAssistantJsonl(user: 'side', assistant: 'should not load'),
    );

    final index = await const SubagentAttachmentInflater().inflate(
      messages: [
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            const AiToolCallPart(
              toolCallId: 'toolu_null_parent',
              toolName: 'Agent',
              args: {'agentId': 'abc'},
              result: 'degraded',
            ),
          ],
        ),
      ],
      fs: fs,
      parentTranscriptPath: null,
    );

    final attachment = index['toolu_null_parent'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(attachment.sidePath, isNull);
    expect(
      (attachment.messages.single.parts.single as AiTextPart).text,
      'degraded',
    );
    expect(fs.listDirCount, 0);
  });

  test('blank parentTranscriptPath is degrade-only without side FS', () async {
    final fs = _CountingListDirFilesystem();
    // Files that blank-path stem join would otherwise discover.
    await fs.writeString(
      'subagents/agent-abc.meta.json',
      jsonEncode({'toolUseId': 'toolu_blank_parent'}),
    );
    await fs.writeString(
      'subagents/agent-abc.jsonl',
      _userAssistantJsonl(user: 'side', assistant: 'should not load'),
    );

    final index = await const SubagentAttachmentInflater().inflate(
      messages: [
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            const AiToolCallPart(
              toolCallId: 'toolu_blank_parent',
              toolName: 'Agent',
              args: {'agentId': 'abc'},
              result: 'degraded',
            ),
          ],
        ),
      ],
      fs: fs,
      parentTranscriptPath: '',
    );

    final attachment = index['toolu_blank_parent'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(attachment.sidePath, isNull);
    expect(
      (attachment.messages.single.parts.single as AiTextPart).text,
      'degraded',
    );
    expect(fs.listDirCount, 0);
  });

  test('whitespace parentTranscriptPath is degrade-only without side FS',
      () async {
    final fs = _CountingListDirFilesystem();

    final index = await const SubagentAttachmentInflater().inflate(
      messages: [
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            const AiToolCallPart(
              toolCallId: 'toolu_ws_parent',
              toolName: 'Task',
              args: {'agentId': 'abc'},
              result: 'degraded',
            ),
          ],
        ),
      ],
      fs: fs,
      parentTranscriptPath: '   ',
    );

    final attachment = index['toolu_ws_parent'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(fs.listDirCount, 0);
  });

  test('nested side transcript meta under child stem', () async {
    final fs = InMemoryFilesystem();
    final parentSide = claudeSubagentTranscriptPath(
      subagentsDir: subagentsDir,
      agentId: 'abc',
    );
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: subagentsDir, agentId: 'abc'),
      jsonEncode({'toolUseId': 'toolu_parent'}),
    );
    await fs.writeString(
      parentSide,
      _agentToolJsonl(
        toolCallId: 'toolu_child',
        agentIdHint: null,
        description: 'child work',
      ),
    );

    final childSubagents = claudeSubagentsDirFor(parentSide);
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: childSubagents, agentId: 'child'),
      jsonEncode({'toolUseId': 'toolu_child'}),
    );
    await fs.writeString(
      claudeSubagentTranscriptPath(
        subagentsDir: childSubagents,
        agentId: 'child',
      ),
      _userAssistantJsonl(user: 'nested', assistant: 'child done'),
    );

    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_parent',
            toolName: 'Agent',
            args: {'description': 'parent'},
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    expect(index.keys, containsAll(['toolu_parent', 'toolu_child']));
    expect(
      index['toolu_parent']!.source,
      AiSubagentAttachmentSource.sideTranscript,
    );
    expect(
      index['toolu_child']!.source,
      AiSubagentAttachmentSource.sideTranscript,
    );
    expect(index['toolu_child']!.sidePath, endsWith('agent-child.jsonl'));
  });

  test('side read throw degrades to toolResult without rethrow', () async {
    final fs = _ThrowingSideReadFilesystem();
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: subagentsDir, agentId: 'abc'),
      jsonEncode({'toolUseId': 'toolu_throw'}),
    );
    await fs.writeString(
      claudeSubagentTranscriptPath(subagentsDir: subagentsDir, agentId: 'abc'),
      _userAssistantJsonl(user: 'side', assistant: 'unreachable'),
    );

    final messages = [
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_throw',
            toolName: 'Agent',
            args: {'description': 'read throws'},
            result: 'fallback from throw',
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater().inflate(
      messages: messages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    final attachment = index['toolu_throw'];
    expect(attachment, isNotNull);
    expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
    expect(attachment.sidePath, isNull);
    expect(
      (attachment.messages.single.parts.single as AiTextPart).text,
      'fallback from throw',
    );
  });

  test('depth cap still degrade-attaches deepest Agent without past-cap recurse',
      () async {
    final fs = InMemoryFilesystem();
    const maxDepth = 8;

    // Build a chain of side transcripts: each level's jsonl contains the next Agent.
    var currentParentPath = parentPath;
    for (var depth = 0; depth < maxDepth; depth++) {
      final agentId = 'd$depth';
      final toolCallId = 'toolu_d$depth';
      final dir = claudeSubagentsDirFor(currentParentPath);
      await fs.writeString(
        claudeSubagentMetaPath(subagentsDir: dir, agentId: agentId),
        jsonEncode({'toolUseId': toolCallId}),
      );
      final sidePath = claudeSubagentTranscriptPath(
        subagentsDir: dir,
        agentId: agentId,
      );
      final nextToolCallId = 'toolu_d${depth + 1}';
      await fs.writeString(
        sidePath,
        _agentToolJsonl(
          toolCallId: nextToolCallId,
          agentIdHint: 'd${depth + 1}',
          description: 'depth ${depth + 1}',
          result: 'r$depth',
        ),
      );
      currentParentPath = sidePath;
    }

    // Past-cap payload under the deepest side stem — must not be indexed.
    final pastCapDir = claudeSubagentsDirFor(currentParentPath);
    await fs.writeString(
      claudeSubagentMetaPath(subagentsDir: pastCapDir, agentId: 'd$maxDepth'),
      jsonEncode({'toolUseId': 'toolu_d$maxDepth'}),
    );
    await fs.writeString(
      claudeSubagentTranscriptPath(
        subagentsDir: pastCapDir,
        agentId: 'd$maxDepth',
      ),
      _userAssistantJsonl(user: 'past', assistant: 'should not load'),
    );

    final rootMessages = [
      AiMessage(
        id: 'root',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'toolu_d0',
            toolName: 'Agent',
            args: {'description': 'depth 0'},
          ),
        ],
      ),
    ];

    final index = await const SubagentAttachmentInflater(maxDepth: maxDepth)
        .inflate(
      messages: rootMessages,
      fs: fs,
      parentTranscriptPath: parentPath,
    );

    for (var depth = 0; depth < maxDepth; depth++) {
      expect(index.containsKey('toolu_d$depth'), isTrue, reason: 'depth $depth');
      expect(
        index['toolu_d$depth']!.source,
        AiSubagentAttachmentSource.sideTranscript,
      );
    }

    // Agent at depth == maxDepth is still attached, but degrade-only.
    expect(index.containsKey('toolu_d$maxDepth'), isTrue);
    expect(
      index['toolu_d$maxDepth']!.source,
      AiSubagentAttachmentSource.toolResult,
    );
    expect(index['toolu_d$maxDepth']!.sidePath, isNull);

    // Nothing past the cap.
    expect(index.containsKey('toolu_d${maxDepth + 1}'), isFalse);
  });
}

String _userAssistantJsonl({required String user, required String assistant}) {
  return [
    jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': user},
      'uuid': 'u-${user.hashCode}',
      'timestamp': '2026-07-10T10:00:00.000Z',
    }),
    jsonEncode({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': assistant},
        ],
      },
      'uuid': 'a-${assistant.hashCode}',
      'timestamp': '2026-07-10T10:00:01.000Z',
    }),
  ].join('\n');
}

String _agentToolJsonl({
  required String toolCallId,
  required String? agentIdHint,
  required String description,
  Object? result,
}) {
  final input = <String, Object?>{
    'description': description,
    if (agentIdHint != null) 'agentId': agentIdHint,
  };
  final lines = <String>[
    jsonEncode({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': toolCallId,
            'name': 'Agent',
            'input': input,
          },
        ],
      },
      'uuid': 'a-$toolCallId',
      'timestamp': '2026-07-10T10:00:02.000Z',
    }),
  ];
  if (result != null) {
    lines.add(
      jsonEncode({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolCallId,
              'content': result,
            },
          ],
        },
        'uuid': 'u-$toolCallId',
        'timestamp': '2026-07-10T10:00:03.000Z',
      }),
    );
  }
  return lines.join('\n');
}

class _CountingListDirFilesystem extends InMemoryFilesystem {
  int listDirCount = 0;

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    listDirCount++;
    return super.listDir(path);
  }
}

class _ThrowingSideReadFilesystem extends InMemoryFilesystem {
  @override
  Future<String?> readString(String path) async {
    if (path.endsWith('.jsonl')) {
      throw StateError('simulated side read failure');
    }
    return super.readString(path);
  }
}
