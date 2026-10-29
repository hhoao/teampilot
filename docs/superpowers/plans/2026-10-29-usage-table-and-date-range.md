# Token 用量表与时间范围选择器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-written token usage table with a reusable sortable/draggable/hideable `TpDataTable`, move group controls into the table header, add CLI icon filters, and replace the range chips with a cc-switch-style date-time range picker.

**Architecture:** `shared_ui` gains a controlled `TpDataTable` (column model + external `TpTableState`) and a `TpDateTimeRangePicker` composed from `TpPopover`, `TpCalendar`, and `TpTimePicker`. The usage page owns table state, sort/pagination, and persistence through `AppSettingsRepository`. `UsageRange`/`UsageFilter`/`SessionUsageCubit` gain custom bounds and live-end semantics.

**Tech Stack:** Flutter, `flutter_bloc`, `shared_ui`, `shared_preferences`, `intl`, `flutter_test`.

## Global Constraints

- Never run `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Edit only `client/lib/l10n/app_en.arb` and `app_zh.arb`; never hand-edit `l10n/app_localizations*.dart`.
- `shared_ui` must not import app l10n or `shared_preferences`; pass labels and persistence callbacks in.
- No third-party table dependency.
- File size soft limits: pages ~400, files under `pages/` ~500, cubits ~500, services ~600.
- Use `context.read<AppSettingsRepository?>()` for optional persistence; tests without the provider must still render.
- Every user-facing string goes through l10n (app) or injected labels (`shared_ui`).
- Commit after every task.

---

### Task 1: Table column model and state helpers

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/table/tp_table_column.dart`
- Create: `client/packages/shared_ui/lib/src/components/table/tp_table_state.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/components/table/tp_table_state_test.dart`

**Interfaces:**
- Produces:
  - `TpTableColumn<T>` with `id`, `label`, `cellBuilder`, `width`, `flex`, `minWidth`, `alignment`, `sortValue`, `hideable`, `locked`, `draggable`, `groupStart`.
  - `TpTableSort({required String columnId, required bool ascending})`.
  - `TpTableState({List<String> order, Set<String> hidden, TpTableSort? sort})`, `copyWith`, `toJson`, `fromJson`.
  - `TpTableLayout.resolve<T>({required List<TpTableColumn<T>> columns, required double availableWidth, required double minTableWidth})`.
  - `tpTableCellPadding({required bool first, required bool last, required bool groupStart})`.
  - `orderedTableColumns<T>(List<TpTableColumn<T>>, TpTableState)`.
  - `visibleTableColumns<T>(List<TpTableColumn<T>>, TpTableState)`.
  - `reorderTableColumnIds(List<String> ids, String draggedId, String targetId)`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/table/tp_table_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

TpTableColumn<String> _column(
  String id, {
  bool locked = false,
  bool hideable = true,
}) {
  return TpTableColumn<String>(
    id: id,
    label: id,
    locked: locked,
    hideable: hideable,
    cellBuilder: (context, row) => Text(row),
  );
}

void main() {
  test('locked columns stay first and stored order wins', () {
    final columns = [
      _column('group', locked: true),
      _column('total'),
      _column('input'),
    ];

    final ordered = orderedTableColumns(
      columns,
      const TpTableState(order: ['input', 'total']),
    );

    expect(ordered.map((column) => column.id), ['group', 'input', 'total']);
  });

  test('new columns insert before the next known column', () {
    final columns = [
      _column('group', locked: true),
      _column('total'),
      _column('input'),
      _column('share'),
    ];

    final ordered = orderedTableColumns(
      columns,
      const TpTableState(order: ['group', 'share']),
    );

    expect(ordered.map((column) => column.id), [
      'group',
      'total',
      'input',
      'share',
    ]);
  });

  test('hidden columns are removed but locked stays', () {
    final columns = [
      _column('group', locked: true),
      _column('total'),
      _column('input'),
    ];

    final visible = visibleTableColumns(
      columns,
      const TpTableState(hidden: {'group', 'input'}),
    );

    expect(visible.map((column) => column.id), ['group', 'total']);
  });

  test('reorderTableColumnIds moves to the target slot', () {
    expect(
      reorderTableColumnIds(['group', 'total', 'input'], 'total', 'input'),
      ['group', 'input', 'total'],
    );
  });

  test('json round trip and malformed input', () {
    const state = TpTableState(
      order: ['group', 'total'],
      hidden: {'input'},
      sort: TpTableSort(columnId: 'total', ascending: false),
    );

    final restored = TpTableState.fromJson(state.toJson());
    expect(restored.order, state.order);
    expect(restored.hidden, state.hidden);
    expect(restored.sort, state.sort);

    final malformed = TpTableState.fromJson({
      'order': 'bad',
      'hidden': 3,
      'sort': [],
    });
    expect(malformed.order, isEmpty);
    expect(malformed.hidden, isEmpty);
    expect(malformed.sort, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_table_state_test.dart
```

Expected: FAIL because `TpTableColumn`, `TpTableState`, and helpers do not exist.

- [ ] **Step 3: Implement the column model**

Create `client/packages/shared_ui/lib/src/components/table/tp_table_column.dart`:

```dart
import 'package:flutter/material.dart';

/// One column in a [TpDataTable].
///
/// [width] wins over [flex]. Flex columns share the remaining width after
/// fixed columns, never shrinking below [minWidth].
@immutable
class TpTableColumn<T> {
  const TpTableColumn({
    required this.id,
    required this.label,
    required this.cellBuilder,
    this.width,
    this.flex = 1,
    this.minWidth = 80,
    this.alignment = Alignment.centerLeft,
    this.sortValue,
    this.hideable = true,
    this.locked = false,
    this.draggable = true,
    this.groupStart = false,
  });

  final String id;
  final String label;
  final Widget Function(BuildContext context, T row) cellBuilder;
  final double? width;
  final int flex;
  final double minWidth;
  final Alignment alignment;
  final Comparable? Function(T row)? sortValue;
  final bool hideable;
  final bool locked;
  final bool draggable;
  final bool groupStart;
}

/// Resolved column widths for one table layout pass.
@immutable
class TpTableLayout {
  const TpTableLayout({required this.widths, required this.totalWidth});

  final Map<String, double> widths;
  final double totalWidth;

  double widthOf(String id) => widths[id] ?? 0;

  static TpTableLayout resolve<T>({
    required List<TpTableColumn<T>> columns,
    required double availableWidth,
    required double minTableWidth,
  }) {
    final target = availableWidth < minTableWidth
        ? minTableWidth
        : availableWidth;
    final fixedWidth = columns
        .where((column) => column.width != null)
        .fold<double>(0, (sum, column) => sum + column.width!);
    final flexColumns = columns
        .where((column) => column.width == null)
        .toList(growable: false);
    final flexTotal = flexColumns.fold<int>(
      0,
      (sum, column) => sum + column.flex,
    );

    final widths = <String, double>{};
    for (final column in columns) {
      final fixed = column.width;
      if (fixed != null) {
        widths[column.id] = fixed;
        continue;
      }
      final share = flexTotal == 0
          ? 0.0
          : (target - fixedWidth) * column.flex / flexTotal;
      widths[column.id] = share < column.minWidth ? column.minWidth : share;
    }

    final total = widths.values.fold<double>(0, (sum, width) => sum + width);
    return TpTableLayout(widths: widths, totalWidth: total);
  }
}

EdgeInsets tpTableCellPadding({
  required bool first,
  required bool last,
  required bool groupStart,
}) {
  final left = first ? 16.0 : (groupStart ? 40.0 : 24.0);
  final right = last ? 16.0 : 24.0;
  return EdgeInsets.only(left: left, right: right);
}
```

- [ ] **Step 4: Implement the state model**

Create `client/packages/shared_ui/lib/src/components/table/tp_table_state.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'tp_table_column.dart';

@immutable
class TpTableSort {
  const TpTableSort({required this.columnId, required this.ascending});

  final String columnId;
  final bool ascending;

  @override
  bool operator ==(Object other) {
    return other is TpTableSort &&
        other.columnId == columnId &&
        other.ascending == ascending;
  }

  @override
  int get hashCode => Object.hash(columnId, ascending);
}

@immutable
class TpTableState {
  const TpTableState({
    this.order = const [],
    this.hidden = const {},
    this.sort,
  });

  final List<String> order;
  final Set<String> hidden;
  final TpTableSort? sort;

  TpTableState copyWith({
    List<String>? order,
    Set<String>? hidden,
    TpTableSort? sort,
    bool clearSort = false,
  }) {
    return TpTableState(
      order: order ?? this.order,
      hidden: hidden ?? this.hidden,
      sort: clearSort ? null : (sort ?? this.sort),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'hidden': hidden.toList(growable: false),
      if (sort != null)
        'sort': {
          'column': sort!.columnId,
          'ascending': sort!.ascending,
        },
    };
  }

  factory TpTableState.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['order'];
    if (rawOrder is List) {
      for (final value in rawOrder) {
        if (value is String && value.isNotEmpty && !order.contains(value)) {
          order.add(value);
        }
      }
    }

    final hidden = <String>{};
    final rawHidden = json['hidden'];
    if (rawHidden is List) {
      for (final value in rawHidden) {
        if (value is String && value.isNotEmpty) hidden.add(value);
      }
    }

    TpTableSort? sort;
    final rawSort = json['sort'];
    if (rawSort is Map) {
      final column = rawSort['column'];
      final ascending = rawSort['ascending'];
      if (column is String && column.isNotEmpty && ascending is bool) {
        sort = TpTableSort(columnId: column, ascending: ascending);
      }
    }

    return TpTableState(order: order, hidden: hidden, sort: sort);
  }
}

/// All columns in display order: locked first, then persisted order, then any
/// columns missing from the persisted order at their default position.
List<TpTableColumn<T>> orderedTableColumns<T>(
  List<TpTableColumn<T>> columns,
  TpTableState state,
) {
  final byId = {for (final column in columns) column.id: column};
  final ordered = <TpTableColumn<T>>[];
  final seen = <String>{};

  for (final column in columns.where((column) => column.locked)) {
    if (seen.add(column.id)) ordered.add(column);
  }

  for (final id in state.order) {
    final column = byId[id];
    if (column == null || column.locked || !seen.add(column.id)) continue;
    ordered.add(column);
  }

  for (var index = 0; index < columns.length; index++) {
    final column = columns[index];
    if (column.locked || seen.contains(column.id)) continue;

    var insertAt = ordered.length;
    for (var nextIndex = index + 1; nextIndex < columns.length; nextIndex++) {
      final next = columns[nextIndex];
      final at = ordered.indexWhere((item) => item.id == next.id);
      if (at >= 0) {
        insertAt = at;
        break;
      }
    }
    ordered.insert(insertAt, column);
    seen.add(column.id);
  }

  return ordered;
}

List<TpTableColumn<T>> visibleTableColumns<T>(
  List<TpTableColumn<T>> columns,
  TpTableState state,
) {
  return orderedTableColumns(columns, state)
      .where((column) => column.locked || !state.hidden.contains(column.id))
      .toList(growable: false);
}

/// Moves [draggedId] into [targetId]'s slot.
///
/// For `['a','b','c']`, dragging `a` onto `c` yields `['b','c','a']`;
/// dragging `c` onto `a` yields `['c','a','b']`.
List<String> reorderTableColumnIds(
  List<String> ids,
  String draggedId,
  String targetId,
) {
  final next = List<String>.of(ids);
  final from = next.indexOf(draggedId);
  final to = next.indexOf(targetId);
  if (from < 0 || to < 0 || from == to) return next;
  next.removeAt(from);
  next.insert(to.clamp(0, next.length), draggedId);
  return next;
}
```

- [ ] **Step 5: Export the new files**

Modify `client/packages/shared_ui/lib/shared_ui.dart` after the `tab` exports:

```dart
export 'src/components/table/tp_table_column.dart';
export 'src/components/table/tp_table_state.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run:

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_table_state_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/lib/src/components/table/tp_table_column.dart \
  client/packages/shared_ui/lib/src/components/table/tp_table_state.dart \
  client/packages/shared_ui/test/components/table/tp_table_state_test.dart
git commit -m "feat(shared_ui): add table column model and state"
```

---

### Task 2: Table rendering, sorting, and column visibility

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/table/tp_table_column_menu.dart`
- Create: `client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart`
- Create: `client/packages/shared_ui/lib/src/components/table/tp_data_table_body.dart`
- Create: `client/packages/shared_ui/lib/src/components/table/tp_data_table.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/components/table/tp_data_table_test.dart`

**Interfaces:**
- Consumes: Task 1 types and helpers.
- Produces:
  - `TpDataTableLabels({String columns, String reset, String empty})`.
  - `TpDataTable<T>({required columns, rows, rowKey, state, onStateChanged, TpTableSort? defaultSort, toolbar, footer, emptyState, rowHeight, headerHeight, minTableWidth, labels})`.
  - `TpTableColumnMenu<T>({required columns, required state, required onChanged, required labels})`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/table/tp_data_table_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

final _columns = <TpTableColumn<String>>[
  TpTableColumn<String>(
    id: 'name',
    label: 'Name',
    locked: true,
    hideable: false,
    draggable: false,
    cellBuilder: (context, row) => Text(row),
  ),
  TpTableColumn<String>(
    id: 'value',
    label: 'Value',
    width: 100,
    sortValue: (row) => row.length,
    cellBuilder: (context, row) => Text('${row.length}'),
  ),
  TpTableColumn<String>(
    id: 'extra',
    label: 'Extra',
    width: 100,
    cellBuilder: (context, row) => const Text('extra'),
  ),
];

class _Host extends StatefulWidget {
  const _Host({this.rows = const ['alpha', 'four']});

  final List<String> rows;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  TpTableState state = const TpTableState(
    sort: TpTableSort(columnId: 'value', ascending: false),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.indigo),
          scale: 1,
        ),
        child: Scaffold(
          body: TpDataTable<String>(
            columns: _columns,
            rows: widget.rows,
            rowKey: (row) => row,
            state: state,
            defaultSort: const TpTableSort(
              columnId: 'value',
              ascending: false,
            ),
            onStateChanged: (next) => setState(() => state = next),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders headers and rows', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Value'), findsOneWidget);
    expect(find.text('Extra'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('four'), findsOneWidget);
  });

  testWidgets('clicking a sortable header cycles descending, ascending, default', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });

  testWidgets('column menu hides and restores a column', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<String>),
        matching: find.text('Extra'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<String>),
        matching: find.text('Extra'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty rows render the empty slot', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.indigo),
            scale: 1,
          ),
          child: Scaffold(
            body: TpDataTable<String>(
              columns: _columns,
              rows: const [],
              rowKey: _rowKey,
              state: const TpTableState(),
              emptyState: const Text('empty'),
              onStateChanged: _ignoreState,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('empty'), findsOneWidget);
  });
}

String _rowKey(String row) => row;

void _ignoreState(TpTableState state) {}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_data_table_test.dart
```

Expected: FAIL because `TpDataTable`, `TpDataTableLabels`, and `TpTableColumnMenu` do not exist.

- [ ] **Step 3: Implement the column menu**

Create `client/packages/shared_ui/lib/src/components/table/tp_table_column_menu.dart`:

```dart
import 'package:flutter/material.dart';

import '../action_menu/tp_action_menu.dart';
import '../icon_button/tp_icon_button.dart';
import '../popover/tp_popover.dart';
import 'tp_table_column.dart';
import 'tp_table_state.dart';

@immutable
class TpDataTableLabels {
  const TpDataTableLabels({
    this.columns = 'Columns',
    this.reset = 'Reset to default',
    this.empty = 'No data',
  });

  final String columns;
  final String reset;
  final String empty;
}

class TpTableColumnMenu<T> extends StatefulWidget {
  const TpTableColumnMenu({
    required this.columns,
    required this.state,
    required this.onChanged,
    required this.labels,
    super.key,
  });

  final List<TpTableColumn<T>> columns;
  final TpTableState state;
  final ValueChanged<TpTableState> onChanged;
  final TpDataTableLabels labels;

  @override
  State<TpTableColumnMenu<T>> createState() => _TpTableColumnMenuState<T>();
}

class _TpTableColumnMenuState<T> extends State<TpTableColumnMenu<T>> {
  late final TpPopoverController _controller = TpPopoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(TpTableColumn<T> column) {
    final hidden = Set<String>.of(widget.state.hidden);
    if (!hidden.add(column.id)) hidden.remove(column.id);
    widget.onChanged(widget.state.copyWith(hidden: hidden));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final columns = orderedTableColumns(widget.columns, widget.state)
        .where((column) => !column.locked)
        .toList(growable: false);

    return TpPopover(
      controller: _controller,
      panelWidth: 220,
      padding: EdgeInsets.zero,
      decoration: TpActionMenuMetrics.panelDecoration(context),
      anchor: const TpAnchor(
        childAlignment: Alignment.topRight,
        overlayAlignment: Alignment.bottomRight,
        offset: Offset(0, 4),
      ),
      popover: (context) => TpActionMenuPanel(
        children: [
          for (final column in columns)
            TpActionMenuItem(
              label: column.label,
              enabled: column.hideable,
              trailing: Icon(
                Icons.check,
                size: 16,
                color: !widget.state.hidden.contains(column.id)
                    ? cs.primary
                    : Colors.transparent,
              ),
              onTap: column.hideable ? () => _toggle(column) : null,
            ),
          const TpActionMenuDivider(),
          TpActionMenuItem(
            label: widget.labels.reset,
            onTap: () => widget.onChanged(
              widget.state.copyWith(order: const [], hidden: const {}),
            ),
          ),
        ],
      ),
      child: TpIconButton(
        icon: Icons.view_column_outlined,
        tooltip: widget.labels.columns,
        onTap: _controller.toggle,
      ),
    );
  }
}
```

- [ ] **Step 4: Implement the header**

Create `client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/tp_text_styles.dart';
import 'tp_table_column.dart';
import 'tp_table_state.dart';

class TpTableHeader<T> extends StatelessWidget {
  const TpTableHeader({
    required this.columns,
    required this.layout,
    required this.sort,
    required this.onSort,
    required this.firstId,
    required this.lastId,
    required this.headerHeight,
    super.key,
  });

  final List<TpTableColumn<T>> columns;
  final TpTableLayout layout;
  final TpTableSort? sort;
  final ValueChanged<String> onSort;
  final String firstId;
  final String lastId;
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: headerHeight,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final column in columns)
            SizedBox(
              width: layout.widthOf(column.id),
              child: _HeaderCell<T>(
                key: ValueKey(column.id),
                column: column,
                sorted: sort?.columnId == column.id,
                ascending: sort?.ascending ?? false,
                first: column.id == firstId,
                last: column.id == lastId,
                onSort: onSort,
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sorted,
    required this.ascending,
    required this.first,
    required this.last,
    required this.onSort,
    super.key,
  });

  final TpTableColumn<T> column;
  final bool sorted;
  final bool ascending;
  final bool first;
  final bool last;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return InkWell(
      onTap: column.sortValue == null ? null : () => onSort(column.id),
      child: Padding(
        padding: tpTableCellPadding(
          first: first,
          last: last,
          groupStart: column.groupStart,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                column.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (sorted) ...[
              const SizedBox(width: 2),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement the row**

Create `client/packages/shared_ui/lib/src/components/table/tp_data_table_body.dart`:

```dart
import 'package:flutter/material.dart';

import 'tp_table_column.dart';

class TpTableRow<T> extends StatelessWidget {
  const TpTableRow({
    required this.columns,
    required this.layout,
    required this.row,
    required this.firstId,
    required this.lastId,
    required this.rowHeight,
    required this.hovered,
    required this.onHoverChanged,
    super.key,
  });

  final List<TpTableColumn<T>> columns;
  final TpTableLayout layout;
  final T row;
  final String firstId;
  final String lastId;
  final double rowHeight;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: hovered
              ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
              : null,
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final column in columns)
              SizedBox(
                width: layout.widthOf(column.id),
                child: Padding(
                  padding: tpTableCellPadding(
                    first: column.id == firstId,
                    last: column.id == lastId,
                    groupStart: column.groupStart,
                  ),
                  child: Align(
                    alignment: column.alignment,
                    child: column.cellBuilder(context, row),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement the table**

Create `client/packages/shared_ui/lib/src/components/table/tp_data_table.dart`:

```dart
import 'package:flutter/material.dart';

import 'tp_data_table_body.dart';
import 'tp_data_table_header.dart';
import 'tp_table_column.dart';
import 'tp_table_column_menu.dart';
import 'tp_table_state.dart';

class TpDataTable<T> extends StatefulWidget {
  const TpDataTable({
    required this.columns,
    required this.rows,
    required this.rowKey,
    required this.state,
    required this.onStateChanged,
    this.defaultSort,
    this.toolbar,
    this.footer,
    this.emptyState,
    this.rowHeight = 40,
    this.headerHeight = 36,
    this.minTableWidth = 720,
    this.labels = const TpDataTableLabels(),
    super.key,
  });

  final List<TpTableColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowKey;
  final TpTableState state;
  final ValueChanged<TpTableState> onStateChanged;
  final TpTableSort? defaultSort;
  final Widget? toolbar;
  final Widget? footer;
  final Widget? emptyState;
  final double rowHeight;
  final double headerHeight;
  final double minTableWidth;
  final TpDataTableLabels labels;

  @override
  State<TpDataTable<T>> createState() => _TpDataTableState<T>();
}

class _TpDataTableState<T> extends State<TpDataTable<T>> {
  int? _hoveredRow;

  void _setHovered(int index, bool hovered) {
    setState(() {
      if (hovered) {
        _hoveredRow = index;
      } else if (_hoveredRow == index) {
        _hoveredRow = null;
      }
    });
  }

  void _handleSort(String columnId) {
    final current = widget.state.sort ?? widget.defaultSort;
    final TpTableSort? next;
    if (current?.columnId != columnId) {
      next = TpTableSort(columnId: columnId, ascending: false);
    } else if (current!.ascending) {
      next = widget.defaultSort;
    } else {
      next = TpTableSort(columnId: columnId, ascending: true);
    }
    widget.onStateChanged(
      widget.state.copyWith(sort: next, clearSort: next == null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = visibleTableColumns(widget.columns, widget.state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.toolbar != null) ...[
          widget.toolbar!,
          const SizedBox(height: 10),
        ],
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        if (widget.rows.isEmpty)
          SizedBox(
            height: 160,
            child: Center(
              child: widget.emptyState ?? Text(widget.labels.empty),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = TpTableLayout.resolve(
                columns: visible,
                availableWidth: constraints.maxWidth,
                minTableWidth: widget.minTableWidth,
              );
              final pinned = visible
                  .where((column) => column.locked)
                  .toList(growable: false);
              final scrollable = visible
                  .where((column) => !column.locked)
                  .toList(growable: false);
              final pinnedWidth = pinned.fold<double>(
                0,
                (sum, column) => sum + layout.widthOf(column.id),
              );
              final scrollableWidth = scrollable.fold<double>(
                0,
                (sum, column) => sum + layout.widthOf(column.id),
              );
              final firstId = visible.isEmpty ? '' : visible.first.id;
              final lastId = visible.isEmpty ? '' : visible.last.id;
              final effectiveSort = widget.state.sort ?? widget.defaultSort;

              Widget rowsFor(List<TpTableColumn<T>> columns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TpTableHeader<T>(
                      columns: columns,
                      layout: layout,
                      sort: effectiveSort,
                      onSort: _handleSort,
                      firstId: firstId,
                      lastId: lastId,
                      headerHeight: widget.headerHeight,
                    ),
                    for (var index = 0; index < widget.rows.length; index++)
                      TpTableRow<T>(
                        columns: columns,
                        layout: layout,
                        row: widget.rows[index],
                        firstId: firstId,
                        lastId: lastId,
                        rowHeight: widget.rowHeight,
                        hovered: _hoveredRow == index,
                        onHoverChanged: (hovered) =>
                            _setHovered(index, hovered),
                      ),
                  ],
                );
              }

              if (pinned.isEmpty) {
                final width = layout.totalWidth < constraints.maxWidth
                    ? constraints.maxWidth
                    : layout.totalWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: rowsFor(visible)),
                );
              }

              final remainingWidth = constraints.maxWidth - pinnedWidth;
              final scrollWidth = remainingWidth > scrollableWidth
                  ? remainingWidth
                  : scrollableWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: pinnedWidth, child: rowsFor(pinned)),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollWidth < 0 ? 0 : scrollWidth,
                        child: rowsFor(scrollable),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }
}
```

- [ ] **Step 7: Export the new files**

Modify `client/packages/shared_ui/lib/shared_ui.dart`:

```dart
export 'src/components/table/tp_data_table.dart';
export 'src/components/table/tp_data_table_body.dart';
export 'src/components/table/tp_data_table_header.dart';
export 'src/components/table/tp_table_column_menu.dart';
```

- [ ] **Step 8: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_data_table_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/lib/src/components/table/ \
  client/packages/shared_ui/test/components/table/tp_data_table_test.dart
git commit -m "feat(shared_ui): add data table with sorting and column menu"
```

---

### Task 3: Column drag reordering

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart`
- Test: `client/packages/shared_ui/test/components/table/tp_data_table_drag_test.dart`

**Interfaces:**
- Consumes: `TpTableHeader` from Task 2; `onReorder` callback.
- Produces: hover-visible `Icons.drag_indicator` handle; `Draggable<String>` + `DragTarget<String>`; `onReorder(draggedId, targetId)`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/table/tp_data_table_drag_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

final _columns = <TpTableColumn<String>>[
  TpTableColumn<String>(
    id: 'name',
    label: 'Name',
    width: 120,
    locked: true,
    hideable: false,
    draggable: false,
    cellBuilder: (context, row) => Text(row),
  ),
  TpTableColumn<String>(
    id: 'value',
    label: 'Value',
    width: 120,
    cellBuilder: (context, row) => const Text('value'),
  ),
  TpTableColumn<String>(
    id: 'extra',
    label: 'Extra',
    width: 120,
    cellBuilder: (context, row) => const Text('extra'),
  ),
];

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  TpTableState state = const TpTableState();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.indigo),
          scale: 1,
        ),
        child: Scaffold(
          body: TpDataTable<String>(
            columns: _columns,
            rows: const ['row'],
            rowKey: (row) => row,
            state: state,
            onStateChanged: (next) => setState(() => state = next),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('hovering a draggable header shows the drag handle', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Value')));
    await tester.pump();

    expect(find.byIcon(Icons.drag_indicator), findsWidgets);
    await gesture.removePointer();
  });

  testWidgets('dragging a header onto another reorders columns', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Value')));
    await tester.pump();

    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveTo(tester.getCenter(find.text('Extra')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final hostState = tester.state<_HostState>(find.byType(_Host));
    expect(hostState.state.order, ['name', 'extra', 'value']);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_data_table_drag_test.dart
```

Expected: FAIL because no drag handle is rendered.

- [ ] **Step 3: Add drag support to the header**

Replace `_HeaderCell` in `client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart` with a stateful implementation:

```dart
class _HeaderCell<T> extends StatefulWidget {
  const _HeaderCell({
    required this.column,
    required this.sorted,
    required this.ascending,
    required this.first,
    required this.last,
    required this.height,
    required this.onSort,
    required this.onReorder,
    super.key,
  });

  final TpTableColumn<T> column;
  final bool sorted;
  final bool ascending;
  final bool first;
  final bool last;
  final double height;
  final ValueChanged<String> onSort;
  final void Function(String draggedId, String targetId) onReorder;

  @override
  State<_HeaderCell<T>> createState() => _HeaderCellState<T>();
}

class _HeaderCellState<T> extends State<_HeaderCell<T>> {
  bool _hovered = false;
  bool _dragging = false;

  bool get _canDrag => widget.column.draggable && !widget.column.locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canDrag && details.data != widget.column.id,
      onAcceptWithDetails: (details) =>
          widget.onReorder(details.data, widget.column.id),
      builder: (context, candidates, rejected) {
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Stack(
            children: [
              InkWell(
                onTap: widget.column.sortValue == null
                    ? null
                    : () => widget.onSort(widget.column.id),
                onLongPress: _canDrag
                    ? () => setState(() => _hovered = true)
                    : null,
                child: Padding(
                  padding: tpTableCellPadding(
                    first: widget.first,
                    last: widget.last,
                    groupStart: widget.column.groupStart,
                  ).copyWith(right: _canDrag ? 28 : null),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.column.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.xs.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.56),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.sorted) ...[
                        const SizedBox(width: 2),
                        Icon(
                          widget.ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 12,
                          color: cs.onSurface.withValues(alpha: 0.56),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (candidates.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: cs.primary),
                ),
              if (_canDrag && (_hovered || _dragging))
                Positioned(
                  right: 2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Draggable<String>(
                      data: widget.column.id,
                      axis: Axis.horizontal,
                      onDragStarted: () => setState(() => _dragging = true),
                      onDragEnd: (_) => setState(() => _dragging = false),
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 160,
                          height: widget.height,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            widget.column.label,
                            style: styles.xs.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(Icons.drag_indicator, size: 14),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Pass drag callbacks through the header**

Modify `TpTableHeader` in `client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart`:

```dart
  const TpTableHeader({
    required this.columns,
    required this.layout,
    required this.sort,
    required this.onSort,
    required this.onReorder,
    required this.firstId,
    required this.lastId,
    required this.headerHeight,
    super.key,
  });

  final List<TpTableColumn<T>> columns;
  final TpTableLayout layout;
  final TpTableSort? sort;
  final ValueChanged<String> onSort;
  final void Function(String draggedId, String targetId) onReorder;
  final String firstId;
  final String lastId;
  final double headerHeight;
```

Pass both the height and the callback when building the cell:

```dart
              child: _HeaderCell<T>(
                key: ValueKey(column.id),
                column: column,
                sorted: sort?.columnId == column.id,
                ascending: sort?.ascending ?? false,
                first: column.id == firstId,
                last: column.id == lastId,
                height: headerHeight,
                onSort: onSort,
                onReorder: onReorder,
              ),
```

- [ ] **Step 5: Add reorder handling to `TpDataTable`**

In `client/packages/shared_ui/lib/src/components/table/tp_data_table.dart`, add:

```dart
  void _handleReorder(String draggedId, String targetId) {
    final ids = orderedTableColumns(widget.columns, widget.state)
        .map((column) => column.id)
        .toList(growable: false);
    final next = reorderTableColumnIds(ids, draggedId, targetId);
    widget.onStateChanged(widget.state.copyWith(order: next));
  }
```

Pass it to both header instances:

```dart
                    TpTableHeader<T>(
                      columns: columns,
                      layout: layout,
                      sort: effectiveSort,
                      onSort: _handleSort,
                      onReorder: _handleReorder,
                      firstId: firstId,
                      lastId: lastId,
                      headerHeight: widget.headerHeight,
                    ),
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/tp_data_table_drag_test.dart
```

Expected: PASS.

- [ ] **Step 7: Run the earlier table tests**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/table/
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart \
  client/packages/shared_ui/lib/src/components/table/tp_data_table.dart \
  client/packages/shared_ui/test/components/table/tp_data_table_drag_test.dart
git commit -m "feat(shared_ui): reorder table columns by dragging headers"
```

---

### Task 4: Date-time range picker

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range.dart`
- Create: `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_panel.dart`
- Create: `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_picker.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart`

**Interfaces:**
- Consumes: `TpPopover`, `TpCalendar`, `TpTimePicker`, `TpButton`, `showTpDialog`, `TpDialog`.
- Produces:
  - `TpDateTimeRange({required DateTime start, required DateTime end, bool liveEnd})`.
  - `TpDateTimeRangePreset({required String id, required String label})`.
  - `TpDateTimeRangePickerLabels`.
  - `TpDateTimeRangeField { start, end }`.
  - `TpDateTimeRangePicker` with `value`, `onChanged`, `firstDate`, `lastDate`, `maxDuration`, `presets`, `selectedPresetId`, `onPresetSelected`, `triggerBuilder`, `panelsWidth`, `controller`.

- [ ] **Step 1: Write the failing test**

Create `client/packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ColorScheme.fromSeed(seedColor: Colors.indigo),
        scale: 1,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-range')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preset click calls onPresetSelected and closes', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          labels: const TpDateTimeRangePickerLabels(),
          presets: const [
            TpDateTimeRangePreset(id: 'today', label: 'Today'),
          ],
          onPresetSelected: (id) => selected = id,
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(selected, 'today');
  });

  testWidgets('confirm returns the draft range', (tester) async {
    TpDateTimeRange? applied;
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          value: TpDateTimeRange(
            start: DateTime(2026, 9, 29, 10),
            end: DateTime(2026, 10, 29, 12),
          ),
          labels: const TpDateTimeRangePickerLabels(),
          onChanged: (value) => applied = value,
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.start, DateTime(2026, 9, 29, 10));
    expect(applied!.end, DateTime(2026, 10, 29, 12));
  });

  testWidgets('editing the start hour updates the applied range', (
    tester,
  ) async {
    TpDateTimeRange? applied;
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          value: TpDateTimeRange(
            start: DateTime(2026, 9, 29, 10),
            end: DateTime(2026, 10, 29, 12),
          ),
          labels: const TpDateTimeRangePickerLabels(),
          onChanged: (value) => applied = value,
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    await tester.enterText(
      find.byKey(const Key('tp-time-picker-hour')).first,
      '11',
    );
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(applied!.start.hour, 11);
  });

  testWidgets('invalid order shows an error and keeps the panel open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          value: TpDateTimeRange(
            start: DateTime(2026, 10, 29, 12),
            end: DateTime(2026, 10, 29, 10),
          ),
          labels: const TpDateTimeRangePickerLabels(),
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(
      find.text('Start time cannot be later than end time'),
      findsOneWidget,
    );
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets('range longer than maxDuration shows an error', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          maxDuration: const Duration(days: 30),
          value: TpDateTimeRange(
            start: DateTime(2026, 1, 1),
            end: DateTime(2026, 3, 1),
          ),
          labels: const TpDateTimeRangePickerLabels(),
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Range cannot exceed 30 days'), findsOneWidget);
  });

  testWidgets('live end disables the end time picker', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          value: TpDateTimeRange(
            start: DateTime(2026, 9, 29, 10),
            end: DateTime.now(),
            liveEnd: true,
          ),
          labels: const TpDateTimeRangePickerLabels(),
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    final pickers = tester.widgetList<TpTimePicker>(find.byType(TpTimePicker));
    expect(pickers.last.enabled, isFalse);
  });

  testWidgets('narrow viewport opens a dialog', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        TpDateTimeRangePicker(
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          labels: const TpDateTimeRangePickerLabels(),
          triggerBuilder: (context, isOpen) => const SizedBox(
            key: Key('open-range'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    await _open(tester);
    expect(find.byType(TpDialog), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart
```

Expected: FAIL because the picker types do not exist.

- [ ] **Step 3: Implement the models**

Create `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range.dart`:

```dart
import 'package:flutter/foundation.dart';

enum TpDateTimeRangeField { start, end }

@immutable
class TpDateTimeRange {
  const TpDateTimeRange({
    required this.start,
    required this.end,
    this.liveEnd = false,
  });

  final DateTime start;
  final DateTime end;
  final bool liveEnd;

  TpDateTimeRange copyWith({
    DateTime? start,
    DateTime? end,
    bool? liveEnd,
  }) {
    return TpDateTimeRange(
      start: start ?? this.start,
      end: end ?? this.end,
      liveEnd: liveEnd ?? this.liveEnd,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TpDateTimeRange &&
        other.start == start &&
        other.end == end &&
        other.liveEnd == liveEnd;
  }

  @override
  int get hashCode => Object.hash(start, end, liveEnd);
}

@immutable
class TpDateTimeRangePreset {
  const TpDateTimeRangePreset({required this.id, required this.label});

  final String id;
  final String label;
}

@immutable
class TpDateTimeRangePickerLabels {
  const TpDateTimeRangePickerLabels({
    this.start = 'Start time',
    this.end = 'End time',
    this.confirm = 'Confirm',
    this.cancel = 'Cancel',
    this.hint = 'Date and time, up to 30 days',
    this.liveEnd = 'End time follows now',
    this.invalidOrder = 'Start time cannot be later than end time',
    this.tooLong = 'Range cannot exceed 30 days',
  });

  final String start;
  final String end;
  final String confirm;
  final String cancel;
  final String hint;
  final String liveEnd;
  final String invalidOrder;
  final String tooLong;
}
```

- [ ] **Step 4: Implement the panel**

Create `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/tp_text_styles.dart';
import '../../theme/tokens/tp_control_metrics.dart';
import '../button/tp_button.dart';
import '../time_picker/tp_time_picker.dart';
import 'tp_calendar.dart';
import 'tp_date_time_range.dart';

class TpDateTimeRangePanel extends StatelessWidget {
  const TpDateTimeRangePanel({
    required this.start,
    required this.end,
    required this.activeField,
    required this.liveEnd,
    required this.presets,
    required this.selectedPresetId,
    required this.labels,
    required this.firstDate,
    required this.lastDate,
    required this.onActiveFieldChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onDateChanged,
    required this.onLiveEndChanged,
    required this.onPresetSelected,
    required this.onApply,
    required this.onCancel,
    this.error,
    super.key,
  });

  final DateTime start;
  final DateTime end;
  final TpDateTimeRangeField activeField;
  final bool liveEnd;
  final List<TpDateTimeRangePreset> presets;
  final String? selectedPresetId;
  final TpDateTimeRangePickerLabels labels;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<TpDateTimeRangeField> onActiveFieldChanged;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<bool> onLiveEndChanged;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback onApply;
  final VoidCallback onCancel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          labels.hint,
          style: styles.xs.copyWith(
            color: cs.onSurface.withValues(alpha: 0.56),
          ),
        ),
        const SizedBox(height: 8),
        _FieldCard(
          label: labels.start,
          date: start,
          active: activeField == TpDateTimeRangeField.start,
          enabled: true,
          onTap: () => onActiveFieldChanged(TpDateTimeRangeField.start),
          onTimeChanged: (time) => onStartChanged(
            DateTime(start.year, start.month, start.day, time.hour, time.minute),
          ),
        ),
        const SizedBox(height: 8),
        _FieldCard(
          label: labels.end,
          date: end,
          active: activeField == TpDateTimeRangeField.end,
          enabled: !liveEnd,
          onTap: () => onActiveFieldChanged(TpDateTimeRangeField.end),
          onTimeChanged: (time) => onEndChanged(
            DateTime(end.year, end.month, end.day, time.hour, time.minute),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => onLiveEndChanged(!liveEnd),
          child: Row(
            children: [
              IgnorePointer(
                child: Checkbox(
                  value: liveEnd,
                  onChanged: (_) {},
                ),
              ),
              Expanded(
                child: Text(
                  labels.liveEnd,
                  style: styles.xs.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error!, style: styles.xs.copyWith(color: cs.error)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TpButton(
                variant: TpButtonVariant.outline,
                size: TpControlSize.small,
                onPressed: onCancel,
                child: Text(labels.cancel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TpButton(
                size: TpControlSize.small,
                onPressed: onApply,
                child: Text(labels.confirm),
              ),
            ),
          ],
        ),
      ],
    );

    final calendar = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: TpCalendar(
        key: ValueKey(activeField),
        firstDate: firstDate,
        lastDate: lastDate,
        selected: activeField == TpDateTimeRangeField.start ? start : end,
        initialMonth: activeField == TpDateTimeRangeField.start ? start : end,
        allowDeselection: false,
        onChanged: (date) {
          if (date != null) onDateChanged(date);
        },
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presets.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in presets)
                TpButton(
                  variant: selectedPresetId == preset.id
                      ? TpButtonVariant.primary
                      : TpButtonVariant.outline,
                  size: TpControlSize.small,
                  onPressed: () => onPresetSelected(preset.id),
                  child: Text(preset.label),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fields,
                  const SizedBox(height: 10),
                  calendar,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: fields),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: calendar),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.label,
    required this.date,
    required this.active,
    required this.enabled,
    required this.onTap,
    required this.onTimeChanged,
  });

  final String label;
  final DateTime date;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<TimeOfDay> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: enabled ? cs.surface : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('yyyy/MM/dd').format(date),
                      style: styles.sm,
                    ),
                  ),
                  TpTimePicker(
                    initialValue: TimeOfDay.fromDateTime(date),
                    enabled: enabled,
                    onChanged: onTimeChanged,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Implement the picker**

Create `client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_picker.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../action_menu/tp_action_menu.dart';
import '../dialog/show_tp_dialog.dart';
import '../dialog/tp_dialog.dart';
import '../popover/tp_popover.dart';
import 'tp_date_time_range.dart';
import 'tp_date_time_range_panel.dart';

class TpDateTimeRangePicker extends StatefulWidget {
  const TpDateTimeRangePicker({
    required this.firstDate,
    required this.lastDate,
    required this.triggerBuilder,
    required this.labels,
    this.value,
    this.onChanged,
    this.maxDuration,
    this.presets = const [],
    this.selectedPresetId,
    this.onPresetSelected,
    this.panelWidth = 620,
    this.controller,
    super.key,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final Widget Function(BuildContext context, bool isOpen) triggerBuilder;
  final TpDateTimeRangePickerLabels labels;
  final TpDateTimeRange? value;
  final ValueChanged<TpDateTimeRange?>? onChanged;
  final Duration? maxDuration;
  final List<TpDateTimeRangePreset> presets;
  final String? selectedPresetId;
  final ValueChanged<String>? onPresetSelected;
  final double panelWidth;
  final TpPopoverController? controller;

  @override
  State<TpDateTimeRangePicker> createState() => _TpDateTimeRangePickerState();
}

class _TpDateTimeRangePickerState extends State<TpDateTimeRangePicker> {
  late final TpPopoverController _controller =
      widget.controller ?? TpPopoverController();
  late final bool _ownsController = widget.controller == null;

  late DateTime _draftStart;
  late DateTime _draftEnd;
  late bool _draftLiveEnd;
  TpDateTimeRangeField _activeField = TpDateTimeRangeField.start;
  String? _error;
  Timer? _liveTimer;

  TpDateTimeRange get _defaultValue {
    final now = DateTime.now();
    return TpDateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
  }

  @override
  void initState() {
    super.initState();
    _resetDraft();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _resetDraft() {
    final value = widget.value ?? _defaultValue;
    _draftStart = value.start;
    _draftEnd = value.end;
    _draftLiveEnd = value.liveEnd;
    _activeField = TpDateTimeRangeField.start;
    _error = null;
    _syncLiveTimer();
  }

  void _syncLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
    if (!_draftLiveEnd) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _draftEnd = DateTime.now());
    });
  }

  void _open() {
    _resetDraft();
    _controller.show();
  }

  void _close() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _controller.hide();
  }

  void _setActiveField(TpDateTimeRangeField field) {
    if (_draftLiveEnd && field == TpDateTimeRangeField.end) return;
    setState(() => _activeField = field);
  }

  void _setLiveEnd(bool live) {
    setState(() {
      _draftLiveEnd = live;
      if (live) {
        _draftEnd = DateTime.now();
        _activeField = TpDateTimeRangeField.start;
      }
      _error = null;
    });
    _syncLiveTimer();
  }

  void _setDate(DateTime day) {
    setState(() {
      final target = _activeField == TpDateTimeRangeField.start
          ? _draftStart
          : _draftEnd;
      final next = DateTime(
        day.year,
        day.month,
        day.day,
        target.hour,
        target.minute,
      );

      if (_activeField == TpDateTimeRangeField.start) {
        _draftStart = next;
        if (_draftStart.isAfter(_draftEnd)) {
          _draftEnd = DateTime(
            next.year,
            next.month,
            next.day,
            _draftEnd.hour,
            _draftEnd.minute,
          );
          if (_draftEnd.isBefore(_draftStart)) _draftEnd = _draftStart;
        }
        _activeField = TpDateTimeRangeField.end;
      } else if (next.isBefore(_draftStart)) {
        _draftStart = next;
        _activeField = TpDateTimeRangeField.end;
      } else {
        _draftEnd = next;
      }
      _error = null;
    });
  }

  void _setStart(DateTime value) {
    setState(() {
      _draftStart = value;
      _error = null;
    });
  }

  void _setEnd(DateTime value) {
    if (_draftLiveEnd) return;
    setState(() {
      _draftEnd = value;
      _error = null;
    });
  }

  String? _validate() {
    if (_draftStart.isAfter(_draftEnd)) return widget.labels.invalidOrder;
    final max = widget.maxDuration;
    if (max != null && _draftEnd.difference(_draftStart) > max) {
      return widget.labels.tooLong;
    }
    return null;
  }

  void _apply() {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onChanged?.call(
      TpDateTimeRange(
        start: _draftStart,
        end: _draftEnd,
        liveEnd: _draftLiveEnd,
      ),
    );
    _close();
  }

  void _presetSelected(String id) {
    widget.onPresetSelected?.call(id);
    _close();
  }

  Widget _panel({VoidCallback? onCancel}) {
    return TpDateTimeRangePanel(
      start: _draftStart,
      end: _draftEnd,
      activeField: _activeField,
      liveEnd: _draftLiveEnd,
      presets: widget.presets,
      selectedPresetId: widget.selectedPresetId,
      labels: widget.labels,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      error: _error,
      onActiveFieldChanged: _setActiveField,
      onStartChanged: _setStart,
      onEndChanged: _setEnd,
      onDateChanged: _setDate,
      onLiveEndChanged: _setLiveEnd,
      onPresetSelected: _presetSelected,
      onApply: _apply,
      onCancel: onCancel ?? _close,
    );
  }

  Future<void> _openDialog() async {
    _resetDraft();
    String? dialogError;
    final result = await showTpDialog<TpDateTimeRange>(
      context: context,
      maxWidth: 680,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return TpDialog(
              maxWidth: 680,
              scrollable: true,
              child: TpDateTimeRangePanel(
                start: _draftStart,
                end: _draftEnd,
                activeField: _activeField,
                liveEnd: _draftLiveEnd,
                presets: widget.presets,
                selectedPresetId: widget.selectedPresetId,
                labels: widget.labels,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                error: dialogError,
                onActiveFieldChanged: (field) {
                  _setActiveField(field);
                  setDialogState(() {});
                },
                onStartChanged: (value) {
                  _setStart(value);
                  setDialogState(() {});
                },
                onEndChanged: (value) {
                  _setEnd(value);
                  setDialogState(() {});
                },
                onDateChanged: (date) {
                  _setDate(date);
                  setDialogState(() {});
                },
                onLiveEndChanged: (live) {
                  _setLiveEnd(live);
                  setDialogState(() {});
                },
                onPresetSelected: (id) {
                  widget.onPresetSelected?.call(id);
                  Navigator.of(dialogContext).pop();
                },
                onApply: () {
                  final error = _validate();
                  if (error != null) {
                    setDialogState(() => dialogError = error);
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    TpDateTimeRange(
                      start: _draftStart,
                      end: _draftEnd,
                      liveEnd: _draftLiveEnd,
                    ),
                  );
                },
                onCancel: () => Navigator.of(dialogContext).pop(),
              ),
            );
          },
        );
      },
    );
    _liveTimer?.cancel();
    _liveTimer = null;
    if (result != null) widget.onChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    if (narrow) {
      return GestureDetector(
        onTap: _openDialog,
        behavior: HitTestBehavior.opaque,
        child: widget.triggerBuilder(context, false),
      );
    }

    final width = widget.panelWidth > MediaQuery.sizeOf(context).width - 32
        ? MediaQuery.sizeOf(context).width - 32
        : widget.panelWidth;

    return TpPopover(
      controller: _controller,
      panelWidth: width,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: TpActionMenuMetrics.panelDecoration(context),
      anchor: const TpAnchor(
        childAlignment: Alignment.topLeft,
        overlayAlignment: Alignment.bottomLeft,
        offset: Offset(0, 4),
      ),
      popover: (_) => _panel(),
      child: GestureDetector(
        onTap: _open,
        behavior: HitTestBehavior.opaque,
        child: widget.triggerBuilder(context, _controller.isOpen),
      ),
    );
  }
}
```

- [ ] **Step 6: Export the new files**

Modify `client/packages/shared_ui/lib/shared_ui.dart`:

```dart
export 'src/components/date_range/tp_date_time_range.dart';
export 'src/components/date_range/tp_date_time_range_panel.dart';
export 'src/components/date_range/tp_date_time_range_picker.dart';
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart
```

Expected: PASS. If `TpButton` inside `Wrap` overflows, wrap each preset in `SizedBox(height: 28)` and keep `TpControlSize.small`.

- [ ] **Step 8: Commit**

```bash
git add client/packages/shared_ui/lib/shared_ui.dart \
  client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range.dart \
  client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_panel.dart \
  client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_picker.dart \
  client/packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart
git commit -m "feat(shared_ui): add date-time range picker"
```

---

### Task 5: Persist table state in app settings

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart`
- Test: `client/test/repositories/app_settings_repository_test.dart`

**Interfaces:**
- Produces:
  - `Future<Map<String, dynamic>?> loadTableState(String tableId)`.
  - `Future<void> saveTableState(String tableId, Map<String, dynamic> state)`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/repositories/app_settings_repository_test.dart` inside `main()`:

```dart
  group('AppSettingsRepository.tableState', () {
    test('round-trips and isolates table ids', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      await repo.saveTableState('usage.detail', {
        'order': ['group', 'total'],
        'hidden': ['share'],
      });
      await repo.saveTableState('other.table', {
        'order': ['a'],
      });

      expect(await repo.loadTableState('usage.detail'), {
        'order': ['group', 'total'],
        'hidden': ['share'],
      });
      expect(await repo.loadTableState('other.table'), {
        'order': ['a'],
      });
    });

    test('returns null for missing tables', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadTableState('missing'), isNull);
    });

    test('returns null for corrupt table state', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsAppSettingsRepository.storageKey: jsonEncode({
          'tableStates': 'not a map',
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsAppSettingsRepository(prefs);

      expect(await repo.loadTableState('usage.detail'), isNull);
    });

    test('InMemory round-trips table state', () async {
      final repo = InMemoryAppSettingsRepository();
      await repo.saveTableState('usage.detail', {'order': ['total']});

      expect(await repo.loadTableState('usage.detail'), {
        'order': ['total'],
      });
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/repositories/app_settings_repository_test.dart
```

Expected: FAIL because `loadTableState` / `saveTableState` do not exist.

- [ ] **Step 3: Add the interface methods**

In `client/lib/repositories/app_settings_repository.dart`, add before `loadSkillsMpApiKey`:

```dart
  /// Persisted column order/visibility for a reusable table, keyed by table id.
  Future<Map<String, dynamic>?> loadTableState(String tableId);
  Future<void> saveTableState(String tableId, Map<String, dynamic> state);
```

- [ ] **Step 4: Implement in `SharedPrefsAppSettingsRepository`**

Add the key near the other static keys:

```dart
  static const _tableStatesKey = 'tableStates';
```

Add the implementation before `_writeMap`:

```dart
  @override
  Future<Map<String, dynamic>?> loadTableState(String tableId) async {
    final rawStates = _readMap()[_tableStatesKey];
    if (rawStates is! Map) return null;
    final raw = rawStates[tableId];
    if (raw is! Map) return null;
    try {
      return Map<String, dynamic>.from(raw);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveTableState(
    String tableId,
    Map<String, dynamic> state,
  ) async {
    final current = _readMap();
    final rawStates = current[_tableStatesKey];
    Map<String, Object?> states;
    try {
      states = rawStates is Map
          ? Map<String, Object?>.from(rawStates)
          : <String, Object?>{};
    } on Object {
      states = <String, Object?>{};
    }
    states[tableId] = state;
    current[_tableStatesKey] = states;
    await _writeMap(current);
  }
```

- [ ] **Step 5: Implement in `InMemoryAppSettingsRepository`**

Add the field:

```dart
  final Map<String, Map<String, dynamic>> _tableStates = {};
```

Add the methods before the closing brace:

```dart
  @override
  Future<Map<String, dynamic>?> loadTableState(String tableId) async {
    final state = _tableStates[tableId];
    return state == null ? null : Map<String, dynamic>.from(state);
  }

  @override
  Future<void> saveTableState(
    String tableId,
    Map<String, dynamic> state,
  ) async {
    _tableStates[tableId] = Map<String, dynamic>.from(state);
  }
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/repositories/app_settings_repository_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/repositories/app_settings_repository.dart \
  client/test/repositories/app_settings_repository_test.dart
git commit -m "feat(settings): persist table column state"
```

---

### Task 6: Usage range presets and custom bounds

**Files:**
- Modify: `client/lib/models/session_usage_dashboard.dart`
- Modify: `client/lib/services/usage/usage_aggregator.dart`
- Test: `client/test/services/usage/usage_aggregator_test.dart`

**Interfaces:**
- Produces:
  - `UsageRange.last24Hours`, `fourteenDays`, `custom`, `UsageRange.value`, `UsageRange.tryParse`.
  - `UsageFilter.customStartMs`, `customEndMs`, `liveEnd`; `copyWith(clearCustomRange:)`.
  - `usageRangeBounds({required UsageRange range, required int nowMs, int? customStartMs, int? customEndMs, bool liveEnd})`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/usage/usage_aggregator_test.dart` inside `main()`:

```dart
  test('last24Hours and fourteenDays use rolling/local windows', () {
    final events = [
      _event(
        id: 'eight-hours',
        timestampMs: DateTime(2026, 10, 26, 10).millisecondsSinceEpoch,
      ),
      _event(
        id: 'thirty-two-hours',
        timestampMs: DateTime(2026, 10, 25, 10).millisecondsSinceEpoch,
      ),
      _event(
        id: 'ten-days',
        timestampMs: DateTime(2026, 10, 16, 10).millisecondsSinceEpoch,
      ),
    ];

    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.last24Hours),
      ).summary.requests,
      1,
    );
    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.fourteenDays),
      ).summary.requests,
      3,
    );
  });

  test('custom range filters both ends', () {
    final events = [
      _event(
        id: 'inside',
        timestampMs: DateTime(2026, 10, 25, 12).millisecondsSinceEpoch,
      ),
      _event(
        id: 'outside',
        timestampMs: DateTime(2026, 10, 24, 12).millisecondsSinceEpoch,
      ),
    ];

    final dashboard = _build(
      events,
      filter: UsageFilter(
        range: UsageRange.custom,
        customStartMs: DateTime(2026, 10, 25).millisecondsSinceEpoch,
        customEndMs: DateTime(2026, 10, 26).millisecondsSinceEpoch,
      ),
    );

    expect(dashboard.summary.requests, 1);
  });

  test('custom live end uses now as the end bound', () {
    final events = [
      _event(
        id: 'now',
        timestampMs: DateTime(2026, 10, 26, 18).millisecondsSinceEpoch,
      ),
    ];

    final dashboard = _build(
      events,
      filter: UsageFilter(
        range: UsageRange.custom,
        customStartMs: DateTime(2026, 10, 26).millisecondsSinceEpoch,
        customEndMs: DateTime(2026, 10, 26, 10).millisecondsSinceEpoch,
        liveEnd: true,
      ),
    );

    expect(dashboard.summary.requests, 1);
  });

  test('custom without both bounds falls back to all', () {
    final events = [
      _event(id: 'old', timestampMs: DateTime(2020).millisecondsSinceEpoch),
    ];

    expect(
      _build(
        events,
        filter: const UsageFilter(range: UsageRange.custom),
      ).summary.requests,
      1,
    );
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart
```

Expected: FAIL because the new enum values and fields do not exist.

- [ ] **Step 3: Extend the enum and filter**

In `client/lib/models/session_usage_dashboard.dart`, replace:

```dart
enum UsageRange { today, sevenDays, thirtyDays, all }
```

with:

```dart
enum UsageRange {
  today('today'),
  last24Hours('last24Hours'),
  sevenDays('sevenDays'),
  fourteenDays('fourteenDays'),
  thirtyDays('thirtyDays'),
  all('all'),
  custom('custom');

  const UsageRange(this.value);

  final String value;

  static UsageRange? tryParse(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final range in UsageRange.values) {
      if (range.value == normalized) return range;
    }
    return null;
  }
}
```

In `UsageFilter`, add fields:

```dart
    this.customStartMs,
    this.customEndMs,
    this.liveEnd = false,
```

```dart
  final int? customStartMs;
  final int? customEndMs;
  final bool liveEnd;
```

Extend `copyWith`:

```dart
  UsageFilter copyWith({
    UsageRange? range,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
    int? customStartMs,
    int? customEndMs,
    bool clearCustomRange = false,
    bool? liveEnd,
  }) {
    return UsageFilter(
      range: range ?? this.range,
      cli: clearCli ? null : (cli ?? this.cli),
      groupBy: groupBy ?? this.groupBy,
      query: query ?? this.query,
      customStartMs: clearCustomRange
          ? null
          : (customStartMs ?? this.customStartMs),
      customEndMs: clearCustomRange ? null : (customEndMs ?? this.customEndMs),
      liveEnd: liveEnd ?? this.liveEnd,
    );
  }
```

Extend `props`:

```dart
  List<Object?> get props => [
    range,
    cli,
    groupBy,
    query,
    customStartMs,
    customEndMs,
    liveEnd,
  ];
```

- [ ] **Step 4: Implement bounds in the aggregator**

In `client/lib/services/usage/usage_aggregator.dart`, replace `usageRangeStartMs` with:

```dart
/// Inclusive start/end bounds for a range selection.
///
/// A null bound means unbounded on that side. A custom range missing either
/// endpoint falls back to all-time so a dirty filter cannot empty the table.
({int? startMs, int? endMs}) usageRangeBounds({
  required UsageRange range,
  required int nowMs,
  int? customStartMs,
  int? customEndMs,
  bool liveEnd = false,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    UsageRange.today => (
      startMs: today.millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.last24Hours => (
      startMs: nowMs - const Duration(hours: 24).inMilliseconds,
      endMs: null,
    ),
    UsageRange.sevenDays => (
      startMs: today.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.fourteenDays => (
      startMs: today.subtract(const Duration(days: 13)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.thirtyDays => (
      startMs: today.subtract(const Duration(days: 29)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.all => (startMs: null, endMs: null),
    UsageRange.custom => customStartMs == null || customEndMs == null
        ? (startMs: null, endMs: null)
        : (
            startMs: customStartMs,
            endMs: liveEnd ? nowMs : customEndMs,
          ),
  };
}

/// Kept for callers that only need the start boundary.
int? usageRangeStartMs(UsageRange range, int nowMs) {
  return usageRangeBounds(range: range, nowMs: nowMs).startMs;
}
```

In `buildUsageDashboard`, replace:

```dart
  final rangeStart = usageRangeStartMs(filter.range, nowMs);
  final scoped = events
      .where((event) {
        if (rangeStart != null && event.timestampMs < rangeStart) return false;
        if (filter.cli != null && event.cli != filter.cli) return false;
        return true;
      })
      .toList(growable: false);
```

with:

```dart
  final bounds = usageRangeBounds(
    range: filter.range,
    nowMs: nowMs,
    customStartMs: filter.customStartMs,
    customEndMs: filter.customEndMs,
    liveEnd: filter.liveEnd,
  );
  final scoped = events
      .where((event) {
        if (bounds.startMs != null && event.timestampMs < bounds.startMs!) {
          return false;
        }
        if (bounds.endMs != null && event.timestampMs > bounds.endMs!) {
          return false;
        }
        if (filter.cli != null && event.cli != filter.cli) return false;
        return true;
      })
      .toList(growable: false);
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/services/usage/usage_aggregator_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/session_usage_dashboard.dart \
  client/lib/services/usage/usage_aggregator.dart \
  client/test/services/usage/usage_aggregator_test.dart
git commit -m "feat(usage): add 24h/14d/custom range bounds"
```

---

### Task 7: Cubit custom range and live end

**Files:**
- Modify: `client/lib/cubits/session_usage_cubit.dart`
- Test: `client/test/cubits/session_usage_cubit_test.dart`

**Interfaces:**
- Produces:
  - `SessionUsageState.customStartMs`, `customEndMs`, `liveEnd`.
  - `setCustomRange({required int startMs, required int endMs, bool liveEnd = false})`.
  - `setLiveEnd(bool value)`.
  - `refreshRangeNow()`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/cubits/session_usage_cubit_test.dart` inside `main()`:

```dart
  test('custom range filters events and clears when switching presets', () async {
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(
          id: 'recent',
          timestampMs: DateTime(2026, 10, 26, 12).millisecondsSinceEpoch,
        ),
        _event(
          id: 'old',
          timestampMs: DateTime(2026, 10, 20, 12).millisecondsSinceEpoch,
        ),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => DateTime(2026, 10, 26, 18),
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    expect(cubit.state.dashboard.summary.requests, 2);

    cubit.setCustomRange(
      startMs: DateTime(2026, 10, 25).millisecondsSinceEpoch,
      endMs: DateTime(2026, 10, 26, 18).millisecondsSinceEpoch,
    );
    expect(cubit.state.range, UsageRange.custom);
    expect(cubit.state.dashboard.summary.requests, 1);

    cubit.setRange(UsageRange.all);
    expect(cubit.state.range, UsageRange.all);
    expect(cubit.state.customStartMs, isNull);
    expect(cubit.state.customEndMs, isNull);
    expect(cubit.state.liveEnd, isFalse);
    expect(cubit.state.dashboard.summary.requests, 2);
  });

  test('live end uses now on refresh', () async {
    var now = DateTime(2026, 10, 26, 12);
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(
          id: 'later',
          timestampMs: DateTime(2026, 10, 26, 13).millisecondsSinceEpoch,
        ),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      now: () => now,
    );
    addTearDown(cubit.close);

    await cubit.ensureLoaded();
    cubit.setCustomRange(
      startMs: DateTime(2026, 10, 26).millisecondsSinceEpoch,
      endMs: DateTime(2026, 10, 26, 12).millisecondsSinceEpoch,
      liveEnd: true,
    );
    expect(cubit.state.dashboard.summary.requests, 0);

    now = DateTime(2026, 10, 26, 14);
    cubit.refreshRangeNow();
    expect(cubit.state.dashboard.summary.requests, 1);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/cubits/session_usage_cubit_test.dart
```

Expected: FAIL because the new state fields and methods do not exist.

- [ ] **Step 3: Add state fields and copyWith**

In `SessionUsageState` constructor add:

```dart
    this.customStartMs,
    this.customEndMs,
    this.liveEnd = false,
```

Add fields after `range`:

```dart
  final int? customStartMs;
  final int? customEndMs;
  final bool liveEnd;
```

Add `copyWith` parameters:

```dart
    int? customStartMs,
    int? customEndMs,
    bool clearCustomRange = false,
    bool? liveEnd,
```

Pass them in the constructor call:

```dart
      customStartMs: clearCustomRange
          ? null
          : (customStartMs ?? this.customStartMs),
      customEndMs: clearCustomRange
          ? null
          : (customEndMs ?? this.customEndMs),
      liveEnd: liveEnd ?? this.liveEnd,
```

Add to `props` after `range`:

```dart
    customStartMs,
    customEndMs,
    liveEnd,
```

- [ ] **Step 4: Add cubit methods**

Replace `setRange`, `setCli`, `setGroupBy`, `setQuery` block with:

```dart
  void setRange(UsageRange range) {
    _updateFilter(
      range: range,
      clearCustomRange: true,
      liveEnd: false,
    );
  }

  void setCustomRange({
    required int startMs,
    required int endMs,
    bool liveEnd = false,
  }) {
    _updateFilter(
      range: UsageRange.custom,
      customStartMs: startMs,
      customEndMs: endMs,
      liveEnd: liveEnd,
    );
  }

  void setLiveEnd(bool value) => _updateFilter(liveEnd: value);

  void refreshRangeNow() {
    if (!state.liveEnd) return;
    emit(state.copyWith(dashboard: _computeDashboard()));
  }

  void setCli(CliTool? cli) => _updateFilter(cli: cli, clearCli: cli == null);

  void setGroupBy(UsageGroupBy groupBy) => _updateFilter(groupBy: groupBy);

  void setQuery(String query) => _updateFilter(query: query);
```

Update `resetFilters`:

```dart
  void resetFilters() {
    _updateFilter(
      range: UsageRange.all,
      cli: null,
      clearCli: true,
      groupBy: UsageGroupBy.session,
      query: '',
      clearCustomRange: true,
      liveEnd: false,
    );
  }
```

Extend `_updateFilter` signature:

```dart
  void _updateFilter({
    UsageRange? range,
    CliTool? cli,
    bool clearCli = false,
    UsageGroupBy? groupBy,
    String? query,
    int? customStartMs,
    int? customEndMs,
    bool clearCustomRange = false,
    bool? liveEnd,
  }) {
    final next = state.copyWith(
      range: range,
      cli: cli,
      clearCli: clearCli,
      groupBy: groupBy,
      query: query,
      customStartMs: customStartMs,
      customEndMs: customEndMs,
      clearCustomRange: clearCustomRange,
      liveEnd: liveEnd,
    );
    emit(next.copyWith(dashboard: _computeDashboard(next)));
  }
```

Update `_computeDashboard`'s `UsageFilter`:

```dart
      filter: UsageFilter(
        range: current.range,
        cli: current.cli,
        groupBy: current.groupBy,
        query: current.query,
        customStartMs: current.customStartMs,
        customEndMs: current.customEndMs,
        liveEnd: current.liveEnd,
      ),
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/cubits/session_usage_cubit_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session_usage_cubit.dart \
  client/test/cubits/session_usage_cubit_test.dart
git commit -m "feat(usage): support custom ranges in the cubit"
```

---

### Task 8: Usage l10n keys and range labels

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/usage/usage_format.dart`
- Test: `client/test/pages/usage/usage_format_test.dart`

**Interfaces:**
- Produces: `usageRangeLabel(BuildContext context, UsageRange range)`.

- [ ] **Step 1: Write the failing test**

Add these imports to `client/test/pages/usage/usage_format_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
```

Append to the same file:

```dart
  testWidgets('range labels cover all presets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            expect(
              usageRangeLabel(context, UsageRange.last24Hours),
              'Last 24 hours',
            );
            expect(
              usageRangeLabel(context, UsageRange.fourteenDays),
              'Last 14 days',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_format_test.dart
```

Expected: FAIL because `usageRangeLabel` does not exist.

- [ ] **Step 3: Add the ARB keys**

In `client/lib/l10n/app_en.arb`, next to the existing range keys, add:

```json
  "sessionUsageRangeLast24Hours": "Last 24 hours",
  "sessionUsageRangeFourteenDays": "Last 14 days",
  "sessionUsageStartTime": "Start time",
  "sessionUsageEndTime": "End time",
  "sessionUsageLiveEnd": "End time follows now",
  "sessionUsageRangeHint": "Date and time, up to 30 days",
  "sessionUsageRangeInvalidOrder": "Start time cannot be later than end time",
  "sessionUsageRangeTooLong": "Range cannot exceed 30 days",
  "sessionUsageColumnSettings": "Columns",
  "sessionUsageColumnReset": "Reset to default",
  "sessionUsageSortDescending": "Sort descending",
  "sessionUsageSortAscending": "Sort ascending",
```

In `client/lib/l10n/app_zh.arb`, add:

```json
  "sessionUsageRangeLast24Hours": "近 24 小时",
  "sessionUsageRangeFourteenDays": "近 14 天",
  "sessionUsageStartTime": "开始时间",
  "sessionUsageEndTime": "结束时间",
  "sessionUsageLiveEnd": "结束时间跟随当前时刻",
  "sessionUsageRangeHint": "支持日期与时间，最长 30 天",
  "sessionUsageRangeInvalidOrder": "开始时间不能晚于结束时间",
  "sessionUsageRangeTooLong": "时间范围不能超过 30 天",
  "sessionUsageColumnSettings": "显示的列",
  "sessionUsageColumnReset": "恢复默认",
  "sessionUsageSortDescending": "降序",
  "sessionUsageSortAscending": "升序",
```

- [ ] **Step 4: Generate localizations**

```bash
cd client && flutter gen-l10n
```

Expected: `lib/l10n/app_localizations*.dart` regenerated with the new getters.

- [ ] **Step 5: Add `usageRangeLabel`**

In `client/lib/pages/usage/usage_format.dart`, add:

```dart
String usageRangeLabel(BuildContext context, UsageRange range) {
  final l10n = context.l10n;
  return switch (range) {
    UsageRange.today => l10n.sessionUsageRangeToday,
    UsageRange.last24Hours => l10n.sessionUsageRangeLast24Hours,
    UsageRange.sevenDays => l10n.sessionUsageRangeSevenDays,
    UsageRange.fourteenDays => l10n.sessionUsageRangeFourteenDays,
    UsageRange.thirtyDays => l10n.sessionUsageRangeThirtyDays,
    UsageRange.all => l10n.sessionUsageRangeAll,
    UsageRange.custom => l10n.sessionUsageRangeAll,
  };
}
```

For `custom`, the trigger uses a formatted date string, so this fallback is only a safety net.

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_format_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/pages/usage/usage_format.dart \
  client/test/pages/usage/usage_format_test.dart
git commit -m "feat(usage): add range and table l10n keys"
```

---

### Task 9: Usage table columns and sorting

**Files:**
- Create: `client/lib/pages/usage/widgets/usage_table_columns.dart`
- Test: `client/test/pages/usage/usage_table_columns_test.dart`

**Interfaces:**
- Consumes: `TpTableColumn`, `TpTableSort`, `UsageGroup`, `UsageSummary`.
- Produces:
  - `const String usageGroupColumnId = 'group'`.
  - `List<TpTableColumn<UsageGroup>> buildUsageTableColumns({required BuildContext context, required UsageSummary summary, required UsageGroupBy groupBy})`.
  - `List<UsageGroup> sortUsageRows(List<UsageGroup> rows, TpTableSort? sort, List<TpTableColumn<UsageGroup>> columns)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/usage/usage_table_columns_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_table_columns_test.dart
```

Expected: FAIL because the file does not exist.

- [ ] **Step 3: Implement the columns**

Create `client/lib/pages/usage/widgets/usage_table_columns.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../models/team_config.dart';
import '../usage_format.dart';

const String usageGroupColumnId = 'group';
const String usageTotalColumnId = 'total';

List<TpTableColumn<UsageGroup>> buildUsageTableColumns({
  required BuildContext context,
  required UsageSummary summary,
  required UsageGroupBy groupBy,
}) {
  final l10n = context.l10n;

  return [
    TpTableColumn<UsageGroup>(
      id: usageGroupColumnId,
      label: usageGroupLabel(context, groupBy),
      flex: 3,
      minWidth: 240,
      locked: true,
      hideable: false,
      draggable: false,
      sortValue: (row) => row.label.toLowerCase(),
      cellBuilder: (context, row) => _GroupCell(row: row),
    ),
    _numberColumn(
      id: usageTotalColumnId,
      label: l10n.sessionUsageTotalShort,
      width: 100,
      value: (row) => row.totalTokens,
    ),
    _numberColumn(
      id: 'input',
      label: l10n.sessionUsageInputShort,
      width: 90,
      value: (row) => row.freshInputTokens,
    ),
    _numberColumn(
      id: 'output',
      label: l10n.sessionUsageOutputShort,
      width: 90,
      value: (row) => row.outputTokens,
    ),
    _numberColumn(
      id: 'cache',
      label: l10n.sessionUsageCacheShort,
      width: 100,
      value: (row) => row.cacheReadTokens,
    ),
    TpTableColumn<UsageGroup>(
      id: 'cost',
      label: l10n.sessionUsageCostShort,
      width: 110,
      groupStart: true,
      sortValue: (row) => row.costMicroUsd,
      cellBuilder: (context, row) => _CostCell(row: row),
    ),
    _numberColumn(
      id: 'requests',
      label: l10n.sessionUsageRequestsShort,
      width: 80,
      value: (row) => row.requests,
    ),
    _numberColumn(
      id: 'sessions',
      label: l10n.sessionUsageSessionsShort,
      width: 90,
      value: (row) => row.sessions,
    ),
    TpTableColumn<UsageGroup>(
      id: 'share',
      label: l10n.sessionUsageShareShort,
      width: 120,
      groupStart: true,
      sortValue: (row) => row.totalTokens,
      cellBuilder: (context, row) => _ShareCell(
        totalTokens: row.totalTokens,
        summaryTotal: summary.totalTokens,
      ),
    ),
  ];
}

TpTableColumn<UsageGroup> _numberColumn({
  required String id,
  required String label,
  required double width,
  required int Function(UsageGroup row) value,
}) {
  return TpTableColumn<UsageGroup>(
    id: id,
    label: label,
    width: width,
    sortValue: (row) => value(row),
    cellBuilder: (context, row) => _NumberText(text: formatUsageTokens(value(row))),
  );
}

List<UsageGroup> sortUsageRows(
  List<UsageGroup> rows,
  TpTableSort? sort,
  List<TpTableColumn<UsageGroup>> columns,
) {
  if (sort == null || rows.isEmpty) return rows;
  final column = columns.where((item) => item.id == sort.columnId).firstOrNull;
  final sortValue = column?.sortValue;
  if (sortValue == null) return rows;

  final indexed = rows.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final left = sortValue(a.$2);
    final right = sortValue(b.$2);
    int result;
    if (left == null && right == null) {
      result = 0;
    } else if (left == null) {
      result = 1;
    } else if (right == null) {
      result = -1;
    } else {
      result = left.compareTo(right);
    }
    if (!sort.ascending) result = -result;
    if (result != 0) return result;
    return a.$1.compareTo(b.$1);
  });

  return [for (final entry in indexed) entry.$2];
}

class _NumberText extends StatelessWidget {
  const _NumberText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = TpTextStyles.of(context).sm.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

class _GroupCell extends StatelessWidget {
  const _GroupCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final cli = CliTool.tryParse(row.label);
    final label = cli == null ? usageGroupName(context, row) : usageCliLabel(cli);
    final subtitle = usageGroupSubtitle(context, row.subtitle);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.smMedium,
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tool in row.clis)
              if (cli == null) _CliBadge(cli: tool),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CliBadge extends StatelessWidget {
  const _CliBadge({required this.cli});

  final CliTool cli;

  @override
  Widget build(BuildContext context) {
    final color = usageCliColor(cli);
    final styles = TpTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        usageCliLabel(cli),
        style: styles.xs.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _CostCell extends StatelessWidget {
  const _CostCell({required this.row});

  final UsageGroup row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = row.pricedEvents == 0
        ? l10n.sessionUsageCostUnpriced
        : '${formatUsageCost(row.costMicroUsd)}'
              '${row.unpricedEvents > 0 ? '*' : ''}';
    final style = TpTextStyles.of(context).sm.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text(text, maxLines: 1, style: style);
  }
}

class _ShareCell extends StatelessWidget {
  const _ShareCell({required this.totalTokens, required this.summaryTotal});

  final int totalTokens;
  final int summaryTotal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final share = summaryTotal == 0 ? 0.0 : totalTokens / summaryTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatUsagePercent(share),
          style: styles.smMedium.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 4,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ),
      ],
    );
  }
}
```

`firstOrNull` comes from `package:collection` (already a client dependency). Add `import 'package:collection/collection.dart';` at the top.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_table_columns_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/usage/widgets/usage_table_columns.dart \
  client/test/pages/usage/usage_table_columns_test.dart
git commit -m "feat(usage): define sortable table columns"
```

---

### Task 10: Usage table toolbar, pagination, and detail table

**Files:**
- Create: `client/lib/pages/usage/widgets/usage_table_toolbar.dart`
- Create: `client/lib/pages/usage/widgets/usage_table_pagination.dart`
- Modify: `client/lib/pages/usage/widgets/usage_detail_table.dart`
- Test: `client/test/pages/usage/usage_detail_table_test.dart`

**Interfaces:**
- Consumes: `TpDataTable`, `TpTableColumnMenu`, `buildUsageTableColumns`, `sortUsageRows`, `AppSettingsRepository`.
- Produces:
  - `UsageTableToolbar`.
  - `UsageTablePagination`.
  - `UsageDetailTable` (same constructor as today, now backed by `TpDataTable`).

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/usage/usage_detail_table_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/usage/widgets/usage_detail_table.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/usage/usage_aggregator.dart';

UsageDashboard _dashboard() {
  final now = DateTime(2026, 10, 26, 12).millisecondsSinceEpoch;
  final events = [
    SessionUsageEvent(
      requestId: 'r1',
      cli: CliTool.claude,
      model: 'sonnet',
      inputTokens: 10,
      outputTokens: 2,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: now,
      sessionId: 's1',
    ),
    SessionUsageEvent(
      requestId: 'r2',
      cli: CliTool.codex,
      model: 'gpt',
      inputTokens: 100,
      outputTokens: 20,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: now,
      sessionId: 's2',
    ),
  ];
  return buildUsageDashboard(
    events: events,
    attribution: const UsageAttribution(
      sessionTitles: {'s1': 'Alpha', 's2': 'Beta'},
    ),
    filter: const UsageFilter(),
    nowMs: now,
  );
}

Widget _wrap({
  required UsageDashboard dashboard,
  required AppSettingsRepository repository,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RepositoryProvider<AppSettingsRepository>.value(
      value: repository,
      child: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.indigo),
          scale: 1,
        ),
        child: Scaffold(
          body: UsageDetailTable(
            dashboard: dashboard,
            groupBy: UsageGroupBy.session,
            searchController: TextEditingController(),
            onQueryChanged: (_) {},
            onGroupByChanged: (_) {},
            onResetFilters: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders group controls in the table card', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sessions'), findsNothing);
    expect(find.textContaining('Group by'), findsOneWidget);
  });

  testWidgets('hiding a column persists and removes its header', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryAppSettingsRepository();
    await tester.pumpWidget(
      _wrap(dashboard: _dashboard(), repository: repository),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<UsageGroup>),
        matching: find.text('Share'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TpTableHeader<UsageGroup>),
        matching: find.text('Share'),
      ),
      findsNothing,
    );
    final saved = await repository.loadTableState('usage.detail');
    expect(saved?['hidden'], contains('share'));
  });

  testWidgets('clicking the total header reverses row order', (tester) async {
    tester.view.physicalSize = const Size(1300, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        dashboard: _dashboard(),
        repository: InMemoryAppSettingsRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_detail_table_test.dart
```

Expected: FAIL because the table still uses the old `_PaginationBar` and has no column menu.

- [ ] **Step 3: Extract the pagination bar**

Create `client/lib/pages/usage/widgets/usage_table_pagination.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../utils/ui/app_keys.dart';

class UsageTablePagination extends StatelessWidget {
  const UsageTablePagination({
    required this.page,
    required this.pageCount,
    required this.start,
    required this.end,
    required this.total,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.onPageSizeChanged,
    required this.onPrev,
    required this.onNext,
    super.key,
  });

  final int page;
  final int pageCount;
  final int start;
  final int end;
  final int total;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final muted = styles.xs.copyWith(
      color: cs.onSurface.withValues(alpha: 0.56),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            l10n.sessionUsagePageRange(start + 1, end, total),
            key: AppKeys.sessionUsagePageRange,
            style: muted,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              Text(l10n.sessionUsageRowsPerPage, style: muted),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: AppKeys.sessionUsagePageSize,
                  value: pageSize,
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  style: styles.xs.copyWith(color: cs.onSurface),
                  items: [
                    for (final size in pageSizeOptions)
                      DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: (value) {
                    if (value != null) onPageSizeChanged(value);
                  },
                ),
              ),
              IconButton(
                key: AppKeys.sessionUsagePrevPage,
                tooltip: l10n.sessionUsagePrevPage,
                onPressed: onPrev,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(l10n.sessionUsagePageOf(page + 1, pageCount), style: muted),
              IconButton(
                key: AppKeys.sessionUsageNextPage,
                tooltip: l10n.sessionUsageNextPage,
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create the table toolbar**

Create `client/lib/pages/usage/widgets/usage_table_toolbar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

class UsageTableToolbar extends StatelessWidget {
  const UsageTableToolbar({
    required this.groupBy,
    required this.groupLabel,
    required this.count,
    required this.searchController,
    required this.onQueryChanged,
    required this.onGroupByChanged,
    required this.columns,
    required this.tableState,
    required this.onTableStateChanged,
    required this.labels,
    super.key,
  });

  final UsageGroupBy groupBy;
  final String groupLabel;
  final int count;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UsageGroupBy> onGroupByChanged;
  final List<TpTableColumn<UsageGroup>> columns;
  final TpTableState tableState;
  final ValueChanged<TpTableState> onTableStateChanged;
  final TpDataTableLabels labels;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    final search = TextField(
      key: AppKeys.sessionUsageSearchField,
      controller: searchController,
      onChanged: onQueryChanged,
      style: styles.sm,
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.sessionUsageSearchHint,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: context.l10n.sessionUsageResetFilters,
                iconSize: 18,
                onPressed: () {
                  searchController.clear();
                  onQueryChanged('');
                },
                icon: const Icon(Icons.close),
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );

    final groupControls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sessionUsageGroupCount(count),
          style: styles.mdBold,
        ),
        const SizedBox(height: 2),
        Text(
          '${context.l10n.sessionUsageGroupBy} · $groupLabel',
          style: styles.xs.copyWith(
            color: cs.onSurface.withValues(alpha: 0.56),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: TpSegmentedControl(
            totalSwitches: UsageGroupBy.values.length,
            initialLabelIndex: UsageGroupBy.values.indexOf(groupBy),
            labels: [
              for (final group in UsageGroupBy.values)
                usageGroupLabel(context, group),
            ],
            variant: TpSegmentedControlVariant.outlined,
            minHeight: 28,
            onToggle: (index) {
              if (index == null) return;
              onGroupByChanged(UsageGroupBy.values[index]);
            },
          ),
        ),
      ],
    );

    final columnMenu = TpTableColumnMenu<UsageGroup>(
      columns: columns,
      state: tableState,
      onChanged: onTableStateChanged,
      labels: labels,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              groupControls,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  columnMenu,
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: groupControls),
            const SizedBox(width: 12),
            SizedBox(width: 240, child: search),
            const SizedBox(width: 8),
            columnMenu,
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Rewrite the detail table**

Replace `client/lib/pages/usage/widgets/usage_detail_table.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../repositories/app_settings_repository.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';
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
    );

    return Container(
      key: AppKeys.sessionUsageTable,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
        labels: labels,
        toolbar: UsageTableToolbar(
          groupBy: widget.groupBy,
          groupLabel: usageGroupLabel(context, widget.groupBy),
          count: dashboard.rows.length,
          searchController: widget.searchController,
          onQueryChanged: widget.onQueryChanged,
          onGroupByChanged: widget.onGroupByChanged,
          columns: columns,
          tableState: _tableState,
          onTableStateChanged: _onStateChanged,
          labels: labels,
        ),
        footer: showPager
            ? UsageTablePagination(
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
              )
            : null,
        emptyState: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.sessionUsageTableEmpty),
              const SizedBox(height: 4),
              Text(
                l10n.sessionUsageTableEmptyHint,
                style: TpTextStyles.of(context).xs.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
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
```

`UsageDetailTable` already accepts `onGroupByChanged`; the toolbar uses `widget.onGroupByChanged`. Do not import `session_usage_cubit.dart` in this file.

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/usage_detail_table_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/usage/widgets/usage_table_toolbar.dart \
  client/lib/pages/usage/widgets/usage_table_pagination.dart \
  client/lib/pages/usage/widgets/usage_detail_table.dart \
  client/test/pages/usage/usage_detail_table_test.dart
git commit -m "feat(usage): replace detail table with TpDataTable"
```

---

### Task 11: Filter bar, date range wrapper, and page wiring

**Files:**
- Create: `client/lib/pages/usage/widgets/usage_filter_bar.dart`
- Create: `client/lib/pages/usage/widgets/usage_date_range_picker.dart`
- Modify: `client/lib/pages/usage/session_usage_page.dart`
- Modify: `client/lib/pages/usage/widgets/usage_page_chrome.dart`
- Test: `client/test/pages/usage/session_usage_page_test.dart`

**Interfaces:**
- Consumes: `TpDateTimeRangePicker`, `UsageRange`, `usageRangeBounds`, `CliBrandIcon`.
- Produces: `UsageFilterBar`, `UsageDateRangePicker`; removes `UsageToolbar`.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/usage/session_usage_page_test.dart`, replace the test `range, CLI, and group chips update the cubit` with:

```dart
  testWidgets('range picker, CLI icons, and group control update the cubit', (
    tester,
  ) async {
    _useTallViewport(tester);
    final cubit = SessionUsageCubit(
      loadEvents: () async => [
        _event(),
        _event(id: 'r2', sessionId: 's2', cli: CliTool.codex, input: 20),
      ],
      syncAll: () async => const UsageSyncResult(),
      loadSessions: () async => [
        _session('s1', 'Alpha'),
        _session('s2', 'Beta'),
      ],
      loadTeams: () async => const <TeamProfile>[],
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.sessionUsageRangeTrigger));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(cubit.state.range, UsageRange.sevenDays);

    await tester.tap(find.byTooltip('Codex'));
    await tester.pumpAndSettle();
    expect(cubit.state.cli, CliTool.codex);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(UsageTableToolbar),
        matching: find.text('Model'),
      ),
    );
    await tester.pumpAndSettle();
    expect(cubit.state.groupBy, UsageGroupBy.model);
  });
```

Add imports:

```dart
import 'package:teampilot/pages/usage/widgets/usage_table_toolbar.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/session_usage_page_test.dart
```

Expected: FAIL because the range trigger key and new filter bar do not exist.

- [ ] **Step 3: Add the range trigger key and implement the filter bar**

In `client/lib/utils/ui/app_keys.dart`, next to `sessionUsageSearchField`, add:

```dart
  static const sessionUsageRangeTrigger = Key('session-usage-range-trigger');
```

Create `client/lib/pages/usage/widgets/usage_filter_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../cubits/session_usage_cubit.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../usage_format.dart';
import 'usage_date_range_picker.dart';

class UsageFilterBar extends StatelessWidget {
  const UsageFilterBar({
    required this.state,
    required this.cubit,
    super.key,
  });

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        UsageDateRangePicker(state: state, cubit: cubit),
        Container(width: 1, height: 20, color: cs.outlineVariant),
        _CliFilter(state: state, cubit: cubit),
      ],
    );
  }
}

class _CliFilter extends StatelessWidget {
  const _CliFilter({required this.state, required this.cubit});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _CliButton(
          label: context.l10n.sessionUsageCliAll,
          selected: state.cli == null,
          onTap: () => cubit.setCli(null),
        ),
        for (final cli in CliTool.values)
          Tooltip(
            message: usageCliLabel(cli),
            waitDuration: const Duration(milliseconds: 500),
            child: _CliButton(
              selected: state.cli == cli,
              onTap: () => cubit.setCli(cli),
              icon: CliBrandIcon(
                cli: cli,
                size: 18,
                borderRadius: 4,
                showBorder: false,
              ),
            ),
          ),
      ],
    );
  }
}

class _CliButton extends StatelessWidget {
  const _CliButton({
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  });

  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Material(
      color: selected ? cs.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: label == null
                ? icon
                : Text(
                    label!,
                    style: styles.xs.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement the date range wrapper**

Create `client/lib/pages/usage/widgets/usage_date_range_picker.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/session_usage_dashboard.dart';
import '../../../services/usage/usage_aggregator.dart';
import '../../../utils/ui/app_keys.dart';
import '../usage_format.dart';

const _usageRangePresets = <UsageRange>[
  UsageRange.today,
  UsageRange.last24Hours,
  UsageRange.sevenDays,
  UsageRange.fourteenDays,
  UsageRange.thirtyDays,
  UsageRange.all,
];

class UsageDateRangePicker extends StatelessWidget {
  const UsageDateRangePicker({
    required this.state,
    required this.cubit,
    super.key,
  });

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final value = _valueFor(state, now);
    final labels = TpDateTimeRangePickerLabels(
      start: l10n.sessionUsageStartTime,
      end: l10n.sessionUsageEndTime,
      confirm: l10n.confirm,
      cancel: l10n.cancel,
      hint: l10n.sessionUsageRangeHint,
      liveEnd: l10n.sessionUsageLiveEnd,
      invalidOrder: l10n.sessionUsageRangeInvalidOrder,
      tooLong: l10n.sessionUsageRangeTooLong,
    );

    return TpDateTimeRangePicker(
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 1)),
      value: value,
      maxDuration: const Duration(days: 30),
      labels: labels,
      presets: [
        for (final range in _usageRangePresets)
          TpDateTimeRangePreset(
            id: range.value,
            label: usageRangeLabel(context, range),
          ),
      ],
      selectedPresetId: state.range == UsageRange.custom
          ? null
          : state.range.value,
      onPresetSelected: (id) {
        final range = UsageRange.tryParse(id);
        if (range != null) cubit.setRange(range);
      },
      onChanged: (range) {
        if (range == null) return;
        cubit.setCustomRange(
          startMs: range.start.millisecondsSinceEpoch,
          endMs: range.end.millisecondsSinceEpoch,
          liveEnd: range.liveEnd,
        );
      },
      triggerBuilder: (context, isOpen) => _Trigger(
        label: _triggerLabel(context, state),
        open: isOpen,
      ),
    );
  }

  TpDateTimeRange? _valueFor(SessionUsageState state, DateTime now) {
    if (state.range == UsageRange.custom &&
        state.customStartMs != null &&
        state.customEndMs != null) {
      return TpDateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(state.customStartMs!),
        end: state.liveEnd
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(state.customEndMs!),
        liveEnd: state.liveEnd,
      );
    }

    final bounds = usageRangeBounds(
      range: state.range == UsageRange.custom ? UsageRange.all : state.range,
      nowMs: now.millisecondsSinceEpoch,
    );
    final start = bounds.startMs == null
        ? now.subtract(const Duration(days: 30))
        : DateTime.fromMillisecondsSinceEpoch(bounds.startMs!);
    final end = bounds.endMs == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(bounds.endMs!);
    return TpDateTimeRange(start: start, end: end);
  }

  String _triggerLabel(BuildContext context, SessionUsageState state) {
    if (state.range != UsageRange.custom ||
        state.customStartMs == null ||
        state.customEndMs == null) {
      return usageRangeLabel(context, state.range);
    }
    final formatter = DateFormat('MM/dd HH:mm');
    final start = DateTime.fromMillisecondsSinceEpoch(state.customStartMs!);
    final end = state.liveEnd
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(state.customEndMs!);
    return '${formatter.format(start)} – ${formatter.format(end)}';
  }
}

class _Trigger extends StatelessWidget {
  const _Trigger({required this.label, required this.open});

  final String label;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        key: AppKeys.sessionUsageRangeTrigger,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: open ? cs.surfaceContainerHighest : cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the page and remove the toolbar**

In `client/lib/pages/usage/session_usage_page.dart`:

Add the live-range timer next to `_autoSyncTimer`:

```dart
  Timer? _liveRangeTimer;
```

Cancel it in `dispose()`:

```dart
    _liveRangeTimer?.cancel();
```

Add the timer helper:

```dart
  void _syncLiveRangeTimer(bool live) {
    if (live && _liveRangeTimer == null) {
      _liveRangeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) return;
        context.read<SessionUsageCubit>().refreshRangeNow();
      });
      return;
    }
    if (!live) {
      _liveRangeTimer?.cancel();
      _liveRangeTimer = null;
    }
  }
```

Wrap the existing sync listener with a live-range listener:

```dart
    final content = BlocListener<SessionUsageCubit, SessionUsageState>(
      listenWhen: (previous, current) => previous.liveEnd != current.liveEnd,
      listener: (context, state) => _syncLiveRangeTimer(state.liveEnd),
      child: BlocListener<SessionUsageCubit, SessionUsageState>(
        listenWhen: (previous, current) =>
            previous.isSyncing && !current.isSyncing,
        listener: (context, state) {
          // ... existing body unchanged ...
        },
        child: BlocBuilder<SessionUsageCubit, SessionUsageState>(
          // ... existing body unchanged ...
        ),
      ),
    );
```

Replace the import:

```dart
import 'widgets/usage_page_chrome.dart';
```

with:

```dart
import 'widgets/usage_filter_bar.dart';
import 'widgets/usage_page_chrome.dart';
```

Replace:

```dart
          UsageToolbar(state: state, cubit: cubit),
```

with:

```dart
          UsageFilterBar(state: state, cubit: cubit),
```

Pass the group callback to the detail table:

```dart
          UsageDetailTable(
            dashboard: dashboard,
            groupBy: state.groupBy,
            searchController: _searchController,
            onQueryChanged: cubit.setQuery,
            onResetFilters: () => _resetFilters(cubit),
            onGroupByChanged: cubit.setGroupBy,
            resetKey:
                '${state.range.name}|${state.customStartMs ?? ''}|'
                '${state.customEndMs ?? ''}|${state.liveEnd}|'
                '${state.cli?.name ?? ''}|${state.groupBy.name}|${state.query}',
          ),
```

In `client/lib/pages/usage/widgets/usage_page_chrome.dart`, delete the `UsageToolbar` class and its `_rangeLabel` method. Keep `UsagePageHeader` and `UsageFooter`. Remove the now-unused `models/session_usage_dashboard.dart` and `models/team_config.dart` imports if `flutter analyze` reports them.

- [ ] **Step 6: Verify the callback wiring**

Confirm `client/lib/pages/usage/widgets/usage_detail_table.dart` passes `widget.onGroupByChanged` to `UsageTableToolbar` and no longer imports `session_usage_cubit.dart`.

- [ ] **Step 7: Run the test to verify it passes**

```bash
cd client && dart run tool/run_tests.dart test/pages/usage/session_usage_page_test.dart
```

Expected: PASS. If the tooltip lookup fails because `Tooltip` is not in the tree until hover, use `find.byTooltip('Codex')`; it finds the `Tooltip` widget regardless of visibility.

- [ ] **Step 8: Commit**

```bash
git add client/lib/pages/usage/widgets/usage_filter_bar.dart \
  client/lib/pages/usage/widgets/usage_date_range_picker.dart \
  client/lib/pages/usage/session_usage_page.dart \
  client/lib/pages/usage/widgets/usage_page_chrome.dart \
  client/lib/pages/usage/widgets/usage_detail_table.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/usage/session_usage_page_test.dart
git commit -m "feat(usage): add icon filters and date-time range picker"
```

---

### Task 12: Final verification and cleanup

**Files:**
- All changed files.

- [ ] **Step 1: Regenerate localizations**

```bash
cd client && flutter gen-l10n
```

Expected: no errors.

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues. Fix any unused imports or stale `UsageToolbar` references.

- [ ] **Step 3: Run the focused usage and shared_ui tests**

```bash
cd client && dart run tool/run_tests.dart \
  packages/shared_ui/test/components/table/ \
  packages/shared_ui/test/components/date_range/tp_date_time_range_picker_test.dart \
  test/pages/usage/ \
  test/services/usage/usage_aggregator_test.dart \
  test/cubits/session_usage_cubit_test.dart \
  test/repositories/app_settings_repository_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run the full suite**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: PASS. If a pre-existing unrelated test fails, record it and confirm it is unrelated with `git diff --stat`.

- [ ] **Step 5: Commit any final fixes**

```bash
git add client/lib/l10n \
  client/lib/pages/usage \
  client/lib/cubits/session_usage_cubit.dart \
  client/lib/models/session_usage_dashboard.dart \
  client/lib/services/usage/usage_aggregator.dart \
  client/lib/repositories/app_settings_repository.dart \
  client/lib/utils/ui/app_keys.dart \
  client/packages/shared_ui/lib \
  client/packages/shared_ui/test \
  client/test/pages/usage \
  client/test/services/usage/usage_aggregator_test.dart \
  client/test/cubits/session_usage_cubit_test.dart \
  client/test/repositories/app_settings_repository_test.dart
git commit -m "test: verify usage table and range picker"
```

---

## Self-Review Notes

- Spec coverage: table model/drag/sort/hide (Tasks 1-3), date-time picker (Task 4), persistence (Task 5), range bounds (Task 6), cubit (Task 7), l10n (Task 8), usage columns (Task 9), table UI (Task 10), filter bar/page wiring (Task 11), verification (Task 12).
- Controlled table state is used consistently: `TpDataTable` only calls `onStateChanged`; `UsageDetailTable` sorts and paginates.
- `UsageDetailTable` now requires `onGroupByChanged`; the only production caller is `session_usage_page.dart`, and the new test passes a no-op.
- `shared_ui` stays free of app l10n and preferences; labels and table state are injected.
- Persistence strips sort with `copyWith(clearSort: true)`.
- `custom` range falls back to all-time when either bound is missing.
