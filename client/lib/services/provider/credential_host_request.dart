import '../cli/cli_invocation.dart';
import '../host/host_one_shot_runner.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';

/// Builds [HostRunRequest] for provider credential CLIs on the home host.
class CredentialHostRequest {
  const CredentialHostRequest._();

  static bool usePosixCliPaths(String preferencePath) {
    if (AppStorage.isInstalled) {
      final mode = AppStorage.context.mode;
      if (mode == StorageBackendMode.wsl || mode == StorageBackendMode.ssh) {
        return true;
      }
    }
    return CliInvocation.fromExecutable(preferencePath).usesWsl;
  }

  static String hostExecutable(String preferencePath) {
    final invocation = CliInvocation.fromExecutable(preferencePath);
    if (!invocation.usesWsl) return invocation.executable;
    final linuxExecutable = _wslLinuxExecutable(invocation.prefixArgs);
    return linuxExecutable ?? preferencePath;
  }

  static List<String> hostArguments(
    String preferencePath,
    List<String> subcommand,
  ) {
    final invocation = CliInvocation.fromExecutable(preferencePath);
    if (!invocation.usesWsl) {
      return [...invocation.prefixArgs, ...subcommand];
    }
    final linuxExecutable = _wslLinuxExecutable(invocation.prefixArgs);
    if (linuxExecutable == null) return subcommand;
    final index = invocation.prefixArgs.indexOf(linuxExecutable);
    final trailing =
        index < 0 ? const <String>[] : invocation.prefixArgs.sublist(index + 1);
    return [...trailing, ...subcommand];
  }

  static HostRunRequest build({
    required String preferencePath,
    required List<String> subcommand,
    required Map<String, String> environment,
  }) {
    return HostRunRequest(
      executable: hostExecutable(preferencePath),
      arguments: hostArguments(preferencePath, subcommand),
      environment: environment,
    );
  }

  static String? _wslLinuxExecutable(List<String> prefixArgs) {
    for (final arg in prefixArgs.reversed) {
      if (arg.startsWith('/')) return arg;
    }
    return prefixArgs.isEmpty ? null : prefixArgs.last;
  }
}
