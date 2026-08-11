import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('AiSubagentAttachment stores typed handle', () {
    const file = SubagentFileHandle('/tmp/a.jsonl');
    const att = AiSubagentAttachment(
      toolCallId: '1',
      messages: [],
      source: AiSubagentAttachmentSource.sideTranscript,
      handle: file,
    );
    expect(att.handle, same(file));
    expect(att.sidePath, '/tmp/a.jsonl');

    const session = AiSubagentAttachment(
      toolCallId: '2',
      messages: [],
      source: AiSubagentAttachmentSource.sideTranscript,
      handle: SubagentSessionHandle('ses_x'),
    );
    expect(session.sidePath, isNull);
  });

  test('subagentTitleFromPart prefers description then prompt', () {
    expect(
      subagentTitleFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Agent',
        args: {'description': 'Explore auth', 'prompt': 'long…'},
      )),
      'Explore auth',
    );
    expect(
      subagentTitleFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Task',
        args: {'prompt': 'Do the thing'},
      )),
      'Do the thing',
    );
  });

  test('syntheticSubagentMessagesFromResult null/blank → empty list', () {
    expect(
      syntheticSubagentMessagesFromResult(toolCallId: '1', result: null),
      isEmpty,
    );
    expect(
      syntheticSubagentMessagesFromResult(toolCallId: '1', result: '  '),
      isEmpty,
    );
  });

  test('syntheticSubagentMessagesFromResult keeps non-empty result text', () {
    final msgs = syntheticSubagentMessagesFromResult(
      toolCallId: '1',
      result: 'done',
    );
    expect(msgs, hasLength(1));
    expect((msgs.single.parts.single as AiTextPart).text, 'done');
  });

  test('attachment copyWith preserves workflow when not provided', () {
    final messages = [AiMessage(id: 'a', role: AiRole.assistant, parts: [])];
    final wf = const SubagentWorkflowInfo(runId: 'r1');
    final attachment = AiSubagentAttachment(
      toolCallId: 't1',
      messages: messages,
      source: AiSubagentAttachmentSource.sideTranscript,
      workflow: wf,
    );
    final edited = attachment.copyWith(messages: messages);
    expect(edited.workflow, same(wf));
    expect(edited.messages, same(messages));
  });

  test('workflow copyWith rebuilds agents', () {
    const messages = [AiMessage(id: 'a', role: AiRole.assistant, parts: [])];
    const agent = SubagentWorkflowAgent(
      agentId: 'ag1',
      messages: messages,
      handle: SubagentFileHandle('/side/a'),
    );
    final wf = const SubagentWorkflowInfo(runId: 'r1', agents: [agent]);
    final newMessages = [
      AiMessage(id: 'b', role: AiRole.assistant, parts: [AiTextPart(text: 'x')]),
    ];
    final wfEdited = wf.copyWith(
      agents: [agent.copyWith(messages: newMessages)],
    );
    expect(wfEdited.agents.single.messages, same(newMessages));
    expect(wfEdited.runId, 'r1');
  });

  test('subagentAgentIdFromPart reads args then Map result', () {
    expect(
      subagentAgentIdFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Agent',
        args: {'agentId': 'from-args'},
      )),
      'from-args',
    );
    expect(
      subagentAgentIdFromPart(AiToolCallPart(
        toolCallId: '1',
        toolName: 'Task',
        result: {'agentId': 'from-result', 'status': 'completed'},
      )),
      'from-result',
    );
  });
}
