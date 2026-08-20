import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../theme.dart';

Color aiTaskStatusColor(ColorScheme scheme, AiTaskStatus status) =>
    switch (status) {
      AiTaskStatus.pending => scheme.onSurfaceVariant,
      AiTaskStatus.inProgress => scheme.primary,
      AiTaskStatus.completed => scheme.tertiary,
      AiTaskStatus.cancelled => scheme.error,
      AiTaskStatus.unknown => scheme.onSurfaceVariant,
    };

/// Shared collapsible header used by task / todo / ask-user history cards.
class AiToolChromeHeader extends StatelessWidget {
  const AiToolChromeHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.open,
    required this.onToggle,
    this.emphasized = '',
    this.pill,
    this.pillColor,
    this.headerKey,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String emphasized;
  final String? pill;
  final Color? pillColor;
  final bool open;
  final VoidCallback onToggle;
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    final markdown = AiMessageTheme.of(context).markdown;
    final triggerStyle = markdown.toolTrigger(color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: headerKey,
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
              if (pill != null && pillColor != null) ...[
                const SizedBox(width: 6),
                _Pill(label: pill!, color: pillColor!),
              ],
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

class AiToolChromeField extends StatelessWidget {
  const AiToolChromeField({required this.label, required this.text, super.key});

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
