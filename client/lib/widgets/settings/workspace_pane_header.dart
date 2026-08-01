import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

class WorkspacePaneHeader extends StatelessWidget {
  const WorkspacePaneHeader({
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final trimmed = subtitle?.trim();
    final showSub =
        showSubtitle && trimmed != null && trimmed.isNotEmpty;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.xl,
        ),
        if (showSub) ...[
          const SizedBox(height: 8),
          Text(
            trimmed,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: styles.mdColored(cs.onSurface.withValues(alpha: 0.66)),
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
      ],
    );

    final back = onBack;
    if (back == null) return titleBlock;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: back,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        const SizedBox(width: 8),
        Expanded(child: titleBlock),
      ],
    );
  }
}
