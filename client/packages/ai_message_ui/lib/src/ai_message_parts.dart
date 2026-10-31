import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'message_role_scope.dart';
import 'part_grouping.dart';
import 'part_registry.dart';
import 'parts/chain_of_thought_view.dart';
import 'theme.dart';
import 'tool_call_fold_scope.dart';

/// Dispatches grouped parts through [AiPartRegistry].
///
/// Built nodes are cached per content, so a streaming tip that grows one part
/// only rebuilds that part: the rest of a long turn (hundreds of tool cards)
/// keeps its elements and layout. Without the cache every ACP chunk re-built
/// the whole message, which stalls the UI thread while the agent streams.
class AiMessageParts extends StatefulWidget {
  const AiMessageParts({
    required this.parts,
    this.registry = AiPartRegistry.defaults,
    this.chainOfThoughtAutoExpand = false,
    super.key,
  });

  final List<AiMessagePart> parts;
  final AiPartRegistry registry;

  /// Auto-expand the *last* chain-of-thought of this message while it is the
  /// live thinking tail (see [AiChainOfThoughtView.autoExpand]). Every other
  /// chain-of-thought stays collapsed.
  final bool chainOfThoughtAutoExpand;

  @override
  State<AiMessageParts> createState() => _AiMessagePartsState();
}

class _AiMessagePartsState extends State<AiMessageParts> {
  final Map<_NodeKey, Widget> _nodeWidgets = {};

  @override
  void didUpdateWidget(covariant AiMessageParts oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different registry may render the same node differently.
    if (!identical(oldWidget.registry, widget.registry)) {
      _nodeWidgets.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parts.isEmpty) {
      _nodeWidgets.clear();
      return const SizedBox.shrink();
    }
    final gap = AiMessageTheme.of(context).partSpacing;
    final shouldFold = AiToolCallFoldScope.maybeOf(context)?.shouldFold;
    final nodes = groupMessageParts(widget.parts, shouldFold: shouldFold);
    final lastChainIndex = _lastChainOfThoughtIndex(nodes);
    // User bubbles size to content (capped upstream). Assistant tool cards need
    // the full thread width.
    final crossAxisAlignment = AiMessageRoleScope.of(context) == AiRole.user
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.stretch;
    final children = <Widget>[];
    final liveKeys = <_NodeKey>{};
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) children.add(SizedBox(height: gap));
      final node = nodes[i];
      final autoExpand = i == lastChainIndex;
      final key = _NodeKey(node, autoExpand: autoExpand);
      liveKeys.add(key);
      var child = _nodeWidgets[key];
      if (child == null) {
        child = _buildNode(context, node, autoExpand: autoExpand);
        _nodeWidgets[key] = child;
      }
      children.add(child);
    }
    // Keep only the nodes still in the message (a turn can hold hundreds).
    _nodeWidgets.removeWhere((key, _) => !liveKeys.contains(key));
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Index of the last chain-of-thought node, or -1 when auto-expand is off.
  int _lastChainOfThoughtIndex(List<AiRenderNode> nodes) {
    if (!widget.chainOfThoughtAutoExpand) return -1;
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (nodes[i] is AiRenderChainOfThought) return i;
    }
    return -1;
  }

  Widget _buildNode(
    BuildContext context,
    AiRenderNode node, {
    required bool autoExpand,
  }) {
    if (node is AiRenderChainOfThought &&
        widget.registry.chainOfThoughtBuilder == null) {
      return AiChainOfThoughtView(parts: node.parts, autoExpand: autoExpand);
    }
    return widget.registry.buildNode(context, node);
  }
}

/// Cache key for one rendered node: its parts (by instance — parts are
/// immutable value objects) plus the auto-expand mode the chrome depends on.
class _NodeKey {
  _NodeKey(AiRenderNode node, {required this.autoExpand})
    : parts = switch (node) {
        AiRenderPart(:final part) => <AiMessagePart>[part],
        AiRenderChainOfThought(:final parts) => parts,
        AiRenderToolGroup(:final tools) => tools,
        AiRenderReasoningGroup(:final parts) => parts,
      };

  final List<AiMessagePart> parts;
  final bool autoExpand;

  @override
  bool operator ==(Object other) {
    if (other is! _NodeKey ||
        other.autoExpand != autoExpand ||
        other.parts.length != parts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      if (!identical(other.parts[i], parts[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    autoExpand,
    parts.length,
    parts.isEmpty ? null : identityHashCode(parts.first),
    parts.isEmpty ? null : identityHashCode(parts.last),
  );
}
