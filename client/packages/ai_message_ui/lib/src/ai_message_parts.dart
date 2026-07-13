import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'parts/reasoning_part_view.dart';
import 'parts/text_part_view.dart';
import 'parts/tool_call_part_view.dart';

/// Dispatches [AiMessagePart]s to default or override builders.
class AiMessageParts extends StatelessWidget {
  const AiMessageParts({
    required this.parts,
    this.partBuilders,
    super.key,
  });

  final List<AiMessagePart> parts;
  final Map<Type, Widget Function(BuildContext context, AiMessagePart part)>?
      partBuilders;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildPart(context, parts[i]),
        ],
      ],
    );
  }

  Widget _buildPart(BuildContext context, AiMessagePart part) {
    final override = partBuilders?[part.runtimeType];
    if (override != null) return override(context, part);

    return switch (part) {
      AiTextPart(:final text) => AiTextPartView(text: text),
      AiToolCallPart() => AiToolCallPartView(part: part),
      AiReasoningPart(:final text) => AiReasoningPartView(text: text),
    };
  }
}
