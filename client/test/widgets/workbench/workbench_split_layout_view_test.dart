import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/widgets/workbench/workbench_split_layout_view.dart';

final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');

/// Host constrains the view to a deterministic 500x400 box so divider math
/// (extent-based min-clamp expectations) is stable.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 500, height: 400, child: child)),
  ),
);

/// Stateful probe: its State identity asserts an element was never
/// unmounted across a rebuild.
class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe({super.key, required this.label});

  final String label;

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: Text(widget.label));
}

void main() {
  late WorkbenchGroupLayout layout;

  /// Two groups: root branch horizontal, g0 (s1) first, new group (s2) second.
  WorkbenchGroupLayout seedTwoGroups() {
    const r = SplitLayoutReducer();
    final base = singleGroupLayout(_s1);
    final withTwo = base.copyWith(
      groups: {
        'g0': const TabStripReducer()
            .add(base.groups['g0']!, _s2, preview: false)
            .$1,
      },
    );
    return r.split(withTwo, tab: _s2, axis: Axis.horizontal, before: false)!;
  }

  setUp(() {
    layout = seedTwoGroups();
  });

  String secondGroupId() =>
      ((layout.root as SplitBranch).second as SplitLeaf).groupId;

  testWidgets('renders one group builder output per leaf', (tester) async {
    final second = secondGroupId();
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    expect(find.text('group-g0'), findsOneWidget);
    expect(find.text('group-$second'), findsOneWidget);
  });

  testWidgets('splitEnabled false renders only focused group', (tester) async {
    final second = secondGroupId();
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          splitEnabled: false,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    expect(find.text('group-$second'), findsOneWidget);
    expect(find.text('group-g0'), findsNothing);
    // No dividers in single-group mode.
    expect(find.byKey(workbenchSplitDividerKey(const <bool>[])), findsNothing);
  });

  testWidgets('focus change keeps pane elements mounted (state survives)', (
    tester,
  ) async {
    // A focus-only layout change must not unmount or displace any pane —
    // terminals and chat views would lose their state otherwise. The panes
    // rebuild (fresh data) but keep their elements.
    final paneKeys = <String, GlobalKey<State<StatefulWidget>>>{};
    late StateSetter setRootState;
    var currentLayout = layout;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            setRootState = setState;
            return WorkbenchSplitLayoutView(
              layout: currentLayout,
              groupBuilder: (context, id, strip) => _StatefulProbe(
                key: paneKeys.putIfAbsent(
                  id,
                  () => GlobalKey<State<StatefulWidget>>(
                    debugLabel: 'pane-$id',
                  ),
                ),
                label: 'group-$id',
              ),
            );
          },
        ),
      ),
    );
    final second = secondGroupId();
    expect(paneKeys['g0']!.currentState, isNotNull);
    expect(paneKeys[second]!.currentState, isNotNull);
    final g0State = paneKeys['g0']!.currentState;
    final secondState = paneKeys[second]!.currentState;

    setRootState(
      () => currentLayout = currentLayout.copyWith(focusedGroupId: second),
    );
    await tester.pump();

    expect(find.text('group-g0'), findsOneWidget);
    expect(find.text('group-$second'), findsOneWidget);
    // Same state objects → the elements were never unmounted or displaced.
    expect(identical(paneKeys['g0']!.currentState, g0State), isTrue);
    expect(identical(paneKeys[second]!.currentState, secondState), isTrue);
  });

  testWidgets('splitEnabled false honors focusedGroupIdOverride', (
    tester,
  ) async {
    final second = secondGroupId();
    layout = layout.copyWith(focusedGroupId: 'g0');
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          splitEnabled: false,
          focusedGroupIdOverride: second,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    expect(find.text('group-$second'), findsOneWidget);
    expect(find.text('group-g0'), findsNothing);
  });

  testWidgets('maximizedGroupId renders only that group', (tester) async {
    final second = secondGroupId();
    layout = layout.copyWith(maximizedGroupId: 'g0');
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    expect(find.text('group-g0'), findsOneWidget);
    expect(find.text('group-$second'), findsNothing);
    expect(find.byKey(workbenchSplitDividerKey(const <bool>[])), findsNothing);
  });

  testWidgets('divider drag commits once on end and brackets pty hold', (
    tester,
  ) async {
    final holds = <String>[];
    final paths = <List<bool>>[];
    double? committed;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          minGroupExtent: 100,
          onPtyHoldBegin: () => holds.add('begin'),
          onPtyHoldEnd: () => holds.add('end'),
          onResizeCommit: (commits) {
            paths.add(commits.first.$1);
            committed = commits.first.$2;
          },
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(workbenchSplitDividerKey(const <bool>[])),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(holds, ['begin', 'end']);
    expect(paths, [<bool>[]]);
    expect(committed, isNotNull);
    // 500px host, 1px divider → 499 content; 0.5 start + 40px first-ward.
    expect(committed! > 0.0 && committed! < 1.0, isTrue);
    expect(committed!, closeTo((0.5 * 499 + 40) / 499, 0.01));
  });

  testWidgets('divider drag clamps to minGroupExtent', (tester) async {
    double? committed;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          minGroupExtent: 100,
          onResizeCommit: (commits) => committed = commits.first.$2,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(
      find.byKey(workbenchSplitDividerKey(const <bool>[])),
    );
    final gesture = await tester.startGesture(center);
    // Way past the point where the second pane would drop below 100px.
    await gesture.moveBy(const Offset(600, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(committed, isNotNull);
    expect(committed!, closeTo(1 - 100 / 499, 0.002));
  });

  testWidgets(
    'dragging the OUTER divider keeps the far side pane width fixed',
    (tester) async {
      // Three columns: root branch g0 | nested branch (g1 | g2), all
      // horizontal. Dragging the ROOT divider (between g0 and the nested
      // pair) must absorb all change in g1 (the nested pair's first) and
      // keep g2 (the far side) at its current pixel width.
      const r = SplitLayoutReducer();
      final second = secondGroupId();
      final withThird = layout.copyWith(
        groups: {
          ...layout.groups,
          second: const TabStripReducer()
              .add(layout.groups[second]!, _s3, preview: false)
              .$1,
        },
      );
      final threeCols = r.splitInto(
        withThird,
        tab: _s3,
        targetGroupId: second,
        axis: Axis.horizontal,
        before: false,
      )!;
      final thirdId =
          (((threeCols.root as SplitBranch).second as SplitBranch).second
                  as SplitLeaf)
              .groupId;
      final secondId = second;

      final commitsOut = <(List<bool>, double)>[];
      late StateSetter setRootState;
      var currentLayout = threeCols;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              setRootState = setState;
              return WorkbenchSplitLayoutView(
                layout: currentLayout,
                minGroupExtent: 40,
                onResizeCommit: (commits) => commitsOut.addAll(commits),
                groupBuilder: (context, id, strip) =>
                    _StatefulProbe(label: 'group-$id'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Probe fills its pane (SizedBox.expand), so its size IS the pane size.
      double widthOf(String id) => tester.getSize(find.text('group-$id')).width;
      final g2Before = widthOf(thirdId);
      final g0Before = widthOf('g0');

      final center = tester.getCenter(
        find.byKey(workbenchSplitDividerKey(const <bool>[])),
      );
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      // Still mid-drag: g2 must not have moved; g0 grew by the drag.
      expect(widthOf(thirdId), g2Before);
      expect(widthOf('g0'), closeTo(g0Before + 40, 1));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(widthOf(thirdId), g2Before);
      expect(widthOf('g0'), closeTo(g0Before - 40, 1));
      await gesture.up();
      await tester.pumpAndSettle();

      // Apply the commits like the cubit does (dragged branch + pinned
      // nested fractions) and verify the committed layout reproduces the
      // drag-end geometry: far side fixed, middle pane absorbed the delta.
      expect(commitsOut, isNotEmpty);
      setRootState(() {
        for (final (path, fraction) in commitsOut) {
          currentLayout = const SplitLayoutReducer().commitResizeByPath(
            currentLayout,
            path: path,
            fraction: fraction,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(widthOf(thirdId), closeTo(g2Before, 1));
      expect(widthOf('g0'), closeTo(g0Before - 40, 1));
      expect(
        widthOf(secondId),
        closeTo(500 - 1 - (g0Before - 40) - g2Before, 1),
      );
    },
  );

  testWidgets('nested branch drag reports its own path', (tester) async {
    // g1 (second group) gains s3, then splits vertically: root branch keeps
    // g0 first, the nested vertical branch (g1 / g2) second.
    final second = secondGroupId();
    layout = layout.copyWith(
      groups: {
        ...layout.groups,
        second: const TabStripReducer()
            .add(layout.groups[second]!, _s3, preview: false)
            .$1,
      },
    );
    layout = const SplitLayoutReducer().split(
      layout,
      tab: _s3,
      axis: Axis.vertical,
      before: false,
    )!;
    double? committed;
    List<bool>? committedPath;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          minGroupExtent: 100,
          onResizeCommit: (commits) {
            committedPath = commits.first.$1;
            committed = commits.first.$2;
          },
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('group-g0'), findsOneWidget);
    expect(find.text('group-$second'), findsOneWidget);
    expect(find.text('group-g2'), findsOneWidget);

    final center = tester.getCenter(
      find.byKey(workbenchSplitDividerKey(const <bool>[true])),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(committedPath, [true]);
    // Nested branch extent is the 400px-tall right pane; 1px divider → 399.
    expect(committed!, closeTo((0.5 * 399 + 30) / 399, 0.01));
  });

  testWidgets('tap in group reports focus', (tester) async {
    String? focusedId;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          onGroupFocused: (id) => focusedId = id,
          groupBuilder: (context, id, strip) =>
              SizedBox.expand(child: Text('group-$id')),
        ),
      ),
    );
    await tester.tap(find.text('group-g0'));
    expect(focusedId, 'g0');
  });

  testWidgets('tap over content with competing gestures still reports focus', (
    tester,
  ) async {
    // Terminal / chat pane content carries its own gesture recognizers
    // (scroll, tap-to-focus editors). The leaf's translucent focus tap must
    // still fire when the child loses or ties the arena — focus follows the
    // pointer-down, not a won tap arena.
    String? focusedId;
    var contentTaps = 0;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          onGroupFocused: (id) => focusedId = id,
          groupBuilder: (context, id, strip) => GestureDetector(
            // A competing tap recognizer on the content, like real panes.
            onTap: () => contentTaps++,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.amber)),
          ),
        ),
      ),
    );
    // Tap a deterministic point inside the left (g0) pane.
    final topLeft = tester.getTopLeft(find.byType(WorkbenchSplitLayoutView));
    await tester.tapAt(topLeft + const Offset(50, 50));
    expect(focusedId, 'g0');
    expect(contentTaps, 1); // content interaction is preserved
  });

  testWidgets('double-tap divider fires onDividerDoubleTap', (tester) async {
    var doubleTaps = 0;
    await tester.pumpWidget(
      _host(
        WorkbenchSplitLayoutView(
          layout: layout,
          onDividerDoubleTap: () => doubleTaps++,
          groupBuilder: (context, id, strip) => Text('group-$id'),
        ),
      ),
    );
    final divider = find.byKey(workbenchSplitDividerKey(const <bool>[]));
    await tester.tap(divider, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(divider, warnIfMissed: false);
    await tester.pump();
    expect(doubleTaps, 1);
    // Let the double-tap recognizer's deadline timer expire before teardown.
    await tester.pump(const Duration(milliseconds: 500));
  });
}
