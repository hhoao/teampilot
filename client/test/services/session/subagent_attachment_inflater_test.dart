import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_side_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/capabilities/shared_tool_call_resolvers.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/subagent_attachment_inflater.dart';
import 'package:teampilot/services/session/subagent_side_transcript_path.dart';

import '../../support/in_memory_filesystem.dart';

SessionHistoryContext _testCtx(Filesystem fs) => SessionHistoryContext(
  fs: fs,
  taskId: 'task-1',
  env: const {},
  transcriptRoots: const [],
  bucket: 'bucket',
);

class _Cap implements AiHistoryCapability {
  _Cap(this.subagentSideResolver);

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null;

  @override
  String get tailFallbackPrefix => 'test';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher => const NoOpToolResultEnricher();

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  Map<String, String> sessionEnv({String? toolRoot}) => const {};

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async => null;

  static const _resolvers = SharedToolCallResolvers();

  @override
  AiEditToolTargetResolver get editResolver => _resolvers.editResolver;

  @override
  AiToolFileTargetResolver get fileResolver => _resolvers.fileResolver;

  @override
  AiShellToolTargetResolver get shellResolver => _resolvers.shellResolver;

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      _resolvers.categoryResolver;
}

Future<Map<String, AiSubagentAttachment>> _inflate({
  required List<AiMessage> messages,
  required Filesystem fs,
  required String? rootTranscriptPath,
  int maxDepth = 8,
  AiHistoryCapability? capability,
}) {
  return SubagentAttachmentInflater(maxDepth: maxDepth).inflate(
    messages: messages,
    ctx: _testCtx(fs),
    capability: capability ?? _Cap(const ClaudeCompatibleSideResolver()),
    rootTranscriptPath: rootTranscriptPath,
  );
}

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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
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
      rootTranscriptPath: null,
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

    final index = await _inflate(
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
      rootTranscriptPath: '',
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

    final index = await _inflate(
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
      rootTranscriptPath: '   ',
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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: parentPath,
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

    final index = await _inflate(
      messages: rootMessages,
      fs: fs,
      rootTranscriptPath: parentPath,
      maxDepth: maxDepth,
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

  test('Workflow run fans out into per-agent preview entries', () async {
    final fs = InMemoryFilesystem();
    final messages = [
      AiMessage(
        id: 'root',
        role: AiRole.assistant,
        parts: [
          const AiToolCallPart(
            toolCallId: 'call_00_wf',
            toolName: 'Workflow',
            args: {'script': 'export const meta = {};'},
          ),
        ],
      ),
    ];

    final index = await _inflate(
      messages: messages,
      fs: fs,
      rootTranscriptPath: '/projects/enc/uuid.jsonl',
      capability: _WorkflowCap(const _WorkflowStubResolver()),
    );

    final parent = index['call_00_wf'];
    expect(parent, isNotNull);
    final workflow = parent!.workflow;
    expect(workflow, isNotNull);
    expect(workflow!.runId, 'wf_run1');
    expect(workflow.workflowName, 'migrate');
    expect(workflow.agents, hasLength(2));

    final childAId = subagentWorkflowChildToolCallId('wf_run1', 'agent-a');
    final childBId = subagentWorkflowChildToolCallId('wf_run1', 'agent-b');
    expect(index.containsKey(childAId), isTrue);
    expect(index.containsKey(childBId), isTrue);

    final childA = index[childAId]!;
    expect(childA.title, 'implementer');
    expect(childA.messages, isNotEmpty);
    expect(childA.sidePath, endsWith('agent-agent-a.jsonl'));
    expect(
      childA.messages.single.parts.single,
      isA<AiTextPart>(),
    );
  });
}

class _WorkflowCap implements AiHistoryCapability {
  _WorkflowCap(this.subagentSideResolver);

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null;

  @override
  String get tailFallbackPrefix => 'test';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task', 'workflow'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher => const NoOpToolResultEnricher();

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  Map<String, String> sessionEnv({String? toolRoot}) => const {};

  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async => null;

  static const _resolvers = SharedToolCallResolvers();

  @override
  AiEditToolTargetResolver get editResolver => _resolvers.editResolver;

  @override
  AiToolFileTargetResolver get fileResolver => _resolvers.fileResolver;

  @override
  AiShellToolTargetResolver get shellResolver => _resolvers.shellResolver;

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      _resolvers.categoryResolver;
}

class _WorkflowStubResolver implements SubagentSideResolver {
  const _WorkflowStubResolver();

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    if (part.toolName.trim().toLowerCase() != 'workflow') return null;
    return SubagentSideResolveResult(
      messages: const [],
      handle: const SubagentFileHandle('/runs/wf_run1'),
      workflow: SubagentWorkflowInfo(
        runId: 'wf_run1',
        workflowName: 'migrate',
        status: 'DONE',
        phases: const ['Implement', 'Review'],
        agentCount: 2,
        summary: 'all done',
        agents: [
          SubagentWorkflowAgent(
            agentId: 'agent-a',
            role: 'implementer',
            status: 'DONE',
            messages: [
              AiMessage(
                id: 'a',
                role: AiRole.assistant,
                parts: const [AiTextPart(text: 'implemented')],
              ),
            ],
            handle: const SubagentFileHandle('/runs/wf_run1/agent-agent-a.jsonl'),
          ),
          SubagentWorkflowAgent(
            agentId: 'agent-b',
            role: 'reviewer',
            status: 'approved',
            messages: [
              AiMessage(
                id: 'b',
                role: AiRole.assistant,
                parts: const [AiTextPart(text: 'approved')],
              ),
            ],
            handle: const SubagentFileHandle('/runs/wf_run1/agent-agent-b.jsonl'),
          ),
        ],
      ),
    );
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async => null;
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
