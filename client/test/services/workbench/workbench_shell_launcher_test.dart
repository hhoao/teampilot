import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';
import 'package:teampilot/services/terminal/workspace_terminal_connect_coordinator.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_session_ops.dart';
import 'package:teampilot/services/workbench/workbench_shell_launcher.dart';

import '../../support/post_frame_test_harness.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

class _FakeSessionOps extends WorkspaceTerminalSessionOps {
  @override
  Future<WorkspaceTerminalEntry> createEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
  }) async {
    return group.addEntry(
      cwd: cwd,
      spec: spec,
      session: _testSession(),
      select: select,
      titleLabel: titleLabel.isNotEmpty ? titleLabel : 'Local',
      followWorkspace: followWorkspace,
    );
  }

  @override
  Future<void> connectEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {}
}

class _StubConnector extends WorkspaceShellConnector {
  _StubConnector()
    : super(
        transportFactory: TerminalTransportFactory(
          sshProfileRepository: SshProfileRepository(),
          sshCredentialStore: InMemorySshCredentialStore(),
          sshKnownHostRepository: InMemorySshKnownHostRepository(),
        ),
        sshProfileRepository: SshProfileRepository(),
      );
}

WorkbenchShellLauncher _launcher({
  required ChatCubit chat,
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
  required WorkspaceTerminalRegistry registry,
  WorkspaceTerminalSessionOps? sessionOps,
}) {
  return WorkbenchShellLauncher(
    floating: floating,
    workbench: workbench,
    chat: chat,
    registry: registry,
    connector: _StubConnector(),
    layout: LayoutCubit(),
    sessionOps: sessionOps ?? _FakeSessionOps(),
    fallbackLocalShell: () => '/bin/bash',
    platformBrightness: () => Brightness.dark,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('resolveMostRecentFloatingShell', () {
    test('prefers active terminal tab payload', () {
      final shell = resolveMostRecentFloatingShell(
        order: [
          WorkbenchTabId.shell('e1'),
          WorkbenchTabId.shell('e2'),
        ],
        activeId: WorkbenchTabId.shell('e1'),
      );
      expect(shell, WorkbenchTabId.shell('e1'));
    });

    test('falls back to last terminal tab then registry active', () {
      expect(
        resolveMostRecentFloatingShell(
          order: [
            WorkbenchTabId.file('/a'),
            WorkbenchTabId.shell('e1'),
            WorkbenchTabId.shell('e2'),
          ],
          activeId: WorkbenchTabId.file('/a'),
        ),
        WorkbenchTabId.shell('e2'),
      );
      expect(
        resolveMostRecentFloatingShell(
          order: const <WorkbenchTabId>[],
          activeId: null,
          registryActiveEntryId: 'reg-1',
        ),
        WorkbenchTabId.shell('reg-1'),
      );
    });
  });

  group('resolveWorkbenchShellToggle', () {
    test('returns null when workspaceId is empty', () {
      expect(
        resolveWorkbenchShellToggle(
          workspaceId: '  ',
          resolveMostRecentShell: (_) => WorkbenchTabId.shell('e1'),
        ),
        isNull,
      );
    });

    test('selects most recent shell when present', () {
      final shell = WorkbenchTabId.shell('e1');
      final plan = resolveWorkbenchShellToggle(
        workspaceId: 'ws',
        resolveMostRecentShell: (id) {
          expect(id, 'ws');
          return shell;
        },
      );
      expect(plan, isNotNull);
      expect(plan!.action, WorkbenchShellToggleAction.selectExisting);
      expect(plan.existing, shell);
    });

    test('plans create when no shell tab exists', () {
      final plan = resolveWorkbenchShellToggle(
        workspaceId: 'ws',
        resolveMostRecentShell: (_) => null,
      );
      expect(plan, isNotNull);
      expect(plan!.action, WorkbenchShellToggleAction.createDefault);
      expect(plan.existing, isNull);
      expect(plan.workspaceId, 'ws');
    });
  });

  group('WorkbenchShellLauncher.openAndSelect', () {
    late ChatCubit chat;
    late WorkbenchCubit workbench;
    late FloatingWorkspaceCubit floating;
    late WorkspaceTerminalRegistry registry;

    setUp(() {
      chat = testChatCubit(executableResolver: () => 'true');
      workbench = WorkbenchCubit();
      floating = FloatingWorkspaceCubit();
      registry = WorkspaceTerminalRegistry();
    });

    tearDown(() async {
      await chat.close();
      await workbench.close();
      await floating.close();
      registry.disposeAll();
    });

    test('creates registry entry and floating tab, not workbench shell', () async {
      final launcher = _launcher(
        chat: chat,
        workbench: workbench,
        floating: floating,
        registry: registry,
      );

      final entry = await launcher.openAndSelect(
        workspaceId: 'ws',
        tabScopeId: 'ws',
        cwd: '/tmp/proj',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
      );

      expect(entry, isNotNull);
      expect(registry.groupFor('ws').entries.map((e) => e.id), [entry!.id]);
      expect(floating.state.visibility, FloatingPanelVisibility.open);
      expect(floating.state.activeWorkspaceId, 'ws');
      expect(
        workbench.state.bar('ws').floating.order,
        [WorkbenchTabId.shell(entry.id)],
      );
      expect(
        workbench.state.bar('ws').center.order.where(
          (t) => t.kind == WorkbenchTabKind.shell,
        ),
        isEmpty,
      );
    });
  });

  group('WorkbenchShellLauncher.focusOrCreateDefaultShell', () {
    late ChatCubit chat;
    late WorkbenchCubit workbench;
    late FloatingWorkspaceCubit floating;
    late WorkspaceTerminalRegistry registry;

    setUp(() {
      chat = testChatCubit(executableResolver: () => 'true');
      workbench = WorkbenchCubit();
      floating = FloatingWorkspaceCubit();
      registry = WorkspaceTerminalRegistry();
    });

    tearDown(() async {
      await chat.close();
      await workbench.close();
      await floating.close();
      registry.disposeAll();
    });

    test('selectExisting focuses floating tab, not workbench', () async {
      chat.setActiveWorkspace('ws');
      floating.setActiveWorkspace('ws');
      workbench.openShell('ws', 'e1');
      workbench.openShell('ws', 'e2');
      workbench.activate('ws', WorkbenchTabId.shell('e1'));
      floating.minimize();

      final launcher = _launcher(
        chat: chat,
        workbench: workbench,
        floating: floating,
        registry: registry,
      );
      await launcher.focusOrCreateDefaultShell();

      expect(floating.state.visibility, FloatingPanelVisibility.open);
      expect(workbench.state.bar('ws').floating.activeId,
          WorkbenchTabId.shell('e1'));
      expect(
        workbench.state.bar('ws').center.order.where(
          (t) => t.kind == WorkbenchTabKind.shell,
        ),
        isEmpty,
      );
      expect(registry.groupFor('ws').entries, isEmpty);
    });
  });
}
