import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../workspace_status_bar/workspace_status_bar.dart';
import 'managed_provider_usage_panel.dart';

/// Lower-left cached usage summary and its refresh/navigation panel.
class ManagedProviderUsageStatusItem implements WorkspaceStatusBarItem {
  const ManagedProviderUsageStatusItem({this.onManage});

  final VoidCallback? onManage;

  @override
  String get id => 'managed-provider-usage';

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) =>
      _ManagedProviderUsageStatusSegment(compact: compact, onManage: onManage);
}

class _ManagedProviderUsageStatusSegment extends StatefulWidget {
  const _ManagedProviderUsageStatusSegment({
    required this.compact,
    required this.onManage,
  });

  final bool compact;
  final VoidCallback? onManage;

  @override
  State<_ManagedProviderUsageStatusSegment> createState() =>
      _ManagedProviderUsageStatusSegmentState();
}

class _ManagedProviderUsageStatusSegmentState
    extends State<_ManagedProviderUsageStatusSegment> {
  final _popover = TpPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ManagedProviderCubit, ManagedProviderState>(
      buildWhen: (previous, next) =>
          previous.providers != next.providers ||
          previous.status != next.status,
      builder: (context, providerState) {
        return BlocBuilder<
          ManagedProviderUsageCubit,
          ManagedProviderUsageState
        >(
          buildWhen: (previous, next) =>
              previous.snapshots != next.snapshots ||
              previous.status != next.status ||
              previous.isRefreshing != next.isRefreshing,
          builder: (context, usageState) {
            final providers = providerState.enabledProviders;
            final summary = _Summary.from(context, providers, usageState);
            final cs = Theme.of(context).colorScheme;
            return TpActionMenuAnchor(
              controller: _popover,
              fixedPanelWidth: ManagedProviderUsagePanel.panelWidth,
              padding: EdgeInsets.zero,
              closeOnTapOutside: true,
              anchor: const TpAnchor(
                childAlignment: Alignment.bottomLeft,
                overlayAlignment: Alignment.topLeft,
                offset: Offset(0, -8),
              ),
              popoverBuilder: (context, menu) => ManagedProviderUsagePanel(
                onManage: () {
                  menu.close();
                  widget.onManage?.call();
                },
              ),
              child: Tooltip(
                message: summary.tooltip,
                child: Semantics(
                  button: true,
                  label: summary.tooltip,
                  child: TpHover(
                    key: const Key('managed-provider-usage-status-item'),
                    onTap: _popover.toggle,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: summary.selected
                        ? cs.onSurface.withValues(alpha: 0.08)
                        : null,
                    hoverColor: cs.onSurface.withValues(alpha: 0.08),
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 6 : 8,
                    ),
                    child: _SummaryContent(
                      summary: summary,
                      compact: widget.compact,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.summary, required this.compact});

  final _Summary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (summary.loading)
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        else
          Icon(
            summary.warning
                ? Icons.warning_amber_rounded
                : Icons.account_balance_wallet_outlined,
            key: summary.warning
                ? const Key('managed-provider-usage-warning')
                : null,
            size: 13,
            color: summary.warning ? cs.error : cs.onSurfaceVariant,
          ),
        const SizedBox(width: 4),
        if (!compact || summary.providers == 1)
          Text(
            summary.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.xs.copyWith(
              color: summary.warning ? cs.error : cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _Summary {
  const _Summary({
    required this.providers,
    required this.label,
    required this.tooltip,
    required this.warning,
    required this.loading,
    required this.selected,
  });

  final int providers;
  final String label;
  final String tooltip;
  final bool warning;
  final bool loading;
  final bool selected;

  factory _Summary.from(
    BuildContext context,
    List<ManagedProvider> providers,
    ManagedProviderUsageState usageState,
  ) {
    final l10n = context.l10n;
    if (providers.isEmpty) {
      return _Summary(
        providers: 0,
        label: l10n.managedProvidersAdd,
        tooltip: l10n.managedProvidersEmptyHint,
        warning: false,
        loading: false,
        selected: false,
      );
    }
    final warning = providers.any((provider) {
      final status = usageState.snapshotFor(provider.id)?.status;
      return status == ProviderUsageStatus.stale ||
          status == ProviderUsageStatus.error ||
          status == ProviderUsageStatus.unsupported;
    });
    final loading =
        usageState.isRefreshing ||
        usageState.status == ManagedProviderUsageLoadStatus.loading;
    final label = providers.length == 1
        ? _singleLabel(providers.single, usageState)
        : '${providers.length}';
    return _Summary(
      providers: providers.length,
      label: label,
      tooltip: warning
          ? '${l10n.managedProvidersTitle} · ${l10n.managedProvidersCachedUsageStale}'
          : l10n.managedProvidersTitle,
      warning: warning,
      loading: loading,
      selected: false,
    );
  }

  static String _singleLabel(
    ManagedProvider provider,
    ManagedProviderUsageState usageState,
  ) {
    final measure = usageState.snapshotFor(provider.id)?.measures.firstOrNull;
    if (measure == null) return '—';
    final value = measure.remaining ?? measure.used ?? measure.total ?? '—';
    final suffix = [
      if (measure.currency?.trim().isNotEmpty == true) measure.currency!,
      if (measure.unit?.trim().isNotEmpty == true) measure.unit!,
    ].join(' ');
    return suffix.isEmpty ? value : '$value $suffix';
  }
}
