import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'part_grouping.dart';
import 'part_registry.dart';
import 'theme.dart';

/// Dispatches grouped parts through [AiPartRegistry].
class AiMessageParts extends StatelessWidget {
  const AiMessageParts({
    required this.parts,
    this.registry = AiPartRegistry.defaults,
    super.key,
  });

  final List<AiMessagePart> parts;
  final AiPartRegistry registry;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final gap = AiMessageTheme.of(context).partSpacing;
    final nodes = groupMessageParts(parts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < nodes.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          registry.buildNode(context, nodes[i]),
        ],
      ],
    );
  }
}
