import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/cli/tasks/cli_task_board.dart';

/// Registry of task-tool custom bubbles, keyed by lowercase tool name.
Map<String, AiToolCallBubbleBuilder> cliTaskBubbleBuilders() => {
  'taskcreate': (context, part) => CliTaskCreateBubble(part: part),
  'taskupdate': (context, part) => CliTaskUpdateBubble(part: part),
};

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}

String _statusLabel(BuildContext context, CliTaskStatus status) =>
    switch (status) {
      CliTaskStatus.pending => context.l10n.cliTaskStatusPending,
      CliTaskStatus.inProgress => context.l10n.cliTaskStatusInProgress,
      CliTaskStatus.completed => context.l10n.cliTaskStatusCompleted,
      CliTaskStatus.cancelled => context.l10n.cliTaskStatusCancelled,
      CliTaskStatus.unknown => context.l10n.cliTaskStatusUnknown,
    };

Color _statusColor(ColorScheme scheme, CliTaskStatus status) => switch (status) {
  CliTaskStatus.pending => scheme.onSurfaceVariant,
  CliTaskStatus.inProgress => scheme.primary,
  CliTaskStatus.completed => scheme.tertiary,
  CliTaskStatus.cancelled => scheme.error,
  CliTaskStatus.unknown => scheme.onSurfaceVariant,
};

/// Dedicated bubble for a TaskCreate tool call.
class CliTaskCreateBubble extends StatefulWidget {
  const CliTaskCreateBubble({required this.part, super.key});

  final AiToolCallPart part;

  @override
  State<CliTaskCreateBubble> createState() => _CliTaskCreateBubbleState();
}

class _CliTaskCreateBubbleState extends State<CliTaskCreateBubble> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final args = widget.part.args ?? const <String, Object?>{};
    final subject = _stringify(args['subject']).trim();
    final description = _stringify(args['description']).trim();
    final activeForm = _stringify(args['activeForm']).trim();

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: _BubbleHeader(
              icon: Icons.add_task_rounded,
              color: triggerColor,
              label: 'TaskCreate',
              emphasized: subject,
              pill: _statusLabel(context, CliTaskStatus.pending),
              pillColor: _statusColor(scheme, CliTaskStatus.pending),
              open: _open,
              onToggle: () => setState(() => _open = !_open),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (description.isNotEmpty)
                    _BubbleField(label: 'description', text: description),
                  if (description.isNotEmpty && activeForm.isNotEmpty)
                    const SizedBox(height: 8),
                  if (activeForm.isNotEmpty)
                    _BubbleField(label: 'activeForm', text: activeForm),
                  if (widget.part.result != null) ...[
                    const SizedBox(height: 8),
                    _BubbleField(
                      label: AiMessageStrings.of(context).result,
                      text: _stringify(widget.part.result),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dedicated bubble for a TaskUpdate tool call.
class CliTaskUpdateBubble extends StatefulWidget {
  const CliTaskUpdateBubble({required this.part, super.key});

  final AiToolCallPart part;

  @override
  State<CliTaskUpdateBubble> createState() => _CliTaskUpdateBubbleState();
}

class _CliTaskUpdateBubbleState extends State<CliTaskUpdateBubble> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final args = widget.part.args ?? const <String, Object?>{};
    final taskId = _stringify(args['taskId']).trim();
    final status = cliTaskStatusFromString(_stringify(args['status']));
    final label = taskId.isEmpty ? 'TaskUpdate' : 'TaskUpdate · T$taskId';

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: _BubbleHeader(
              icon: Icons.sync_alt_rounded,
              color: triggerColor,
              label: label,
              emphasized: '',
              pill: _statusLabel(context, status),
              pillColor: _statusColor(scheme, status),
              open: _open,
              onToggle: () => setState(() => _open = !_open),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BubbleField(label: 'args', text: _stringify(widget.part.args)),
                  if (widget.part.result != null) ...[
                    const SizedBox(height: 8),
                    _BubbleField(
                      label: AiMessageStrings.of(context).result,
                      text: _stringify(widget.part.result),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleHeader extends StatelessWidget {
  const _BubbleHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.emphasized,
    required this.pill,
    required this.pillColor,
    required this.open,
    required this.onToggle,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String emphasized;
  final String pill;
  final Color pillColor;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final markdown = AiMessageTheme.of(context).markdown;
    final triggerStyle = markdown.toolTrigger(color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: triggerStyle,
                    children: [
                      TextSpan(
                        text: label,
                        style: markdown.toolNameEmphasis(triggerStyle),
                      ),
                      if (emphasized.isNotEmpty) ...[
                        const TextSpan(text: ' '),
                        TextSpan(text: emphasized),
                      ],
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _Pill(label: pill, color: pillColor),
              const SizedBox(width: 2),
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.4, color: color),
      ),
    );
  }
}

class _BubbleField extends StatelessWidget {
  const _BubbleField({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: aiTheme.markdown.toolTrigger(scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: aiTheme.resolveToolPanel(scheme),
            borderRadius: BorderRadius.circular(aiTheme.panelRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              text,
              softWrap: true,
              style: aiTheme.markdown.codeBlock.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
