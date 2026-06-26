import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/terminal/workspace_shell_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkspaceShellConnector connector;

  setUp(() {
    connector = WorkspaceShellConnector(
      transportFactory: TerminalTransportFactory(
        sshProfileRepository: SshProfileRepository(),
        sshCredentialStore: InMemorySshCredentialStore(),
        sshKnownHostRepository: InMemorySshKnownHostRepository(),
      ),
      sshProfileRepository: SshProfileRepository(),
    );
  });

  group('WorkspaceShellConnector.resolveLaunchPlan', () {
    test('local spec uses shell path and cwd', () {
      final plan = connector.resolveLaunchPlan(
        spec: const WorkspaceTerminalLocalSpec('/bin/zsh'),
        workingDirectory: '/home/user/proj',
      );
      expect(plan.executable, '/bin/zsh');
      expect(plan.workingDirectory, '/home/user/proj');
      expect(plan.usesRemoteTransport, isFalse);
      expect(plan.runtimeTarget.kind.name, 'local');
    });

    test('ssh profile spec uses remote transport', () {
      final plan = connector.resolveLaunchPlan(
        spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
        workingDirectory: '/remote',
      );
      expect(plan.usesRemoteTransport, isTrue);
      expect(plan.runtimeTarget.kind.name, 'ssh');
    });
  });

  group('WorkspaceShellConnector.runtimeTargetFor', () {
    test('maps workspace target id to runtime kind', () {
      final target = connector.runtimeTargetFor(
        const WorkspaceTerminalWorkspaceTargetSpec('wsl:Ubuntu'),
      );
      expect(target.kind.name, 'wsl');
      expect(target.wslDistro, 'Ubuntu');
    });
  });
}
