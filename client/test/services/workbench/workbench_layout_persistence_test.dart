// test/services/workbench/workbench_layout_persistence_test.dart
//
// Coordinator-level tests for Task 9 save/restore wiring: the debounced
// WorkbenchCubit.stream subscription, the at-most-once restore, and the
// session-id resolver. Time is driven with fakeAsync so the 500 ms debounce
// is deterministic; all IO goes through the in-memory fake filesystem.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/workbench_layout_snapshot_repository.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/workbench/workbench_layout_persistence.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _root = '/tp-root';
const _ws = 'ws';
const _file = '$_root/workspace/workspaces/$_ws/workbench-layout.json';
final _sh1 = WorkbenchTabId.shell('sh1');
final _sh2 = WorkbenchTabId.shell('sh2');
final _sh3 = WorkbenchTabId.shell('sh3');

void main() {
  // ChatCubit construction touches AppStorage-bound services.
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  /// Runs [body] inside fakeAsync with a started coordinator over a fresh
  /// in-memory filesystem.
  void withPersistence(
    void Function(
      FakeAsync async,
      InMemoryFilesystem fs,
      WorkbenchCubit workbench,
      ChatCubit chat,
      WorkbenchLayoutPersistence persistence,
    )
    body,
  ) {
    fakeAsync((async) {
      final fs = InMemoryFilesystem();
      final layout = WorkspaceLayout(teampilotRoot: _root, fs: fs);
      final workbench = WorkbenchCubit();
      final chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: AutomationRepository(fs: fs, layout: layout),
      );
      final persistence = WorkbenchLayoutPersistence(
        workbench: workbench,
        chat: chat,
        fs: fs,
        layout: layout,
      )..start();
      body(async, fs, workbench, chat, persistence);
    });
  }

  /// Persists [seeder]'s current layouts for [_ws] through the repository.
  void seedSnapshot(FakeAsync async, InMemoryFilesystem fs, WorkbenchCubit seeder) {
    unawaited(
      WorkbenchLayoutSnapshotRepository(
        workspaceId: _ws,
        fs: fs,
        layout: WorkspaceLayout(teampilotRoot: _root, fs: fs),
      ).save(seeder.centerLayout(_ws), seeder.floatingLayout(_ws)),
    );
    async.flushMicrotasks();
  }

  test('first layout change after start is debounced-saved', () {
    withPersistence((async, fs, workbench, _, _) {
      // The very first mutation after start() must still be persisted —
      // bloc streams do not replay the current state to new listeners, so
      // the subscribe-time baseline seed (not an emission skip) is what
      // keeps the seed itself from being written.
      workbench.openFloating(_ws, _sh1);
      expect(fs.files.containsKey(_file), isFalse, reason: 'still debouncing');

      async.elapse(const Duration(milliseconds: 600));

      expect(fs.files.containsKey(_file), isTrue);
      final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
      expect(decoded['version'], 1);
      final groups = (decoded['floating'] as Map)['groups'] as Map;
      // A tab id snapshot encodes as a [kind, id] pair (deep list equality —
      // `contains` would compare by identity).
      expect((groups.values.single as Map)['order'], [
        ['shell', 'sh1'],
      ]);
    });
  });

  test('changes coalesce within the debounce window', () {
    withPersistence((async, fs, workbench, _, _) {
      workbench.openFloating(_ws, _sh1);
      async.elapse(const Duration(milliseconds: 200));
      workbench.openFloating(_ws, _sh2);
      async.elapse(const Duration(milliseconds: 600));

      final decoded = jsonDecode(fs.files[_file]!) as Map<String, Object?>;
      final groups = (decoded['floating'] as Map)['groups'] as Map;
      expect((groups.values.single as Map)['order'], [
        ['shell', 'sh1'],
        ['shell', 'sh2'],
      ]);
    });
  });

  test('dispose cancels a pending debounce flush', () {
    withPersistence((async, fs, workbench, _, persistence) {
      workbench.openFloating(_ws, _sh1);
      async.elapse(const Duration(milliseconds: 200));
      unawaited(persistence.dispose());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(fs.files.containsKey(_file), isFalse);
    });
  });

  test('restore applies the snapshot once and re-arms after bar clear', () {
    withPersistence((async, fs, workbench, _, persistence) {
      // Seed a persisted snapshot: two floating tabs, one split group.
      final seeder = WorkbenchCubit()
        ..openFloating(_ws, _sh1)
        ..openFloating(_ws, _sh2)
        ..splitTab(
          _ws,
          _sh2,
          axis: Axis.vertical,
          before: false,
          floating: true,
        );
      seedSnapshot(async, fs, seeder);
      seeder.close();

      // Fresh app run: a new bar with one unrelated tab.
      workbench.openFloating(_ws, _sh3);
      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();

      // The snapshot replaced the fresh bar's floating layout (whole-surface
      // view: the split focused the new group, so floatingOrder alone would
      // show only that group).
      expect(workbench.mergedFloatingStrip(_ws).order, [_sh1, _sh2]);
      expect(workbench.floatingLayout(_ws).groups.length, 2);

      // At-most-once: a second call does not reset later user changes.
      workbench.openFloating(_ws, _sh3);
      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();
      expect(workbench.mergedFloatingStrip(_ws).order, [_sh1, _sh2, _sh3]);

      // Bar cleared (workspace tab closed) → restore is re-armed. The clear
      // emission is delivered on a microtask, so drain it before reopening
      // (in the app the reopen is separated by navigation + session load).
      workbench.clearWorkspace(_ws);
      async.flushMicrotasks();
      workbench.openFloating(_ws, _sh3);
      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();
      expect(workbench.mergedFloatingStrip(_ws).order, [_sh1, _sh2]);
    });
  });

  test('session tabs are pruned when ChatCubit cannot resolve them', () {
    withPersistence((async, fs, workbench, _, persistence) {
      // Persist a bar holding one session tab and one floating shell tab.
      final seeder = WorkbenchCubit()
        ..openSession(_ws, 's1')
        ..openFloating(_ws, _sh1);
      seedSnapshot(async, fs, seeder);
      seeder.close();

      workbench.openFloating(_ws, _sh2);
      // ChatCubit has no sessions and no open tabs → the session id does not
      // resolve and must be pruned; the shell tab survives.
      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();

      expect(workbench.centerOrder(_ws), isEmpty);
      expect(workbench.floatingOrder(_ws), [_sh1]);
    });
  });

  test('restore without a snapshot leaves the bar untouched', () {
    withPersistence((async, _, workbench, _, persistence) {
      workbench.openFloating(_ws, _sh3);
      unawaited(persistence.restoreForWorkspace(_ws));
      async.flushMicrotasks();
      expect(workbench.floatingOrder(_ws), [_sh3]);
    });
  });
}
