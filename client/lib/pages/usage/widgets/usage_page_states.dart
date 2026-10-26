import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/ui/app_keys.dart';

class UsageEmptyState extends StatelessWidget {
  const UsageEmptyState({
    required this.onSync,
    required this.onReset,
    super.key,
  });

  final Future<void> Function() onSync;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          key: AppKeys.sessionUsageEmptyState,
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 22),
          decoration: workspaceCardDecoration(
            cs,
            radius: 14,
          ).copyWith(color: cs.workspaceCard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TpEmptyState(
                icon: Icons.insights_outlined,
                title: l10n.sessionUsageEmptyTitle,
                hint: l10n.sessionUsageEmptyBody,
                actionLabel: l10n.sessionUsageSync,
                onAction: onSync,
                centered: true,
              ),
              TextButton(
                onPressed: onReset,
                child: Text(l10n.sessionUsageResetFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UsageLoadError extends StatelessWidget {
  const UsageLoadError({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: workspaceCardDecoration(
          cs,
          radius: 14,
        ).copyWith(color: cs.workspaceCard),
        child: TpEmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.sessionUsageLoadFailed,
          actionLabel: l10n.sessionUsageRetry,
          onAction: onRetry,
          centered: true,
        ),
      ),
    );
  }
}

class UsageSyncErrorBanner extends StatelessWidget {
  const UsageSyncErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Container(
      key: AppKeys.sessionUsageErrorBanner,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: styles.sm.copyWith(color: cs.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.sessionUsageRetry)),
          IconButton(
            tooltip: l10n.sessionUsageDismiss,
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
