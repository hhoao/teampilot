import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _theme = TerminalTheme.defaults;

class _RecordingConnector extends WorkspaceShellConnector {
  _RecordingConnector()
    : super(
        transportFactory: TerminalTransportFactory(
          sshProfileRepository: SshProfileRepository(),
          sshCredentialStore: InMemorySshCredentialStore(),
          sshKnownHostRepository: InMemorySshKnownHostRepository(),
        ),
        sshProfileRepository: SshProfileRepository(),
      );

  final createdSpecs = <WorkspaceTerminalSessionSpec>[];
  String label = 'recorded-label';

  @override
  TerminalSession createSession(WorkspaceTerminalSessionSpec spec) {
    createdSpecs.add(spec);
    return TerminalSession(
      executable: '/bin/bash',
      validateLaunch: false,
      parseExecutable: false,
    );
  }

  @override
  Future<String> labelForSpec(WorkspaceTerminalSessionSpec spec) async => label;
}

class _RecordingConnectCoordinator extends WorkspaceTerminalConnectCoordinator {
  _RecordingConnectCoordinator(WorkspaceShellConnector connector)
    : super(connector: connector);

  WorkspaceTerminalGroup? lastGroup;
  WorkspaceTerminalEntry? lastEntry;
  TerminalTheme? lastTheme;
  String? lastSshMessage;
  var connectCalls = 0;

  @override
  Future<void> connect({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required void Function() onStateChanged,
    required bool Function() mounted,
  }) async {
    connectCalls++;
    lastGroup = group;
    lastEntry = entry;
    lastTheme = theme;
    lastSshMessage = sshConnectFailedMessage;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openEntry adds entry and connects with given cwd + workspace target', () async {
    final connector = _RecordingConnector();
    final connect = _RecordingConnectCoordinator(connector);
    final group = WorkspaceTerminalGroup();
    const spec = WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1');
    final ops = WorkspaceTerminalSessionOps();

    final entry = await ops.openEntry(
      group: group,
      connector: connector,
      connectCoordinator: connect,
      cwd: '/ws/proj',
      spec: spec,
      theme: _theme,
      sshConnectFailedMessage: 'ssh failed',
      select: true,
      followWorkspace: true,
    );

    expect(connector.createdSpecs, [spec]);
    expect(group.entries, [entry]);
    expect(group.activeId, entry.id);
    expect(entry.cwd, '/ws/proj');
    expect(entry.spec, spec);
    expect(entry.followWorkspace, isTrue);
    expect(entry.titleLabel, 'recorded-label');
    expect(connect.connectCalls, 1);
    expect(connect.lastGroup, same(group));
    expect(connect.lastEntry, same(entry));
    expect(connect.lastTheme, _theme);
    expect(connect.lastSshMessage, 'ssh failed');

    group.dispose();
  });

  test('openEntry uses explicit titleLabel when provided', () async {
    final connector = _RecordingConnector()..label = 'should-not-use';
    final connect = _RecordingConnectCoordinator(connector);
    final group = WorkspaceTerminalGroup();
    final ops = WorkspaceTerminalSessionOps();

    final entry = await ops.openEntry(
      group: group,
      connector: connector,
      connectCoordinator: connect,
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
      theme: _theme,
      sshConnectFailedMessage: 'ssh failed',
      select: false,
      titleLabel: 'custom-title',
    );

    expect(entry.titleLabel, 'custom-title');
    expect(group.activeId, isNull);
    group.dispose();
  });

  test('connectEntry delegates to connect coordinator', () async {
    final connector = _RecordingConnector();
    final connect = _RecordingConnectCoordinator(connector);
    final group = WorkspaceTerminalGroup();
    final entry = group.addEntry(
      cwd: '/tmp',
      spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
      session: connector.createSession(const WorkspaceTerminalLocalSpec('/bin/bash')),
      select: true,
    );
    final ops = WorkspaceTerminalSessionOps();

    await ops.connectEntry(
      group: group,
      entry: entry,
      connectCoordinator: connect,
      theme: _theme,
      sshConnectFailedMessage: 'ssh failed',
    );

    expect(connect.connectCalls, 1);
    expect(connect.lastEntry, same(entry));
    group.dispose();
  });
}
