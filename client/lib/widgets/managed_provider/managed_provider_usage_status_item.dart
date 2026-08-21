import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/provider_usage_snapshot.dart';
import '../workspace_status_bar/workspace_status_bar.dart';
import 'managed_provider_brand_icon.dart';
import 'managed_provider_usage_panel.dart';
import 'managed_provider_usage_status_focus.dart';

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
  Map<String, ProviderUsageSnapshot> _previousSnapshots = const {};
  String? _focusedProviderId;

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
            final snapshots = usageState.snapshots;
            _focusedProviderId = resolveManagedProviderUsageFocus(
              enabledProviders: providers,
              currentSnapshots: snapshots,
              previousSnapshots: _previousSnapshots,
              currentFocusId: _focusedProviderId,
            );
            _previousSnapshots =
                Map<String, ProviderUsageSnapshot>.unmodifiable(snapshots);
            final summary = _Summary.from(
              context,
              providers,
              usageState,
              focusedProviderId: _focusedProviderId,
            );
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

    Widget leadingIcon;
    if (summary.loading) {
      leadingIcon = const SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    } else if (summary.providerList.length == 1) {
      leadingIcon = KeyedSubtree(
        key: Key('managed-provider-brand-${summary.providerList.single.id}'),
        child: ManagedProviderBrandMark(
          provider: summary.providerList.single,
          size: 15,
        ),
      );
    } else {
      leadingIcon = Icon(
        Icons.account_balance_wallet_outlined,
        size: 13,
        color: cs.onSurfaceVariant,
      );
    }

    final warningIcon = summary.warning && !summary.loading
        ? Icon(
            Icons.warning_amber_rounded,
            key: const Key('managed-provider-usage-warning'),
            size: 13,
            color: cs.error,
          )
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leadingIcon,
        if (warningIcon != null) ...[const SizedBox(width: 2), warningIcon],
        const SizedBox(width: 4),
        if (!compact || summary.providerList.length == 1)
          Text(
            summary.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.xs.copyWith(
              color: summary.warning ? cs.error : cs.onSurfaceVariant,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _Summary {
  const _Summary({
    required this.providerList,
    required this.label,
    required this.tooltip,
    required this.warning,
    required this.loading,
    required this.selected,
  });

  final List<ManagedProvider> providerList;
  final String label;
  final String tooltip;
  final bool warning;
  final bool loading;
  final bool selected;

  factory _Summary.from(
    BuildContext context,
    List<ManagedProvider> providers,
    ManagedProviderUsageState usageState, {
    String? focusedProviderId,
  }) {
    final l10n = context.l10n;
    if (providers.isEmpty) {
      return _Summary(
        providerList: const [],
        label: l10n.managedProvidersAdd,
        tooltip: l10n.managedProvidersEmptyHint,
        warning: false,
        loading: false,
        selected: false,
      );
    }
    final loading =
        usageState.isRefreshing ||
        (usageState.status == ManagedProviderUsageLoadStatus.loading &&
            usageState.snapshots.isEmpty);
    ManagedProvider? focused;
    if (focusedProviderId != null) {
      for (final p in providers) {
        if (p.id == focusedProviderId) {
          focused = p;
          break;
        }
      }
    }
    focused ??= providers.isEmpty ? null : providers.first;
    final displayList = focused == null
        ? const <ManagedProvider>[]
        : <ManagedProvider>[focused];
    final label = focused == null ? '—' : _singleLabel(focused, usageState);
    // Warn only for the provider currently shown. TTL `stale` is silent;
    // off-screen providers (e.g. missing Claude credentials) must not paint
    // the focused Codex/DeepSeek segment red.
    final focusedStatus = focused == null
        ? null
        : usageState.snapshotFor(focused.id)?.status;
    final warning =
        focusedStatus == ProviderUsageStatus.error ||
        focusedStatus == ProviderUsageStatus.unsupported;
    return _Summary(
      providerList: displayList,
      label: label,
      tooltip: warning
          ? '${l10n.managedProvidersTitle} · ${l10n.managedProvidersQueryFailed}'
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
