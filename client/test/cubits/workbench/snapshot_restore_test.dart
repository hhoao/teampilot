// test/cubits/workbench/snapshot_restore_test.dart
//
// Cubit-level integration for Task 9: seed a workbench with tabs, persist the
// split layout, reset the bar like a fresh app run, and restore it back.
import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/repositories/workbench_layout_snapshot_repository.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/in_memory_filesystem.dart';

const _root = '/tp-root';
const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');
final _sh1 = WorkbenchTabId.shell('sh1');
final _r1 = WorkbenchTabId.run('r1');

void main() {
  late InMemoryFilesystem fs;
  late WorkbenchLayoutSnapshotRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = WorkbenchLayoutSnapshotRepository(
      workspaceId: _ws,
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: _root, fs: fs),
    );
  });

  WorkbenchCubit seedCubit() {
    return WorkbenchCubit()
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..openSession(_ws, 's3')
      ..splitTab(_ws, _s2, axis: Axis.vertical, before: true)
      ..pin(_ws, _s1)
      ..openFloating(_ws, _sh1)
      ..openFloating(_ws, _r1)
      ..splitTab(_ws, _r1, axis: Axis.horizontal, before: false, floating: true);
  }

  test('save → reset → restore puts the layout back', () async {
    final cubit = seedCubit();
    final savedCenter = toSnapshot(cubit.centerLayout(_ws));
    final savedFloating = toSnapshot(cubit.floatingLayout(_ws));
    await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));

    // Reset: drop the bar (workspace tab closed) and re-open one tab, like a
    // fresh app run rehydrating a single session.
    cubit.clearWorkspace(_ws);
    expect(cubit.state.byWorkspace.containsKey(_ws), isFalse);
    cubit.openSession(_ws, 's1');
    expect(toSnapshot(cubit.centerLayout(_ws)), isNot(savedCenter));

    await repo.restore(cubit);

    expect(toSnapshot(cubit.centerLayout(_ws)), savedCenter);
    expect(toSnapshot(cubit.floatingLayout(_ws)), savedFloating);
    expect(validateLayout(cubit.centerLayout(_ws)), isTrue);
    expect(validateLayout(cubit.floatingLayout(_ws)), isTrue);
    // Split structure and pin survive.
    expect(cubit.centerLayout(_ws).root, isA<SplitBranch>());
    expect(cubit.centerLayout(_ws).groups['g0']!.pinnedIds, {_s1});
    expect(cubit.floatingLayout(_ws).groups.length, 2);
  });

  test('restore prunes session tabs the resolver rejects', () async {
    final cubit = seedCubit();
    await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));

    cubit.clearWorkspace(_ws);
    cubit.openSession(_ws, 's1');

    await repo.restore(cubit, tabResolves: (tab) => tab != _s3 && tab != _sh1);

    final center = cubit.centerLayout(_ws);
    // s3 was rejected; only s1 and s2 survive (s2's split group keeps s2).
    expect(
      center.groups.values.expand((strip) => strip.order).toSet(),
      {_s1, _s2},
    );
    // Rejected floating shell tab pruned as well; the run tab survives.
    expect(cubit.mergedFloatingStrip(_ws).order, [_r1]);
  });

  test('corrupt snapshot leaves the reset bar untouched', () async {
    final cubit = seedCubit();
    await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));
    await fs.writeString(
      '$_root/workspace/workspaces/$_ws/workbench-layout.json',
      'garbage{',
    );

    cubit.clearWorkspace(_ws);
    cubit.openSession(_ws, 's1');

    await repo.restore(cubit);

    expect(cubit.centerOrder(_ws), [_s1]);
    expect(cubit.centerLayout(_ws).groups.keys, ['g0']);
    expect(cubit.floatingOrder(_ws), isEmpty);
  });
}
