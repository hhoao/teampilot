import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

import 'parts/reasoning_part_view.dart';
import 'parts/text_part_view.dart';
import 'parts/tool_call_part_view.dart';
import 'parts/tool_group_view.dart';
import 'part_grouping.dart';

typedef AiPartBuilder = Widget Function(
  BuildContext context,
  AiMessagePart part,
);

typedef AiToolGroupBuilder = Widget Function(
  BuildContext context,
  List<AiToolCallPart> tools,
);

typedef AiReasoningGroupBuilder = Widget Function(
  BuildContext context,
  List<AiReasoningPart> parts,
);

/// Extensible part → widget map (assistant-ui ThreadComponents pattern).
///
/// Hosts override specific part types or group renderers without forking
/// [AiMessageView].
@immutable
class AiPartRegistry {
  const AiPartRegistry({
    this.builders = const {},
    this.toolGroupBuilder,
    this.reasoningGroupBuilder,
  });

  final Map<Type, AiPartBuilder> builders;
  final AiToolGroupBuilder? toolGroupBuilder;
  final AiReasoningGroupBuilder? reasoningGroupBuilder;

  static const AiPartRegistry defaults = AiPartRegistry();

  AiPartRegistry merge(AiPartRegistry? other) {
    if (other == null) return this;
    return AiPartRegistry(
      builders: {...builders, ...other.builders},
      toolGroupBuilder: other.toolGroupBuilder ?? toolGroupBuilder,
      reasoningGroupBuilder:
          other.reasoningGroupBuilder ?? reasoningGroupBuilder,
    );
  }

  Widget buildPart(BuildContext context, AiMessagePart part) {
    final override = builders[part.runtimeType];
    if (override != null) return override(context, part);
    return switch (part) {
      AiTextPart(:final text) => AiTextPartView(text: text),
      AiToolCallPart() => AiToolCallPartView(part: part),
      AiReasoningPart() => AiReasoningPartView(part: part),
    };
  }

  Widget buildNode(BuildContext context, AiRenderNode node) {
    return switch (node) {
      AiRenderPart(:final part) => buildPart(context, part),
      AiRenderToolGroup(:final tools) =>
        (toolGroupBuilder ?? _defaultToolGroup)(context, tools),
      AiRenderReasoningGroup(:final parts) =>
        (reasoningGroupBuilder ?? _defaultReasoningGroup)(context, parts),
      AiRenderChainOfThought() => throw UnimplementedError(
        'Cot render in Task 4',
      ),
    };
  }
}

Widget _defaultToolGroup(BuildContext context, List<AiToolCallPart> tools) {
  return AiToolGroupView(tools: tools);
}

Widget _defaultReasoningGroup(
  BuildContext context,
  List<AiReasoningPart> parts,
) {
  return AiReasoningPartView(
    part: AiReasoningPart(
      text: parts.map((p) => p.text.trim()).where((t) => t.isNotEmpty).join('\n\n'),
    ),
  );
}
