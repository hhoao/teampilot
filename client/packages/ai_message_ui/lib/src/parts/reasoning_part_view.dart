import 'package:flutter/material.dart';

/// Collapsed-by-default reasoning / thinking text.
class AiReasoningPartView extends StatelessWidget {
  const AiReasoningPartView({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          leading: Icon(
            Icons.psychology_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(
            'Reasoning',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
