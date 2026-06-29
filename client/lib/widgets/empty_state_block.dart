import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../theme/app_text_styles.dart';

enum EmptyStateActionStyle {
  text,
  outlinedIcon,
}

/// Flat gray-icon empty state shared across skills, plugins, MCP, extensions, etc.
class EmptyStateBlock extends StatelessWidget {
  const EmptyStateBlock({
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionStyle = EmptyStateActionStyle.text,
    this.centered = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final EmptyStateActionStyle actionStyle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final textBase = Theme.of(context).colorScheme.onSurface;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: context.appIconSizes.md,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTextStyles.of(
              context,
            ).bodyStrong.copyWith(color: textBase),
          ),
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppTextStyles.of(context).bodySmall.copyWith(
                color: textBase.withValues(alpha: 0.55),
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            SizedBox(
              height: actionStyle == EmptyStateActionStyle.outlinedIcon ? 14 : 10,
            ),
            switch (actionStyle) {
              EmptyStateActionStyle.text => TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
              EmptyStateActionStyle.outlinedIcon => OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(
                  actionIcon ?? Icons.arrow_forward,
                  size: context.appIconSizes.md,
                ),
                label: Text(actionLabel!),
              ),
            },
          ],
        ],
      ),
    );

    if (centered) {
      return Center(child: content);
    }
    return content;
  }
}
