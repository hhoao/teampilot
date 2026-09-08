// test/repositories/workbench_layout_snapshot_repository_test.dart
import 'dart:convert';

import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/repositories/workbench_layout_snapshot_repository.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/in_memory_filesystem.dart';

const _root = '/tp-root';
const _ws = 'ws-1';
const _file = '$_root/workspace/workspaces/$_ws/workbench-layout.json';
final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _shell1 = WorkbenchTabId.shell('shell-1');
final _shell2 = WorkbenchTabId.shell('shell-2');

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

  /// Center: `s1 | s2` split (s2 in its own group); floating: two shell tabs
  /// split vertically.
  WorkbenchCubit seedCubit() {
    final cubit = WorkbenchCubit()
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false)
      ..openFloating(_ws, _shell1)
      ..openFloating(_ws, _shell2)
      ..splitTab(_ws, _shell2, axis: Axis.vertical, before: true, floating: true);
    return cubit;
  }

  group('save', () {
    test('writes the versioned per-workspace snapshot', () async {
      final cubit = seedCubit();
      await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));

      final raw = fs.files[_file];
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['version'], 1);
      expect(
        (decoded['center'] as Map)['root'],
        isA<Map>().having((r) => r['kind'], 'kind', 'branch'),
      );
      expect(decoded['floating'], isA<Map>());
    });

    test('writes into the workspace directory only', () async {
      final cubit = seedCubit();
      await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));
      expect(fs.directories.contains('$_root/workspace/workspaces/$_ws'), isTrue);
    });
  });

  group('restore round-trip', () {
    test('restores both layouts into a fresh cubit', () async {
      final seeded = seedCubit();
      final savedCenter = toSnapshot(seeded.centerLayout(_ws));
      final savedFloating = toSnapshot(seeded.floatingLayout(_ws));
      await repo.save(seeded.centerLayout(_ws), seeded.floatingLayout(_ws));

      // Fresh app run: new cubit, one tab already re-opened by the user.
      final restored = WorkbenchCubit()..openSession(_ws, 's1');
      await repo.restore(restored);

      expect(toSnapshot(restored.centerLayout(_ws)), savedCenter);
      expect(toSnapshot(restored.floatingLayout(_ws)), savedFloating);
      expect(validateLayout(restored.centerLayout(_ws)), isTrue);
      expect(validateLayout(restored.floatingLayout(_ws)), isTrue);
    });

    test('persisted landing fields do not leak into the restored strips', () async {
      final seeded = seedCubit()
        ..enterLanding(_ws, initialText: 'draft');
      await repo.save(seeded.centerLayout(_ws), seeded.floatingLayout(_ws));

      final restored = WorkbenchCubit();
      await repo.restore(restored);
      expect(restored.centerLandingInitialText(_ws), isNull);
      expect(restored.centerLandingActive(_ws), isFalse);
    });
  });

  group('restore fallbacks', () {
    test('missing file leaves the bar at its current state', () async {
      final cubit = WorkbenchCubit()..openSession(_ws, 's1');
      final before = toSnapshot(cubit.centerLayout(_ws));
      await repo.restore(cubit);
      expect(toSnapshot(cubit.centerLayout(_ws)), before);
      expect(cubit.centerOrder(_ws), [_s1]);
    });

    test('corrupt JSON leaves the bar at its current state', () async {
      await fs.writeString(_file, '{not valid json');
      final cubit = WorkbenchCubit()..openSession(_ws, 's1');
      final before = toSnapshot(cubit.centerLayout(_ws));
      await repo.restore(cubit);
      expect(toSnapshot(cubit.centerLayout(_ws)), before);
    });

    test('non-object JSON leaves the bar at its current state', () async {
      await fs.writeString(_file, '[1, 2, 3]');
      final cubit = WorkbenchCubit()..openSession(_ws, 's1');
      await repo.restore(cubit);
      expect(cubit.centerOrder(_ws), [_s1]);
      expect(cubit.centerLayout(_ws).groups.keys, ['g0']);
    });

    test('version mismatch is treated as corrupt', () async {
      final seeded = seedCubit();
      await repo.save(seeded.centerLayout(_ws), seeded.floatingLayout(_ws));
      // Re-encode the exact same payload under a future version.
      final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
      decoded['version'] = 99;
      await fs.writeString(_file, jsonEncode(decoded));

      final cubit = WorkbenchCubit()..openSession(_ws, 's1');
      final before = toSnapshot(cubit.centerLayout(_ws));
      await repo.restore(cubit);
      expect(toSnapshot(cubit.centerLayout(_ws)), before);
      expect(cubit.floatingLayout(_ws).groups.length, 1);
      expect(cubit.floatingOrder(_ws), isEmpty);
    });

    test('missing center/floating objects are treated as corrupt', () async {
      await fs.writeString(_file, '{"version": 1, "center": 42}');
      final cubit = WorkbenchCubit()..openSession(_ws, 's1');
      await repo.restore(cubit);
      expect(cubit.centerOrder(_ws), [_s1]);
    });
  });

  group('restore pruning', () {
    test('unresolved session ids are pruned and empty groups rolled up', () async {
      final seeded = seedCubit();
      await repo.save(seeded.centerLayout(_ws), seeded.floatingLayout(_ws));

      final restored = WorkbenchCubit();
      await repo.restore(
        restored,
        tabResolves: (tab) => tab != _s2,
      );

      // s2's group vanished; s1's group rolled up to the root.
      final center = restored.centerLayout(_ws);
      expect(center.root, isA<SplitLeaf>());
      expect(center.groups.length, 1);
      expect(center.groups.values.single.order, [_s1]);
      // Non-session tabs always resolve: the floating split survives intact.
      expect(
        toSnapshot(restored.floatingLayout(_ws)),
        toSnapshot(seeded.floatingLayout(_ws)),
      );
    });

    test('snapshot with no surviving group keeps the current layout', () async {
      final seeded = seedCubit();
      await repo.save(seeded.centerLayout(_ws), seeded.floatingLayout(_ws));

      final restored = WorkbenchCubit()..openSession(_ws, 's9');
      await repo.restore(restored, tabResolves: (_) => false);

      expect(restored.centerOrder(_ws), [WorkbenchTabId.session('s9')]);
      expect(restored.floatingOrder(_ws), isEmpty);
    });
  });

  group('delete', () {
    test('removes the snapshot file', () async {
      final cubit = seedCubit();
      await repo.save(cubit.centerLayout(_ws), cubit.floatingLayout(_ws));
      expect(fs.files.containsKey(_file), isTrue);

      await repo.delete();
      expect(fs.files.containsKey(_file), isFalse);

      // Restore after delete is a no-op fallback.
      final restored = WorkbenchCubit()..openSession(_ws, 's1');
      await repo.restore(restored);
      expect(restored.centerOrder(_ws), [_s1]);
    });

    test('is a no-op when nothing was persisted', () async {
      await repo.delete();
      expect(fs.files.containsKey(_file), isFalse);
    });
  });
}
