import 'package:ai_message_core/ai_message_core.dart';

/// True for teammate-bus `wait_for_message` under CLI-specific MCP names
/// (`wait_for_message`, `teammate-bus_wait_for_message`,
/// `mcp__teammate-bus__wait_for_message`, `mcp__teammate_bus::wait_for_message`).
bool isWaitForMessageToolName(String toolName) {
  final name = toolName.trim();
  if (name.isEmpty) return false;
  const suffix = 'wait_for_message';
  if (name == suffix) return true;
  return name.endsWith('_$suffix') ||
      name.endsWith('::$suffix') ||
      name.endsWith('.$suffix');
}

int lastWaitForMessageIndex(List<AiMessagePart> parts) {
  for (var i = parts.length - 1; i >= 0; i--) {
    final part = parts[i];
    if (part is AiToolCallPart && isWaitForMessageToolName(part.toolName)) {
      return i;
    }
  }
  return -1;
}

/// Infix for the assistant-prose half after a wait-anchor split.
const waitAnchorTailInfix = '::after:';

String waitAnchorTailId(String messageId, String toolCallId) =>
    '$messageId$waitAnchorTailInfix$toolCallId';

bool isWaitAnchorTailId(String messageId) =>
    messageId.contains(waitAnchorTailInfix);

bool _isMailboxUser(AiMessage message) =>
    message.role == AiRole.user && message.deliveryChannel == 'mailbox';

/// Places mailbox user bubbles immediately after `wait_for_message` when that
/// tool shares an assistant message with later prose (Cursor/Claude merge
/// tools-then-text into one turn). Timestamp sort alone cannot do this because
/// both parts inherit the assistant turn's [AiMessage.createdAt].
List<AiMessage> anchorMailboxAfterWaitForMessage(List<AiMessage> messages) {
  if (messages.length < 2) return messages;
  final out = <AiMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final waitIndex = message.role == AiRole.assistant
        ? lastWaitForMessageIndex(message.parts)
        : -1;
    if (waitIndex < 0 || waitIndex == message.parts.length - 1) {
      out.add(message);
      continue;
    }

    var j = i + 1;
    final followingMailbox = <AiMessage>[];
    while (j < messages.length && _isMailboxUser(messages[j])) {
      followingMailbox.add(messages[j]);
      j++;
    }
    if (followingMailbox.isEmpty) {
      out.add(message);
      continue;
    }

    final waitPart = message.parts[waitIndex] as AiToolCallPart;
    out.add(message.copyWith(parts: message.parts.sublist(0, waitIndex + 1)));
    out.addAll(followingMailbox);
    out.add(
      message.copyWith(
        id: waitAnchorTailId(message.id, waitPart.toolCallId),
        parts: message.parts.sublist(waitIndex + 1),
      ),
    );
    i = j - 1;
  }
  return out;
}
