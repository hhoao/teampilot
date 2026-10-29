import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/widgets/usage_table_columns.dart';

UsageGroup _row(String label, {required int total, required int input}) {
  return UsageGroup(
    key: 'k:$label',
    label: label,
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
}
