import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import 'package:tp_markdown/tp_markdown.dart';
import '../parts/expandable_tool_card.dart';
import '../parts/fade_expand_body.dart';
import '../theme.dart';

/// Cursor-style shell tool card: header + always-visible mini/full terminal panel.
class ShellToolCard extends StatelessWidget {
  const ShellToolCard({
    required this.part,
    required this.shell,
    required this.triggerColor,
    required this.markdown,
    required this.dense,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final AiToolCallPart part;
  final AiShellToolTarget shell;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final panelColor = aiTheme.resolveToolPanel(scheme);
    final triggerStyle = markdown.toolTrigger(
      triggerColor,
      cancelled: part.isCancelled,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ShellStatusIcon(part: part, color: triggerColor),
                const SizedBox(width: 8),
                Icon(Icons.terminal, size: 15, color: triggerColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    shell.summary,
                    style: triggerStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                _ShellExpandChevron(open: open, color: triggerColor),
              ],
            ),
          ),
        ),
        if (!open)
          SelectionContainer.disabled(
            child: _ShellTerminalBody(
              part: part,
              command: shell.command,
              panelColor: panelColor,
              radius: aiTheme.panelRadius,
              markdown: markdown,
              accentColor: triggerColor,
              open: false,
              onToggle: onToggle,
            ),
          )
        else
          _ShellTerminalBody(
            part: part,
            command: shell.command,
            panelColor: panelColor,
            radius: aiTheme.panelRadius,
            markdown: markdown,
            accentColor: triggerColor,
            open: true,
            onToggle: onToggle,
          ),
      ],
    );
  }
}

/// Stateful host wrapping [ShellToolCard] in whole-card expand tap target.
class ShellToolCardHost extends StatelessWidget {
  const ShellToolCardHost({
    required this.part,
    required this.shell,
    required this.triggerColor,
    required this.markdown,
    required this.dense,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final AiToolCallPart part;
  final AiShellToolTarget shell;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AiExpandableToolCard(
      open: open,
      onToggle: onToggle,
      child: ShellToolCard(
        part: part,
        shell: shell,
        triggerColor: triggerColor,
        markdown: markdown,
        dense: dense,
        open: open,
        onToggle: onToggle,
      ),
    );
  }
}

class _ShellTerminalBody extends StatelessWidget {
  const _ShellTerminalBody({
    required this.part,
    required this.command,
    required this.panelColor,
    required this.radius,
    required this.markdown,
    required this.accentColor,
    required this.open,
    required this.onToggle,
  });

  final AiToolCallPart part;
  final String command;
  final Color panelColor;
  final double radius;
  final MarkdownTokens markdown;
  final Color accentColor;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = markdown.codeBlock;
    // Cap the strings, not just the visual clip: AiFadeExpandBody lays the
    // child out at full height even while collapsed, so a giant command
    // output would otherwise freeze the frame on every message mount.
    final cappedCommand = capToolPanelText(command);
    final rawOutput = part.result == null ? null : _stringify(part.result);
    final hasOutput = rawOutput != null && rawOutput.trim().isNotEmpty;
    final huge =
        hasOutput && rawOutput.length > kAiShellCollapsedPreviewMinChars;
    final output = !hasOutput
        ? null
        : (open || !huge)
        ? capToolPanelText(rawOutput)
        : previewToolCardText(rawOutput);
    final outputColor = part.isError
        ? scheme.error
        : scheme.onSurface.withValues(alpha: 0.65);

    final body = AiFadeExpandBody(
      open: open,
      onToggle: onToggle,
      fadeColor: panelColor,
      forceChrome: !open && huge,
      contentPadding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: r'$ ',
                  style: mono.copyWith(color: accentColor),
                ),
                TextSpan(
                  text: cappedCommand,
                  style: mono.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (output != null) ...[
            const SizedBox(height: 8),
            Text(output, style: mono.copyWith(color: outputColor)),
          ],
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(color: panelColor, child: body),
    );
  }
}

class _ShellExpandChevron extends StatelessWidget {
  const _ShellExpandChevron({required this.open, required this.color});

  final bool open;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Transform.rotate(
        angle: open ? 0 : -math.pi / 2,
        child: Icon(Icons.expand_more, size: 16, color: color),
      ),
    );
  }
}

class _ShellStatusIcon extends StatelessWidget {
  const _ShellStatusIcon({required this.part, required this.color});

  final AiToolCallPart part;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (part.isError) {
      return Icon(Icons.error_outline, size: 16, color: scheme.error);
    }
    return switch (part.status) {
      AiToolCallStatus.running => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      AiToolCallStatus.complete => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      AiToolCallStatus.incomplete => Icon(
        Icons.highlight_off,
        size: 16,
        color: color,
      ),
      AiToolCallStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: color,
      ),
    };
  }
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
