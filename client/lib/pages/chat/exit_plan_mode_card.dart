import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Chat card for Claude `ExitPlanMode`: shows the submitted plan and jumps to
/// the Terminal for the approval prompt.
class ExitPlanModeCard extends StatelessWidget {
  const ExitPlanModeCard({
    required this.planText,
    this.planFilePath,
    required this.onOpenTerminal,
    super.key,
  });

  final String planText;
  final String? planFilePath;
  final VoidCallback onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final path = planFilePath?.trim() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.exitPlanModeCard,
        elevation: 2,
        shadowColor: cs.shadow.withValues(alpha: 0.28),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.md,
            spacing.sm,
            spacing.sm,
            spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.rule_rounded, size: 16, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.agentPermissionAttentionBanner,
                      style: styles.smColored(cs.onSurface),
                    ),
                  ),
                ],
              ),
              if (planText.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: EdgeInsets.all(spacing.sm),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      planText,
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
              if (path.isNotEmpty) ...[
                SizedBox(height: spacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.xsColored(cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TpButton(
                  key: AppKeys.agentPermissionOpenTerminalButton,
                  variant: TpButtonVariant.primary,
                  size: TpControlSize.small,
                  onPressed: onOpenTerminal,
                  child: Text(l10n.agentPermissionOpenTerminal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
