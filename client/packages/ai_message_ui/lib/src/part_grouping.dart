import 'package:ai_message_core/ai_message_core.dart';

/// Render tree nodes after consecutive-part grouping (assistant-ui GroupedParts).
sealed class AiRenderNode {
  const AiRenderNode();
}

final class AiRenderPart extends AiRenderNode {
  const AiRenderPart(this.part);

  final AiMessagePart part;
}

final class AiRenderToolGroup extends AiRenderNode {
  const AiRenderToolGroup(this.tools);

  final List<AiToolCallPart> tools;
}

final class AiRenderReasoningGroup extends AiRenderNode {
  const AiRenderReasoningGroup(this.parts);

  final List<AiReasoningPart> parts;
}

/// Groups consecutive tool-call / reasoning parts the way assistant-ui does.
List<AiRenderNode> groupMessageParts(List<AiMessagePart> parts) {
  final out = <AiRenderNode>[];
  var i = 0;
  while (i < parts.length) {
    final part = parts[i];
    if (part is AiToolCallPart) {
      final tools = <AiToolCallPart>[];
      while (i < parts.length && parts[i] is AiToolCallPart) {
        tools.add(parts[i] as AiToolCallPart);
        i++;
      }
      if (tools.length == 1) {
        out.add(AiRenderPart(tools.single));
      } else {
        out.add(AiRenderToolGroup(tools));
      }
      continue;
    }
    if (part is AiReasoningPart) {
      final group = <AiReasoningPart>[];
      while (i < parts.length && parts[i] is AiReasoningPart) {
        group.add(parts[i] as AiReasoningPart);
        i++;
      }
      out.add(
        group.length == 1
            ? AiRenderPart(group.single)
            : AiRenderReasoningGroup(group),
      );
      continue;
    }
    out.add(AiRenderPart(part));
    i++;
  }
  return out;
}
