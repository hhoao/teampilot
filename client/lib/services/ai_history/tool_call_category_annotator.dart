import 'package:ai_message_core/ai_message_core.dart';

/// 幂等标注:为每个 AiToolCallPart 填充 category。类别已匹配时跳过
/// copyWith(返回原实例),因此重复调用零分配、结果 identical。
List<AiMessage> annotateToolCallCategories(
  List<AiMessage> messages, {
  required AiToolCallCategoryResolver resolver,
}) {
  if (messages.isEmpty) return messages;
  var anyChanged = false;
  final out = <AiMessage>[];
  for (final message in messages) {
    var messageChanged = false;
    final parts = message.parts;
    final annotated = <AiMessagePart>[];
    for (final part in parts) {
      if (part is AiToolCallPart) {
        final category = resolver.resolve(part);
        if (category != part.category) {
          messageChanged = true;
          annotated.add(part.copyWith(category: category));
        } else {
          annotated.add(part);
        }
      } else {
        annotated.add(part);
      }
    }
    if (messageChanged) {
      anyChanged = true;
      out.add(message.copyWith(parts: annotated));
    } else {
      out.add(message);
    }
  }
  return anyChanged ? out : messages;
}

/// 对附件 map 的每条 transcript(含 workflow agents)做幂等标注。
Map<String, AiSubagentAttachment> annotateSubagentAttachments(
  Map<String, AiSubagentAttachment> attachments, {
  required AiToolCallCategoryResolver resolver,
}) {
  if (attachments.isEmpty) return attachments;
  final out = <String, AiSubagentAttachment>{};
  for (final entry in attachments.entries) {
    out[entry.key] = _annotateAttachment(entry.value, resolver);
  }
  return out;
}

AiSubagentAttachment _annotateAttachment(
  AiSubagentAttachment attachment,
  AiToolCallCategoryResolver resolver,
) {
  final messages = annotateToolCallCategories(
    attachment.messages,
    resolver: resolver,
  );
  final workflow = attachment.workflow;
  if (workflow == null) {
    return identical(messages, attachment.messages)
        ? attachment
        : attachment.copyWith(messages: messages);
  }
  var agentsChanged = false;
  final agents = <SubagentWorkflowAgent>[];
  for (final agent in workflow.agents) {
    final agentMessages = annotateToolCallCategories(
      agent.messages,
      resolver: resolver,
    );
    agentsChanged = agentsChanged || !identical(agentMessages, agent.messages);
    agents.add(
      identical(agentMessages, agent.messages)
          ? agent
          : agent.copyWith(messages: agentMessages),
    );
  }
  final nextWorkflow = agentsChanged
      ? workflow.copyWith(agents: agents)
      : workflow;
  return attachment.copyWith(messages: messages, workflow: nextWorkflow);
}
