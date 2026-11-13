import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/shortcut_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../pages/home_workspace/workspace_chrome_commands.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/run_command_registrar.dart';
import '../../services/commands/shortcuts_ui_commands.dart';
import '../../services/commands/workspace_content_search_command_registrar.dart';
import '../../services/commands/workspace_search_command_registrar.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/storage/home_storage.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_run_service.dart';
import '../../services/terminal/workspace_terminal_session_ops.dart';
import '../ui_zoom_baseline.dart';

/// The shell's command bus, its hosts, and the terminal transport stack.
typedef CommandWiring = ({
  CommandBus commandBus,
  ShortcutCubit shortcutCubit,
  WorkspaceChromeCommands workspaceChromeCommands,
  RunCommandHost runCommandHost,
  WorkspaceSearchHost workspaceSearchHost,
  WorkspaceContentSearchHost workspaceContentSearchHost,
  UiZoomBaseline uiZoomBaseline,
  TerminalTransportFactory transportFactory,
  WorkspaceShellConnector workspaceShellConnector,
  WorkspaceTerminalSessionOps workspaceTerminalSessionOps,
  WorkspaceTerminalRunService workspaceTerminalRunService,
});

/// Creates the app-lifetime [CommandBus], registers the shortcut / run /
/// search command groups on it, and builds the terminal transport stack for
/// [storage]'s home plane.
///
/// Command registrations happen exactly once, in the order the shell previously
/// performed them; the remaining command groups (`registerLayoutCommands`,
/// `registerSessionCommands`, `registerSplitCommands`) are registered later by
/// the callers that own their hosts.
CommandWiring wireCommands({
  required HomeStorage storage,
  required SshProfileRepository sshProfileRepo,
  required SshCredentialStore sshCredentialStore,
  required SshKnownHostRepository sshKnownHostRepo,
  required SshClientFactory sshClientFactory,
  required SessionPreferencesCubit sessionPreferencesCubit,
  required RuntimeTarget Function() homeTarget,
  required SshProfile? Function(String id) sshProfileById,
}) {
  final commandBus = CommandBus();
  final shortcutCubit = ShortcutCubit(storage: storage);
  final workspaceChromeCommands = WorkspaceChromeCommands();
  final runCommandHost = RunCommandHost();
  final workspaceSearchHost = WorkspaceSearchHost();
  final workspaceContentSearchHost = WorkspaceContentSearchHost();
  final uiZoomBaseline = UiZoomBaseline();
  registerShortcutsUiCommands(commandBus);
  registerRunCommands(commandBus, runCommandHost);
  registerWorkspaceSearchCommands(commandBus, workspaceSearchHost);
  registerWorkspaceContentSearchCommands(
    commandBus,
    workspaceContentSearchHost,
  );

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  final workspaceShellConnector = WorkspaceShellConnector(
    transportFactory: transportFactory,
    sshProfileRepository: sshProfileRepo,
    sshUseLoginShell: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    homeTarget: homeTarget,
    profileById: sshProfileById,
    fs: storage.fs,
  );
  // Terminal inject deps after connector: registry was created earlier.
  final workspaceTerminalSessionOps = WorkspaceTerminalSessionOps();
  final workspaceTerminalRunService = WorkspaceTerminalRunService();

  return (
    commandBus: commandBus,
    shortcutCubit: shortcutCubit,
    workspaceChromeCommands: workspaceChromeCommands,
    runCommandHost: runCommandHost,
    workspaceSearchHost: workspaceSearchHost,
    workspaceContentSearchHost: workspaceContentSearchHost,
    uiZoomBaseline: uiZoomBaseline,
    transportFactory: transportFactory,
    workspaceShellConnector: workspaceShellConnector,
    workspaceTerminalSessionOps: workspaceTerminalSessionOps,
    workspaceTerminalRunService: workspaceTerminalRunService,
  );
}
