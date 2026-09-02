import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'message_role_scope.dart';
import 'part_grouping.dart';
import 'part_registry.dart';
import 'parts/chain_of_thought_view.dart';
import 'theme.dart';
import 'tool_call_fold_scope.dart';

/// Dispatches grouped parts through [AiPartRegistry].
class AiMessageParts extends StatelessWidget {
  const AiMessageParts({
    required this.parts,
    this.registry = AiPartRegistry.defaults,
    this.chainOfThoughtAutoExpand = false,
    super.key,
  });

  final List<AiMessagePart> parts;
  final AiPartRegistry registry;

  /// Auto-expand the chain-of-thought while it is the tip thinking message
  /// (see [AiChainOfThoughtView.autoExpand]).
  final bool chainOfThoughtAutoExpand;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final gap = AiMessageTheme.of(context).partSpacing;
    final shouldFold = AiToolCallFoldScope.maybeOf(context)?.shouldFold;
    final nodes = groupMessageParts(parts, shouldFold: shouldFold);
    // User bubbles size to content (capped upstream). Assistant tool cards need
    // the full thread width.
    final crossAxisAlignment = AiMessageRoleScope.of(context) == AiRole.user
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.stretch;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < nodes.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          _buildNode(context, nodes[i]),
        ],
      ],
    );
  }

  Widget _buildNode(BuildContext context, AiRenderNode node) {
    if (node is AiRenderChainOfThought &&
        registry.chainOfThoughtBuilder == null) {
      return AiChainOfThoughtView(
        parts: node.parts,
        autoExpand: chainOfThoughtAutoExpand,
      );
    }
    return registry.buildNode(context, node);
  }
}
