import 'package:flutter/material.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/split_command_registrar.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late ChatCubit chat;
  late WorkbenchCubit workbench;
  late CommandBus bus;

  setUp(() {
    chat = testChatCubit(executableResolver: () => 'true');
    workbench = WorkbenchCubit();
    bus = CommandBus();
    registerSplitCommands(bus, chat, workbench);
    addTearDown(chat.close);
    addTearDown(workbench.close);
  });

  test('splitRight splits the focused center group active tab horizontally', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');

    bus.invoke(CommandIds.workbenchSplitRight);

    final layout = workbench.centerLayout('ws');
    expect(layout.groups.length, 2);
    expect(layout.root, isA<SplitBranch>());
    expect((layout.root as SplitBranch).axis, Axis.horizontal);
    // The split tab lands in the new focused group.
    expect(layout.groups[layout.focusedGroupId]!.order, [
      WorkbenchTabId.session('s2'),
    ]);
    expect(layout.groups['g0']!.order, [WorkbenchTabId.session('s1')]);
  });

  test('splitDown splits vertically', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');

    bus.invoke(CommandIds.workbenchSplitDown);

    final layout = workbench.centerLayout('ws');
    expect(layout.groups.length, 2);
    expect((layout.root as SplitBranch).axis, Axis.vertical);
  });

  test('split commands are silent no-ops without an active workspace', () {
    // No setActiveWorkspaceId: activeWorkspaceId stays ''.
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');

    bus.invoke(CommandIds.workbenchSplitRight);
    bus.invoke(CommandIds.workbenchSplitDown);
    bus.invoke(CommandIds.workbenchSplitReset);
    bus.invoke(CommandIds.workbenchFocusNextGroup);
    bus.invoke(CommandIds.workbenchMoveTabToNextGroup);

    expect(workbench.centerLayout('ws').groups.length, 1);
  });

  test('split command no-ops on a sole-tab group', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');

    bus.invoke(CommandIds.workbenchSplitRight);

    expect(workbench.centerLayout('ws').groups.length, 1);
  });

  test('reset collapses both layouts', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');
    workbench.openShell('ws', 'e1');
    workbench.openShell('ws', 'e2');
    workbench.splitTab(
      'ws',
      WorkbenchTabId.session('s2'),
      axis: Axis.horizontal,
      before: false,
    );
    workbench.splitTab(
      'ws',
      WorkbenchTabId.shell('e2'),
      axis: Axis.vertical,
      before: false,
      floating: true,
    );
    expect(workbench.centerLayout('ws').groups.length, 2);
    expect(workbench.floatingLayout('ws').groups.length, 2);

    bus.invoke(CommandIds.workbenchSplitReset);

    expect(workbench.centerLayout('ws').groups.length, 1);
    expect(workbench.floatingLayout('ws').groups.length, 1);
  });

  test('focusNextGroup cycles through center leaf groups', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');
    workbench.splitTab(
      'ws',
      WorkbenchTabId.session('s2'),
      axis: Axis.horizontal,
      before: false,
    );
    // splitTab focuses the new group (g1).
    expect(workbench.centerLayout('ws').focusedGroupId, 'g1');

    bus.invoke(CommandIds.workbenchFocusNextGroup);
    expect(workbench.centerLayout('ws').focusedGroupId, 'g0');
    bus.invoke(CommandIds.workbenchFocusNextGroup);
    expect(workbench.centerLayout('ws').focusedGroupId, 'g1');

    // Single group: no cycle target, focus unchanged.
    bus.invoke(CommandIds.workbenchSplitReset);
    bus.invoke(CommandIds.workbenchFocusNextGroup);
    expect(workbench.centerLayout('ws').groups.length, 1);
    expect(workbench.centerLayout('ws').focusedGroupId, 'g0');
  });

  test('moveTabToNextGroup moves the focused group active tab', () {
    chat.tabStore.setActiveWorkspaceId('ws');
    workbench.openSession('ws', 's1');
    workbench.openSession('ws', 's2');
    workbench.splitTab(
      'ws',
      WorkbenchTabId.session('s2'),
      axis: Axis.horizontal,
      before: false,
    );

    bus.invoke(CommandIds.workbenchMoveTabToNextGroup);

    final layout = workbench.centerLayout('ws');
    expect(layout.groups.length, 1);
    expect(layout.groups['g0']!.order, [
      WorkbenchTabId.session('s1'),
      WorkbenchTabId.session('s2'),
    ]);
    expect(layout.focusedGroupId, 'g0');
  });
}
