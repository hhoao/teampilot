import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_table_columns.dart';

UsageGroup _row(
  String label, {
  required int total,
  required int input,
  List<CliTool> clis = const [],
}) {
  return UsageGroup(
    key: 'k:$label',
    label: label,
    clis: clis,
    totalTokens: total,
    freshInputTokens: input,
    outputTokens: 0,
    cacheReadTokens: 0,
    requests: total,
    sessions: 1,
  );
}

void main() {
  test('sortUsageRows sorts descending and ascending with stable ties', () {
    final rows = [
      _row('a', total: 10, input: 1),
      _row('b', total: 30, input: 2),
      _row('c', total: 20, input: 3),
      _row('d', total: 30, input: 4),
    ];
    final columns = <TpTableColumn<UsageGroup>>[
      TpTableColumn<UsageGroup>(
        id: 'total',
        label: 'Total',
        sortValue: (row) => row.totalTokens,
        cellBuilder: (context, row) => const SizedBox.shrink(),
      ),
    ];

    final descending = sortUsageRows(
      rows,
      const TpTableSort(columnId: 'total', ascending: false),
      columns,
    );
    expect(descending.map((row) => row.label), ['b', 'd', 'c', 'a']);

    final ascending = sortUsageRows(
      rows,
      const TpTableSort(columnId: 'total', ascending: true),
      columns,
    );
    expect(ascending.map((row) => row.label), ['a', 'c', 'b', 'd']);
  });

  test('sortUsageRows leaves rows unchanged for an unknown column', () {
    final rows = [
      _row('a', total: 10, input: 1),
      _row('b', total: 30, input: 2),
    ];
    final sorted = sortUsageRows(
      rows,
      const TpTableSort(columnId: 'missing', ascending: false),
      const [],
    );
    expect(sorted.map((row) => row.label), ['a', 'b']);
  });

  testWidgets('columns expose a locked group column and formatted cells', (
    tester,
  ) async {
    late List<TpTableColumn<UsageGroup>> columns;
    late List<TpTableColumn<UsageGroup>> cliGroupColumns;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            columns = buildUsageTableColumns(
              context: context,
              summary: const UsageSummary(totalTokens: 100),
              groupBy: UsageGroupBy.session,
            );
            cliGroupColumns = buildUsageTableColumns(
              context: context,
              summary: const UsageSummary(totalTokens: 100),
              groupBy: UsageGroupBy.cli,
            );
            return Column(
              children: [
                SizedBox(
                  width: 300,
                  child: columns
                      .firstWhere((column) => column.id == usageGroupColumnId)
                      .cellBuilder(context, _row('codex', total: 10, input: 1)),
                ),
                columns
                    .firstWhere((column) => column.id == 'share')
                    .cellBuilder(context, _row('share', total: 50, input: 10)),
                columns
                    .firstWhere((column) => column.id == 'cost')
                    .cellBuilder(context, _row('cost', total: 10, input: 1)),
              ],
            );
          },
        ),
      ),
    );

    final group = columns.firstWhere(
      (column) => column.id == usageGroupColumnId,
    );
    expect(group.locked, isTrue);
    expect(group.hideable, isFalse);
    expect(group.draggable, isFalse);
    expect(group.flex, 3);
    expect(group.minWidth, 240);
    expect(group.label, 'Session');

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Unpriced'), findsOneWidget);

    final cliColumn = columns.firstWhere(
      (column) => column.id == usageCliColumnId,
    );
    expect(cliColumn.label, 'CLI');
    expect(cliColumn.width, 120);
    expect(
      cliGroupColumns.any((column) => column.id == usageCliColumnId),
      isFalse,
    );
  });

  testWidgets('CLI column renders one icon per tool', (tester) async {
    late List<TpTableColumn<UsageGroup>> columns;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            columns = buildUsageTableColumns(
              context: context,
              summary: const UsageSummary(totalTokens: 100),
              groupBy: UsageGroupBy.session,
            );
            return columns
                .firstWhere((column) => column.id == usageCliColumnId)
                .cellBuilder(
                  context,
                  _row(
                    'Alpha',
                    total: 10,
                    input: 1,
                    clis: [CliTool.claude, CliTool.codex],
                  ),
                );
          },
        ),
      ),
    );

    expect(find.byTooltip('Claude Code'), findsOneWidget);
    expect(find.byTooltip('Codex'), findsOneWidget);
  });
}
