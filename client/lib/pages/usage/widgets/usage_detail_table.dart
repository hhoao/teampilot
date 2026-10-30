import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../repositories/app_settings_repository.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/ui/app_keys.dart';
import 'usage_table_columns.dart';
import 'usage_table_pagination.dart';
import 'usage_table_toolbar.dart';

class UsageDetailTable extends StatefulWidget {
  const UsageDetailTable({
    required this.dashboard,
    required this.groupBy,
    required this.searchController,
    required this.onQueryChanged,
    required this.onGroupByChanged,
    required this.onResetFilters,
    this.resetKey = '',
    super.key,
  });

  final UsageDashboard dashboard;
  final UsageGroupBy groupBy;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UsageGroupBy> onGroupByChanged;
  final VoidCallback onResetFilters;

  /// Changes whenever range/CLI/group/search filters change; resets the page.
  final String resetKey;

  @override
  State<UsageDetailTable> createState() => _UsageDetailTableState();
}

class _UsageDetailTableState extends State<UsageDetailTable> {
  static const _pageSizeOptions = <int>[10, 20, 50, 100];
  static const _tableId = 'usage.detail';
  static const _defaultSort = TpTableSort(
    columnId: usageTotalColumnId,
    ascending: false,
  );

  int _pageSize = 20;
  int _page = 0;
  TpTableState _tableState = const TpTableState(sort: _defaultSort);

  @override
  void initState() {
    super.initState();
    _loadTableState();
  }

  @override
  void didUpdateWidget(covariant UsageDetailTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey ||
        oldWidget.groupBy != widget.groupBy) {
      _page = 0;
    }
  }

  Future<void> _loadTableState() async {
    final repository = context.read<AppSettingsRepository?>();
    if (repository == null) return;
    try {
      final saved = await repository.loadTableState(_tableId);
      if (!mounted || saved == null) return;
      setState(() {
        _tableState = TpTableState.fromJson(saved).copyWith(sort: _defaultSort);
      });
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[usage] table state load failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _saveTableState(TpTableState state) {
    final repository = context.read<AppSettingsRepository?>();
    if (repository == null) return;
    unawaited(
      repository
          .saveTableState(_tableId, state.copyWith(clearSort: true).toJson())
          .catchError((Object error, StackTrace stackTrace) {
            AppLogger.instance.w(
              '[usage] table state save failed: $error',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void _onStateChanged(TpTableState next) {
    final previous = _tableState;
    setState(() {
      _tableState = next;
      if (previous.sort != next.sort || previous.hidden != next.hidden) {
        _page = 0;
      }
    });
    _saveTableState(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final dashboard = widget.dashboard;
    final columns = buildUsageTableColumns(
      context: context,
      summary: dashboard.summary,
      groupBy: widget.groupBy,
    );
    final sortedRows = sortUsageRows(
      dashboard.rows,
      _tableState.sort ?? _defaultSort,
      columns,
    );

    final total = sortedRows.length;
    final pageCount = total == 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pageCount - 1);
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    final pageRows = total == 0
        ? const <UsageGroup>[]
        : sortedRows.sublist(start, end);
    final showPager = total > _pageSizeOptions.first;

    final labels = TpDataTableLabels(
      columns: l10n.sessionUsageColumnSettings,
      reset: l10n.sessionUsageColumnReset,
      empty: l10n.sessionUsageTableEmpty,
      sortAscending: l10n.sessionUsageSortAscending,
      sortDescending: l10n.sessionUsageSortDescending,
    );

    return Container(
      key: AppKeys.sessionUsageTable,
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      decoration: workspaceCardDecoration(
        cs,
        radius: 14,
      ).copyWith(color: cs.workspaceCard),
      child: TpDataTable<UsageGroup>(
        columns: columns,
        rows: pageRows,
        rowKey: (row) => row.key,
        state: _tableState,
        defaultSort: _defaultSort,
        onStateChanged: _onStateChanged,
        minTableWidth: 1080,
        rowHeight: 56,
        maxHeight: 560,
        labels: labels,
        toolbar: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: UsageTableToolbar(
            groupBy: widget.groupBy,
            searchController: widget.searchController,
            onQueryChanged: widget.onQueryChanged,
            onGroupByChanged: widget.onGroupByChanged,
            columns: columns,
            tableState: _tableState,
            onTableStateChanged: _onStateChanged,
            labels: labels,
          ),
        ),
        footer: showPager
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: UsageTablePagination(
                  page: page,
                  pageCount: pageCount,
                  start: start,
                  end: end,
                  total: total,
                  pageSize: _pageSize,
                  pageSizeOptions: _pageSizeOptions,
                  onPageSizeChanged: (size) {
                    setState(() {
                      _pageSize = size;
                      _page = 0;
                    });
                  },
                  onPrev: page == 0
                      ? null
                      : () => setState(() => _page = page - 1),
                  onNext: page >= pageCount - 1
                      ? null
                      : () => setState(() => _page = page + 1),
                ),
              )
            : null,
        emptyState: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.sessionUsageTableEmpty,
                style: TpTextStyles.of(context).smMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.sessionUsageTableEmptyHint,
                style: TpTextStyles.of(
                  context,
                ).xs.copyWith(color: cs.onSurface.withValues(alpha: 0.56)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onResetFilters,
                child: Text(l10n.sessionUsageResetFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
