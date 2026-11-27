import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import '../thinking_process_summary.dart';
import '../tool_file_actions.dart';
import 'activity_outline.dart';
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

  /// Counts `build` calls. Assert-guarded so release builds pay nothing, and
  /// read by the `[perf]` line in `ai_message_parts.dart`.
  static int debugBuildCount = 0;

  /// Why the last chrome rebuild could not reuse the cached subtree, counted
  /// per reason. Printed by the `[perf]` line so one debug run identifies the
  /// input that keeps changing.
  static final Map<String, int> debugMissReasons = {};

  static void _noteMiss(String reason) {
    assert(() {
      debugMissReasons[reason] = (debugMissReasons[reason] ?? 0) + 1;
      return true;
    }());
  }

  /// Counts `initState` calls: a mount means the element tree was recreated,
  /// so the memo and every node cache behind it start empty.
  static int debugMounts = 0;

  /// Counts actual chrome rebuilds (cache misses). Compare with
  /// [debugBuildCount]: a large gap means the memo absorbed the rebuild.
  static int debugBodyBuilds = 0;

  /// Counts `didChangeDependencies` calls (an inherited scope notified us).
  /// Compare with [debugBuildCount]: equal growth means the rebuild came from a
  /// notification, not from the parent handing in a different part.
  /// Assert-guarded; read alongside [debugBuildCount] in a debug run.
  static int debugDirtyCount = 0;

  @override
  State<AiChainOfThoughtView> createState() => _AiChainOfThoughtViewState();
}

class _AiChainOfThoughtViewState extends State<AiChainOfThoughtView> {
  late bool _open = widget.autoExpand;

  @override
  void initState() {
    super.initState();
    assert(() {
      AiChainOfThoughtView.debugMounts++;
      return true;
    }());
  }

  /// Cached chrome for unchanged inputs.
  ///
  /// A collapsed chain is a header row plus a summary string, but building it
  /// walks every part through `summarizeThinkingProcess`. When an inherited
  /// scope above the transcript notifies, every chain rebuilds for nothing;
  /// returning the previous subtree makes that a cheap identity check and lets
  /// `updateChild` short-circuit the five chrome widgets underneath.
  Widget? _body;
  List<String>? _bodyDigests;
  bool? _bodyAutoExpand;
  bool? _bodyOpen;
  Object? _bodyStrings;
  Object? _bodyActions;
  ColorScheme? _bodyScheme;
  TextStyle? _bodyTriggerStyle;
  Color? _bodyRailColor;
  double? _bodySpacing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    assert(() {
      AiChainOfThoughtView.debugDirtyCount++;
      return true;
    }());
  }

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
    assert(() {
      AiChainOfThoughtView.debugBuildCount++;
      return true;
    }());
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final actions = AiToolFileActions.of(context);
    final triggerStyle = markdown.toolTrigger(triggerColor);
    final railColor = aiTheme.resolveReasoningBorder(scheme);

    // Memo contract: every input the chrome paints with is compared below.
    // Adding a visual input (a new theme field, a string, a resolved style)
    // without adding it to this check silently renders stale chrome.
    final digests = [
      for (final part in widget.parts) messagePartIdentity(part),
    ];
    final cachedBody = _body;
    if (cachedBody != null &&
        _bodyOpen == _open &&
        _bodyAutoExpand == widget.autoExpand &&
        identical(_bodyStrings, strings) &&
        identical(_bodyActions, actions) &&
        _bodyScheme == scheme &&
        _bodyTriggerStyle == triggerStyle &&
        _bodyRailColor == railColor &&
        _bodySpacing == aiTheme.partSpacing &&
        _sameDigests(_bodyDigests!, digests)) {
      return cachedBody;
    }
    assert(() {
      AiChainOfThoughtView.debugBodyBuilds++;
      return true;
    }());
    if (cachedBody != null) {
      if (_bodyOpen != _open) {
        AiChainOfThoughtView._noteMiss('open');
      } else if (_bodyAutoExpand != widget.autoExpand) {
        AiChainOfThoughtView._noteMiss('autoExpand');
      } else if (!identical(_bodyStrings, strings)) {
        AiChainOfThoughtView._noteMiss('strings');
      } else if (!identical(_bodyActions, actions)) {
        AiChainOfThoughtView._noteMiss('actions');
      } else if (_bodyScheme != scheme) {
        AiChainOfThoughtView._noteMiss('scheme');
      } else if (_bodyTriggerStyle != triggerStyle) {
        AiChainOfThoughtView._noteMiss('style');
      } else if (_bodyRailColor != railColor) {
        AiChainOfThoughtView._noteMiss('railColor');
      } else if (_bodySpacing != aiTheme.partSpacing) {
        AiChainOfThoughtView._noteMiss('spacing');
      } else {
        AiChainOfThoughtView._noteMiss('digests');
      }
    }

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
    final stats = strings.formatThinkingProcessStats;
    // Counts are scoped to THIS chain, not the whole message: the header
    // describes the fold it belongs to. When tools are not folded into the
    // chain this stays 0 and the steps phrase is used unchanged.
    final chainToolCalls = widget.parts.whereType<AiToolCallPart>().length;
    final fallbackPhrase = stats != null && chainToolCalls > 0
        ? stats(widget.parts.length, chainToolCalls)
        : strings.formatThinkingProcessSteps(widget.parts.length);
    final detail = formatted.isNotEmpty
        ? formatted
        : _withoutThinkingPrefix(fallbackPhrase, strings.thinkingProcess);
    final phrase = '${strings.thinkingProcess} > $detail';
    final showDiff =
        formatted.isNotEmpty && (summary.added > 0 || summary.removed > 0);
    final semanticsLabel = [
      phrase,
      if (showDiff && summary.added > 0) '+${summary.added}',
      if (showDiff && summary.removed > 0) '-${summary.removed}',
    ].join(' ');

    final header = SelectionContainer.disabled(
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
                children: [
                  AiActivityChevron(open: _open),
                  const SizedBox(width: 8),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final body = Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: AiActivityOutline(
        header: header,
        followLatest: widget.autoExpand,
        children: [
          if (_open)
            for (var i = 0; i < widget.parts.length; i++)
              _buildInnerPart(widget.parts[i], i, activeReasoningIndex),
        ],
      ),
    );
    _body = body;
    _bodyDigests = digests;
    _bodyAutoExpand = widget.autoExpand;
    _bodyOpen = _open;
    _bodyStrings = strings;
    _bodyActions = actions;
    _bodyScheme = scheme;
    _bodyTriggerStyle = triggerStyle;
    _bodyRailColor = railColor;
    _bodySpacing = aiTheme.partSpacing;
    return body;
  }

  static String _withoutThinkingPrefix(String label, String thinkingProcess) {
    const separator = ' · ';
    final prefix = '$thinkingProcess$separator';
    return label.startsWith(prefix) ? label.substring(prefix.length) : label;
  }

  static bool _sameDigests(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
