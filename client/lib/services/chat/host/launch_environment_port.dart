import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cli/registry/cli_tool_registry.dart';
import '../../install/install_job_registry.dart';
import '../launch/workspace/workspace_provision_coordinator.dart';
import '../session/session_lifecycle_service.dart';
import '../chat_session_shell_factory.dart';

/// Everything the launch flow needs to know about *where* and *with what* a
/// shell is spawned: workspace provision state, CLI registry, terminal theme,
/// and the root-sandbox opt-in.
abstract interface class LaunchEnvironmentPort {
  SessionLifecycleService get lifecycle;

  ChatSessionShellFactory get shellFactory;

  WorkspaceProvisionCoordinator get workspaceProvision;

  CliToolRegistry get cliRegistry;

  InstallJobRegistry? get installJobRegistry;

  bool Function()? get autoLaunchAllMembersOnConnect;

  /// Workspace opt-in: inject IS_SANDBOX when launching Claude as root over SSH.
  Future<bool> isWorkspaceRootSandboxEnvOptIn(String workspaceId);

  /// Terminal theme for member PTY spawn (COLORFGBG / Claude `theme: auto`).
  /// Null skips apply — tests and early bootstrap may omit it.
  TerminalTheme? resolveTerminalThemeForLaunch();
}
