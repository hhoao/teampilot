import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';
import 'package:teampilot/services/ai_history/tool_call_category_annotator.dart';

const resolver = defaultToolCallCategoryResolver;

AiMessage assistantWithTool(String toolName) => AiMessage(
  id: 'a1',
  role: AiRole.assistant,
  parts: [AiToolCallPart(toolCallId: '1', toolName: toolName)],
);

void main() {
  test('annotates tool parts, skips text and reasoning', () {
    final messages = [
      assistantWithTool('Bash'),
      const AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [
          AiTextPart(text: 'hi'),
          AiReasoningPart(text: 'think'),
          AiToolCallPart(toolCallId: '2', toolName: 'Read'),
        ],
      ),
    ];
    final out = annotateToolCallCategories(messages, resolver: resolver);
    final bash = (out[0].parts.single as AiToolCallPart);
    expect(bash.category, AiToolCallCategory.command);
    final read = out[1].parts
        .whereType<AiToolCallPart>()
        .single;
    expect(read.category, AiToolCallCategory.read);
  });

  test('idempotent: repeated annotation returns same instance', () {
    final once = annotateToolCallCategories(
      [assistantWithTool('Bash')],
      resolver: resolver,
    );
    final twice = annotateToolCallCategories(once, resolver: resolver);
    expect(identical(once, twice), isTrue);
  });

  test('unknown tools stay other', () {
    final out = annotateToolCallCategories(
      [assistantWithTool('custom_tool_call')],
      resolver: resolver,
    );
    expect((out.single.parts.single as AiToolCallPart).category,
        AiToolCallCategory.other);
  });

  test('annotates attachment transcripts including workflow agents', () {
    final sideMessages = [assistantWithTool('Grep')];
    final agent = SubagentWorkflowAgent(
      agentId: 'ag1',
      messages: [assistantWithTool('bash')],
      handle: const SubagentFileHandle('/side/a'),
    );
    final attachment = AiSubagentAttachment(
      toolCallId: 't1',
      messages: sideMessages,
      source: AiSubagentAttachmentSource.sideTranscript,
      workflow: SubagentWorkflowInfo(runId: 'r1', agents: [agent]),
    );
    final out = annotateSubagentAttachments(
      {'t1': attachment},
      resolver: resolver,
    );
    final edited = out['t1']!;
    expect(
      (edited.messages.single.parts.single as AiToolCallPart).category,
      AiToolCallCategory.read,
    );
    expect(
      (edited.workflow!.agents.single.messages.single.parts.single
              as AiToolCallPart)
          .category,
      AiToolCallCategory.command,
    );
  });
}
