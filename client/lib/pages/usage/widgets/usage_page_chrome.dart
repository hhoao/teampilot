import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/usage/usage_sync_control.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsagePageHeader extends StatelessWidget {
  const UsagePageHeader({
    required this.state,
    required this.onIncrementalSync,
    required this.onFullSync,
    required this.onCancel,
    required this.onSettings,
    super.key,
  });

  final SessionUsageState state;
  final Future<void> Function() onIncrementalSync;
  final Future<void> Function() onFullSync;
  final VoidCallback onCancel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sessionUsageTitle,
          style: styles.xl.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.sessionUsageScopeHint,
              style: styles.xs.copyWith(
                color: cs.onSurface.withValues(alpha: 0.42),
              ),
            ),
            if (state.isSyncing)
              Text(
                key: AppKeys.sessionUsageSyncProgress,
                _progressLabel(context, state.syncProgress),
                style: styles.xs.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );

    final controls = _controls(context, styles, cs);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [summary, const SizedBox(height: 12), controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            const SizedBox(width: 12),
            controls,
          ],
        );
      },
    );
  }

  /// One capsule: sync status (opens the sync menu) and the settings entry.
  Widget _controls(
    BuildContext context,
    TpTextStyles styles,
    ColorScheme cs,
  ) {
    final borderColor = cs.outlineVariant.withValues(alpha: 0.6);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _syncSegment(context, styles, cs),
          Container(width: 1, height: 20, color: borderColor),
          _segment(
            key: AppKeys.sessionUsageSettingsButton,
            tooltip: context.l10n.sessionUsageSettings,
            onTap: onSettings,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(9),
            ),
            child: Icon(
              Icons.tune,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncSegment(
    BuildContext context,
    TpTextStyles styles,
    ColorScheme cs,
  ) {
    final l10n = context.l10n;
    if (state.isSyncing) {
      return _segment(
        key: AppKeys.sessionUsageCancelSyncButton,
        tooltip: l10n.sessionUsageCancelSyncTooltip,
        onTap: state.isCancelling ? null : onCancel,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: state.isCancelling
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Icon(Icons.close, size: 14, color: cs.onSurface),
            ),
            const SizedBox(width: 6),
            Text(
              state.isCancelling
                  ? l10n.sessionUsageCancelling
                  : l10n.sessionUsageCancelSync,
              style: styles.smMedium.copyWith(color: cs.onSurface),
            ),
          ],
        ),
      );
    }
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        MenuItemButton(
          key: AppKeys.sessionUsageIncrementalSync,
          leadingIcon: const Icon(Icons.sync, size: 18),
          onPressed: () => onIncrementalSync(),
          child: _menuOption(
            context,
            l10n.sessionUsageSyncIncremental,
            l10n.sessionUsageSyncIncrementalHint,
          ),
        ),
        MenuItemButton(
          key: AppKeys.sessionUsageFullSync,
          leadingIcon: const Icon(Icons.restart_alt, size: 18),
          onPressed: () => onFullSync(),
          child: _menuOption(
            context,
            l10n.sessionUsageSyncFull,
            l10n.sessionUsageSyncFullHint,
          ),
        ),
      ],
      builder: (context, controller, child) => _segment(
        key: AppKeys.sessionUsageSyncButton,
        tooltip: l10n.sessionUsageSyncTooltip,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 6),
            Text(
              _syncLabel(context),
              style: styles.smMedium.copyWith(
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment({
    required Key key,
    required Widget child,
    required VoidCallback? onTap,
    required BorderRadius borderRadius,
    String? tooltip,
  }) {
    final segment = InkWell(
      key: key,
      onTap: onTap,
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: child,
      ),
    );
    if (tooltip == null) return segment;
    return Tooltip(message: tooltip, child: segment);
  }

  String _syncLabel(BuildContext context) {
    final l10n = context.l10n;
    final lastSyncAtMs = state.lastSyncAtMs;
    if (lastSyncAtMs == null) return l10n.sessionUsageNeverSynced;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastSyncAtMs;
    if (elapsedMs < const Duration(minutes: 1).inMilliseconds) {
      return l10n.sessionUsageSyncedJustNow;
    }
    return formatUsageLastSync(context, lastSyncAtMs);
  }

  Widget _menuOption(BuildContext context, String title, String hint) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: styles.sm),
          const SizedBox(height: 1),
          Text(
            hint,
            style: styles.xs.copyWith(
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

String _progressLabel(BuildContext context, UsageSyncProgress? progress) {
  final l10n = context.l10n;
  if (progress == null || progress.targetsTotal == 0) {
    return l10n.sessionUsageSyncPreparing;
  }
  return l10n.sessionUsageSyncProgress(
    progress.targetsDone,
    progress.targetsTotal,
    progress.inserted,
  );
}
