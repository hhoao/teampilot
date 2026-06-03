import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';

/// A single project tile in the workspace home grid: icon, name, and a footer
/// label with the session count. Read-only; hover lifts the border.
class HomeWorkspaceProjectCard extends StatefulWidget {
  const HomeWorkspaceProjectCard({
    required this.project,
    required this.sessionCount,
    this.onTap,
    super.key,
  });

  final AppProject project;
  final int sessionCount;
  final VoidCallback? onTap;

  @override
  State<HomeWorkspaceProjectCard> createState() =>
      _HomeWorkspaceProjectCardState();
}

class _HomeWorkspaceProjectCardState extends State<HomeWorkspaceProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(26),
        decoration: workspaceCardDecoration(
          cs,
          radius: 14,
          borderAlpha: _hovered ? 1 : 0.7,
        ).copyWith(
          color: cs.workspaceInset,
          border: Border.all(
            color: _hovered
                ? cs.primary.withValues(alpha: 0.5)
                : cs.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.85),
                    cs.tertiary.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.auto_stories_rounded,
                size: 34,
                color: cs.onPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.project.effectiveDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.prominent.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${widget.sessionCount} ${l10n.homeWorkspaceSessionsLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
