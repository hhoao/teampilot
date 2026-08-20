import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import 'tool_chrome_header.dart';

/// History chrome for TaskCreate / TaskUpdate / TodoWrite.
class AiTaskToolCard extends StatelessWidget {
  const AiTaskToolCard({required this.target, super.key});

  final AiTaskToolTarget target;

  @override
  Widget build(BuildContext context) {
    return switch (target) {
      AiTodoListTarget(:final toolLabel, :final items) => _TodoListCard(
        toolLabel: toolLabel,
        items: items,
      ),
      AiTaskCreateTarget create => _TaskCreateCard(target: create),
      AiTaskUpdateTarget update => _TaskUpdateCard(target: update),
    };
  }
}

class _TodoListCard extends StatefulWidget {
  const _TodoListCard({required this.toolLabel, required this.items});

  final String toolLabel;
  final List<AiTodoItem> items;

  @override
  State<_TodoListCard> createState() => _TodoListCardState();
}

class _TodoListCardState extends State<_TodoListCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final completed = widget.items
        .where((t) => t.status == AiTaskStatus.completed)
        .length;
    final pill = widget.items.isEmpty
        ? '0'
        : '$completed/${widget.items.length}';

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: AiToolChromeHeader(
              icon: Icons.fact_check_outlined,
              color: triggerColor,
              label: widget.toolLabel,
              pill: pill,
              pillColor: scheme.onSurfaceVariant,
              open: _open,
              onToggle: () => setState(() => _open = !_open),
            ),
          ),
          if (_open && widget.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 6, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _TodoStatusIcon(
                          status: widget.items[i].status,
                          color: aiTaskStatusColor(
                            scheme,
                            widget.items[i].status,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.items[i].content.isEmpty
                                ? '…'
                                : widget.items[i].content,
                            style: aiTheme.markdown.toolTrigger(
                              scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
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

class _TaskCreateCard extends StatefulWidget {
  const _TaskCreateCard({required this.target});

  final AiTaskCreateTarget target;

  @override
  State<_TaskCreateCard> createState() => _TaskCreateCardState();
}

class _TaskCreateCardState extends State<_TaskCreateCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final strings = AiMessageStrings.of(context);
    final target = widget.target;
    final description = target.description.trim();
    final activeForm = target.activeForm.trim();
    final resultText = target.resultText?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: AiToolChromeHeader(
              icon: Icons.add_task_rounded,
              color: triggerColor,
              label: target.toolLabel,
              emphasized: target.subject,
              pill: strings.taskStatusPending,
              pillColor: aiTaskStatusColor(scheme, AiTaskStatus.pending),
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
                    AiToolChromeField(label: 'description', text: description),
                  if (description.isNotEmpty && activeForm.isNotEmpty)
                    const SizedBox(height: 8),
                  if (activeForm.isNotEmpty)
                    AiToolChromeField(label: 'activeForm', text: activeForm),
                  if (resultText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AiToolChromeField(label: strings.result, text: resultText),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskUpdateCard extends StatefulWidget {
  const _TaskUpdateCard({required this.target});

  final AiTaskUpdateTarget target;

  @override
  State<_TaskUpdateCard> createState() => _TaskUpdateCardState();
}

class _TaskUpdateCardState extends State<_TaskUpdateCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final strings = AiMessageStrings.of(context);
    final target = widget.target;
    final label = target.taskId.isEmpty
        ? target.toolLabel
        : '${target.toolLabel} · T${target.taskId}';
    final resultText = target.resultText?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: AiToolChromeHeader(
              icon: Icons.sync_alt_rounded,
              color: triggerColor,
              label: label,
              pill: strings.taskStatusLabel(target.status),
              pillColor: aiTaskStatusColor(scheme, target.status),
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
                  AiToolChromeField(label: 'args', text: target.argsText),
                  if (resultText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AiToolChromeField(label: strings.result, text: resultText),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodoStatusIcon extends StatelessWidget {
  const _TodoStatusIcon({required this.status, required this.color});

  final AiTaskStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const box = 16.0;
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: Icon(
          switch (status) {
            AiTaskStatus.pending => Icons.radio_button_unchecked,
            AiTaskStatus.inProgress => Icons.arrow_forward,
            AiTaskStatus.completed => Icons.check_circle_outline,
            AiTaskStatus.cancelled => Icons.cancel_outlined,
            AiTaskStatus.unknown => Icons.help_outline,
          },
          size: 14,
          color: color,
        ),
      ),
    );
  }
}
