import '../../services/host/host_interactive_shell.dart';

export '../../services/host/host_interactive_shell.dart'
    show HostInteractiveShell, HostInteractiveShellSpec;
export '../../services/host/host_interactive_shell_kind.dart'
    show HostInteractiveShellKind;

/// @deprecated Use [HostInteractiveShell] from `services/host/`.
abstract final class WorkspaceInteractiveShell {
  WorkspaceInteractiveShell._();

  static String executable() => HostInteractiveShell.defaultExecutable();

  static String resolve(String? preferred) =>
      HostInteractiveShell.resolvePath(preferred);

  static List<String> discoverShellPaths() =>
      HostInteractiveShell.discoverPaths();

  static String menuLabelFor(String shellPath) =>
      HostInteractiveShell.menuLabelFor(shellPath);

  static List<String> launchArguments(String executable) =>
      HostInteractiveShell.resolveSpec(executable).launchArguments;
}
