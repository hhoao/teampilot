// test/widgets/workbench/workbench_tab_drag_test.dart
//
// Task 4: tab drag-and-drop split — zone math, dispatch, drag controller /
// scope, drop-region indicator paint, and the generic drag source.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/widgets/workbench/workbench_tab_drag.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');
final _s4 = WorkbenchTabId.session('s4');

const _size = Size(100, 100);

Key _indicatorKey(String zone) => Key('split_drop_indicator_$zone');

/// Two groups: g0 [s1] first, g1 [s2, s3, s4] second (horizontal root split).
/// The dragged tab in the dispatch tests is [s4] (source g1).
WorkbenchGroupLayout _twoGroups() {
  const r = SplitLayoutReducer();
  const strip = TabStripReducer();
  final base = singleGroupLayout(_s1);
  final g0Two = base.copyWith(
    groups: {
      'g0': strip.add(base.groups['g0']!, _s2, preview: false).$1,
    },
  );
  final split = r.split(g0Two, tab: _s2, axis: Axis.horizontal, before: false)!;
  final g1 = ((split.root as SplitBranch).second as SplitLeaf).groupId;
  var g1Strip = split.groups[g1]!;
  g1Strip = strip.add(g1Strip, _s3, preview: false).$1;
  g1Strip = strip.add(g1Strip, _s4, preview: false).$1;
  return split.copyWith(groups: {...split.groups, g1: g1Strip});
}

void main() {
  group('splitDropZoneForOffset (20% edge bands, horizontal wins corners)', () {
    test('center of the region is center', () {
      expect(splitDropZoneForOffset(const Offset(50, 50), _size),
          SplitDropZone.center);
    });

    test('edge midpoints map to their edges', () {
      expect(splitDropZoneForOffset(const Offset(95, 50), _size),
          SplitDropZone.right);
      expect(splitDropZoneForOffset(const Offset(5, 50), _size),
          SplitDropZone.left);
      expect(
          splitDropZoneForOffset(const Offset(50, 5), _size), SplitDropZone.up);
      expect(splitDropZoneForOffset(const Offset(50, 95), _size),
          SplitDropZone.down);
    });

    test('corners belong to the horizontal band regardless of y', () {
      expect(splitDropZoneForOffset(const Offset(95, 5), _size),
          SplitDropZone.right);
      expect(splitDropZoneForOffset(const Offset(95, 95), _size),
          SplitDropZone.right);
      expect(splitDropZoneForOffset(const Offset(5, 5), _size),
          SplitDropZone.left);
      expect(splitDropZoneForOffset(const Offset(5, 95), _size),
          SplitDropZone.left);
    });

    test('bands scale with the region size', () {
      const wide = Size(200, 100);
      // 20% of 200 = 40; x in [40, 160] is the horizontal center.
      expect(splitDropZoneForOffset(const Offset(30, 50), wide),
          SplitDropZone.left);
      expect(splitDropZoneForOffset(const Offset(170, 50), wide),
          SplitDropZone.right);
      expect(splitDropZoneForOffset(const Offset(100, 50), wide),
          SplitDropZone.center);
      expect(
          splitDropZoneForOffset(const Offset(100, 5), wide), SplitDropZone.up);
      expect(splitDropZoneForOffset(const Offset(100, 95), wide),
          SplitDropZone.down);
    });

    test('degenerate size resolves to center', () {
      expect(splitDropZoneForOffset(const Offset(50, 50), Size.zero),
          SplitDropZone.center);
    });
  });

  group('dispatchSplitDrop (real WorkbenchCubit)', () {
    late WorkbenchCubit cubit;
    setUp(() {
      cubit = WorkbenchCubit();
      addTearDown(cubit.close);
    });

    test('center zone moves the tab into the target group', () {
      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.center,
      );
      final layout = cubit.centerLayout(_ws);
      expect(layout.groups['g0']!.order, [_s1, _s4]);
      expect(layout.groups['g0']!.activeId, _s4);
      expect(layout.groups['g1']!.order, [_s2, _s3]);
      expect(layout.focusedGroupId, 'g0');
    });

    test('right zone splits the target group with a new second sibling', () {
      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.right,
      );
      final layout = cubit.centerLayout(_ws);
      final root = layout.root as SplitBranch; // (g0-branch) | g1
      final inner = root.first as SplitBranch;
      expect(inner.axis, Axis.horizontal);
      expect((inner.first as SplitLeaf).groupId, 'g0');
      final newGroupId = (inner.second as SplitLeaf).groupId;
      expect(layout.groups[newGroupId]!.order, [_s4]);
      expect(layout.groups[newGroupId]!.activeId, _s4);
      expect(layout.groups['g0']!.order, [_s1]);
      expect(layout.groups['g1']!.order, [_s2, _s3]);
      expect(layout.focusedGroupId, newGroupId);
    });

    test('left zone places the new group before the target', () {
      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.left,
      );
      final layout = cubit.centerLayout(_ws);
      final inner = (layout.root as SplitBranch).first as SplitBranch;
      expect(inner.axis, Axis.horizontal);
      expect((inner.first as SplitLeaf).groupId, isNot('g0'));
      expect((inner.second as SplitLeaf).groupId, 'g0');
    });

    test('up/down zones split along the vertical axis', () {
      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.down,
      );
      final layout = cubit.centerLayout(_ws);
      final inner = (layout.root as SplitBranch).first as SplitBranch;
      expect(inner.axis, Axis.vertical);
      expect((inner.first as SplitLeaf).groupId, 'g0');
      final downNew = (inner.second as SplitLeaf).groupId;

      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.up,
      );
      final upInner = (cubit.centerLayout(_ws).root as SplitBranch).first
          as SplitBranch;
      expect(upInner.axis, Axis.vertical);
      expect((upInner.first as SplitLeaf).groupId, isNot('g0'));
      expect((upInner.second as SplitLeaf).groupId, 'g0');
      expect(downNew, isNot('g0')); // sanity: new group ids, not the target
    });

    test('own-group edge drop is rejected: cubit emits nothing', () {
      cubit.resetLayoutToSnapshot(_ws, _twoGroups(), null);
      final before = cubit.state;
      // g1 hosts 3 tabs, so the reducer alone would happily split the tab out
      // of its own group — the dispatch layer must reject it instead.
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s2,
        sourceGroupId: 'g1',
        targetGroupId: 'g1',
        zone: SplitDropZone.right,
      );
      expect(identical(cubit.state, before), isTrue);
    });

    test('floating dispatch targets the floating layout only', () {
      cubit.resetLayoutToSnapshot(_ws, null, _twoGroups());
      final centerBefore = cubit.centerLayout(_ws);
      dispatchSplitDrop(
        cubit,
        _ws,
        tab: _s4,
        sourceGroupId: 'g1',
        targetGroupId: 'g0',
        zone: SplitDropZone.right,
        floating: true,
      );
      final floating = cubit.floatingLayout(_ws);
      final inner = (floating.root as SplitBranch).first as SplitBranch;
      expect((inner.first as SplitLeaf).groupId, 'g0');
      expect(layoutGroupHolding(floating, _s4), isNot('g1'));
      expect(identical(cubit.centerLayout(_ws), centerBefore), isTrue);
    });
  });

  group('drag scope / drop regions', () {
    testWidgets('indicator paints each zone and clears on drag end', (
      tester,
    ) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkbenchTabDragHost(
              controller: controller,
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: WorkbenchTabDropRegions(
                    groupId: 'g0',
                    child: Container(color: const Color(0xFF2196F3)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final region = find.byType(WorkbenchTabDropRegions);
      final topLeft = tester.getTopLeft(region);

      controller.begin(
        tab: _s2,
        sourceGroupId: 'g1',
        onDrop: (_, _) {},
      );
      await tester.pump();
      // No pointer position recorded yet → no indicator.
      expect(find.byKey(_indicatorKey('center')), findsNothing);

      controller.updatePosition(topLeft + const Offset(190, 100));
      await tester.pump();
      expect(find.byKey(_indicatorKey('right')), findsOneWidget);

      controller.updatePosition(topLeft + const Offset(10, 100));
      await tester.pump();
      expect(find.byKey(_indicatorKey('left')), findsOneWidget);

      controller.updatePosition(topLeft + const Offset(100, 10));
      await tester.pump();
      expect(find.byKey(_indicatorKey('up')), findsOneWidget);

      controller.updatePosition(topLeft + const Offset(100, 190));
      await tester.pump();
      expect(find.byKey(_indicatorKey('down')), findsOneWidget);

      controller.updatePosition(topLeft + const Offset(100, 100));
      await tester.pump();
      expect(find.byKey(_indicatorKey('center')), findsOneWidget);

      controller.end();
      await tester.pump();
      expect(find.byKey(_indicatorKey('center')), findsNothing);
    });

    testWidgets('indicator hides while the pointer is outside the region', (
      tester,
    ) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkbenchTabDragHost(
              controller: controller,
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: WorkbenchTabDropRegions(
                    groupId: 'g0',
                    child: Container(color: const Color(0xFF2196F3)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final topLeft = tester.getTopLeft(find.byType(WorkbenchTabDropRegions));
      controller.begin(tab: _s2, sourceGroupId: 'g1', onDrop: (_, _) {});
      controller.updatePosition(topLeft + const Offset(190, 100));
      await tester.pump();
      expect(find.byKey(_indicatorKey('right')), findsOneWidget);
      // Far outside the region.
      controller.updatePosition(topLeft + const Offset(-500, 100));
      await tester.pump();
      expect(find.byKey(_indicatorKey('right')), findsNothing);
    });

    testWidgets('scope exposes the active drag via maybeOf', (tester) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      late WorkbenchTabDragScope scope;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkbenchTabDragHost(
              controller: controller,
              child: Builder(
                builder: (context) {
                  scope = WorkbenchTabDragScope.maybeOf(context)!;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(scope.isActive, isFalse);
      expect(scope.draggedTab, isNull);
      expect(scope.sourceGroupId, isNull);
      expect(scope.onDrop, isNull);

      void onDrop(String targetGroupId, SplitDropZone zone) {}
      controller.begin(
        tab: _s2,
        sourceGroupId: 'g0',
        onDrop: onDrop,
      );
      expect(scope.isActive, isTrue);
      expect(scope.draggedTab, _s2);
      expect(scope.sourceGroupId, 'g0');
      expect(scope.onDrop, onDrop);
    });
  });

  group('WorkbenchTabDraggable (drag source)', () {
    Widget dragHost(
      WorkbenchTabDragController controller, {
      required Widget child,
    }) => MaterialApp(
      home: Scaffold(
        body: WorkbenchTabDragHost(controller: controller, child: child),
      ),
    );

    Widget dragTree(
      WorkbenchTabDragController controller,
      List<(String, SplitDropZone)> drops,
    ) => dragHost(
      controller,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: WorkbenchTabDraggable(
              tab: _s2,
              sourceGroupId: 'g0',
              onDrop: (g, z) => drops.add((g, z)),
              child: const Center(child: Text('tab')),
            ),
          ),
          Expanded(
            child: WorkbenchTabDropRegions(
              groupId: 'g1',
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );

    testWidgets('mouse drag begins on press and drops into the region', (
      tester,
    ) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      final drops = <(String, SplitDropZone)>[];
      await tester.pumpWidget(dragTree(controller, drops));

      final tabCenter = tester.getCenter(find.text('tab'));
      final gesture = await tester.startGesture(
        tabCenter,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.isActive, isTrue);
      expect(controller.draggedTab, _s2);
      expect(controller.sourceGroupId, 'g0');

      // Move into g1's right band (region spans the full width below the bar).
      final regionTopLeft = tester.getTopLeft(
        find.byType(WorkbenchTabDropRegions),
      );
      final target = regionTopLeft + const Offset(700, 200);
      await gesture.moveBy(target - tabCenter);
      await tester.pump();
      expect(find.byKey(_indicatorKey('right')), findsOneWidget);

      await gesture.up();
      expect(drops, [('g1', SplitDropZone.right)]);
      expect(controller.isActive, isFalse);
    });

    testWidgets('touch drag starts on long-press and drops into the region', (
      tester,
    ) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      final drops = <(String, SplitDropZone)>[];
      await tester.pumpWidget(dragTree(controller, drops));

      final tabCenter = tester.getCenter(find.text('tab'));
      final gesture = await tester.startGesture(tabCenter);
      await tester.pump();
      // A touch drag waits for the long-press.
      expect(controller.isActive, isFalse);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(controller.isActive, isTrue);

      final regionTopLeft = tester.getTopLeft(
        find.byType(WorkbenchTabDropRegions),
      );
      // Down band: bottom 20% of the ~540px tall region.
      final target = regionTopLeft + const Offset(400, 500);
      await gesture.moveBy(target - tabCenter);
      await tester.pump();
      expect(find.byKey(_indicatorKey('down')), findsOneWidget);

      await gesture.up();
      expect(drops, [('g1', SplitDropZone.down)]);
      expect(controller.isActive, isFalse);
    });

    testWidgets('release outside any region ends the drag without a drop', (
      tester,
    ) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      final drops = <(String, SplitDropZone)>[];
      await tester.pumpWidget(dragTree(controller, drops));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('tab')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.isActive, isTrue);
      // Release over the tab bar, outside every drop region.
      await gesture.up();
      expect(drops, isEmpty);
      expect(controller.isActive, isFalse);
    });

    testWidgets('without a scope the draggable is inert', (tester) async {
      final drops = <(String, SplitDropZone)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkbenchTabDraggable(
              tab: _s2,
              sourceGroupId: 'g0',
              onDrop: (g, z) => drops.add((g, z)),
              child: const Center(child: Text('tab')),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('tab')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 100));
      await gesture.up();
      expect(drops, isEmpty);
    });

    testWidgets('drag source unmounting mid-drag cancels it', (tester) async {
      final controller = WorkbenchTabDragController();
      addTearDown(controller.dispose);
      final drops = <(String, SplitDropZone)>[];
      await tester.pumpWidget(dragTree(controller, drops));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('tab')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.isActive, isTrue);

      // Unmount the tree while the pointer is held.
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WorkbenchTabDragHost(controller: controller, child: const SizedBox()))),
      );
      expect(controller.isActive, isFalse);
      expect(drops, isEmpty);
      await gesture.up();
    });
  });
}

/// The group whose strip hosts [tab], or null when absent.
String? layoutGroupHolding(WorkbenchGroupLayout layout, WorkbenchTabId tab) {
  for (final entry in layout.groups.entries) {
    if (entry.value.contains(tab)) return entry.key;
  }
  return null;
}
