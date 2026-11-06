import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import '../thinking_process_summary.dart';
import '../tool_file_actions.dart';
import 'reasoning_part_view.dart';
import 'tool_call_part_view.dart';

/// Default-collapsed chain-of-thought chrome for contiguous reasoning + tools.
class AiChainOfThoughtView extends StatefulWidget {
  const AiChainOfThoughtView({
    required this.parts,
    this.autoExpand = false,
    super.key,
  });

  final List<AiMessagePart> parts;

  /// While true, the chain stays expanded with only its live reasoning tail
  /// open: the last reasoning part (when it is the last part of the chain)
  /// follows the newest line, while already-finished reasoning parts stay
  /// folded to their trigger rows. The host turns this off once the reasoning
  /// tail is finished (answer starts streaming / turn ends), collapsing the
  /// whole chain back to its default collapsed chrome.
  final bool autoExpand;

  @override
  State<AiChainOfThoughtView> createState() => _AiChainOfThoughtViewState();
}

class _AiChainOfThoughtViewState extends State<AiChainOfThoughtView> {
  late bool _open = widget.autoExpand;

  @override
  void didUpdateWidget(covariant AiChainOfThoughtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Entering auto-expand opens the chain; leaving it collapses back to the
    // default chrome. While the mode is unchanged, respect manual toggles.
    if (widget.autoExpand != oldWidget.autoExpand) {
      _open = widget.autoExpand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final actions = AiToolFileActions.of(context);
    // Only the reasoning part currently being streamed stays open. A tool
    // call at the tail means thinking paused, so nothing stays expanded.
    final activeReasoningIndex =
        widget.autoExpand &&
                widget.parts.isNotEmpty &&
                widget.parts.last is AiReasoningPart
            ? widget.parts.length - 1
            : -1;
    final summary = summarizeThinkingProcess(
      widget.parts,
      fileResolver: actions.fileResolver,
      editResolver: actions.editResolver,
    );
    final formatted = summary.hasActivity
        ? strings.formatThinkingProcessSummary(summary)
        : '';
    final phrase = formatted.isNotEmpty
        ? formatted
        : strings.formatThinkingProcessSteps(widget.parts.length);
    final showDiff =
        formatted.isNotEmpty && (summary.added > 0 || summary.removed > 0);
    final semanticsLabel = [
      phrase,
      if (showDiff && summary.added > 0) '+${summary.added}',
      if (showDiff && summary.removed > 0) '-${summary.removed}',
    ].join(' ');
    final triggerStyle = markdown.toolTrigger(triggerColor);

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Semantics(
              button: true,
              expanded: _open,
              label: semanticsLabel,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              style: triggerStyle,
                              children: [
                                TextSpan(text: phrase),
                                if (showDiff && summary.added > 0)
                                  TextSpan(
                                    text: ' +${summary.added}',
                                    style: markdown.toolTrigger(scheme.primary),
                                  ),
                                if (showDiff && summary.removed > 0)
                                  TextSpan(
                                    text: ' -${summary.removed}',
                                    style: markdown.toolTrigger(scheme.error),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: _open ? 0 : -math.pi / 2,
                          child: Icon(
                            Icons.expand_more,
                            size: 16,
                            color: triggerColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.parts.length; i++)
                    _buildInnerPart(widget.parts[i], i, activeReasoningIndex),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInnerPart(
    AiMessagePart part,
    int index,
    int activeReasoningIndex,
  ) {
    final aiTheme = AiMessageTheme.of(context);
    final isActive = index == activeReasoningIndex;
    return switch (part) {
      AiReasoningPart() => AiReasoningPartView(
        part: part,
        initiallyExpanded:
            isActive ||
            (!widget.autoExpand && aiTheme.cotExpandReasoningOnOpen),
        autoFollow: isActive,
      ),
      AiToolCallPart() => AiToolCallPartView(
        part: part,
        initiallyExpanded: aiTheme.cotExpandToolsOnOpen,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
