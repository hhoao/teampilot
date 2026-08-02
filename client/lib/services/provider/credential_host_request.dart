import '../cli/cli_invocation.dart';
import '../host/host_one_shot_runner.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';

/// Builds [HostRunRequest] for provider credential CLIs on the home host.
class CredentialHostRequest {
  const CredentialHostRequest._();

  /// True when login env should normalize paths for a POSIX/WSL CLI.
  ///
  /// WSL/SSH home contexts always use POSIX paths. On native Windows, a
  /// `wsl.exe …` preference path still runs inside WSL and needs WSL path
  /// normalization in login environment variables.
  static bool usePosixCliPaths(
    String preferencePath, {
    StorageBackendMode? modeOverride,
  }) {
    final mode = _resolvedMode(modeOverride);
    if (mode == StorageBackendMode.wsl || mode == StorageBackendMode.ssh) {
      return true;
    }
    return CliInvocation.fromExecutable(preferencePath).usesWsl;
  }

  static String hostExecutable(
    String preferencePath, {
    StorageBackendMode? modeOverride,
  }) {
    final invocation = CliInvocation.fromExecutable(preferencePath);
    if (!invocation.usesWsl) return invocation.executable;
    if (!_shouldUnwrapWsl(modeOverride)) return invocation.executable;
    final linuxExecutable = _wslLinuxExecutable(invocation.prefixArgs);
    return linuxExecutable ?? preferencePath;
  }

  static List<String> hostArguments(
    String preferencePath,
    List<String> subcommand, {
    StorageBackendMode? modeOverride,
  }) {
    final invocation = CliInvocation.fromExecutable(preferencePath);
    if (!invocation.usesWsl) {
      return [...invocation.prefixArgs, ...subcommand];
    }
    if (!_shouldUnwrapWsl(modeOverride)) {
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
    StorageBackendMode? modeOverride,
  }) {
    return HostRunRequest(
      executable: hostExecutable(preferencePath, modeOverride: modeOverride),
      arguments: hostArguments(
        preferencePath,
        subcommand,
        modeOverride: modeOverride,
      ),
      environment: environment,
    );
  }

  static StorageBackendMode? _resolvedMode(StorageBackendMode? modeOverride) {
    if (modeOverride != null) return modeOverride;
    if (!AppStorage.isInstalled) return null;
    return AppStorage.context.mode;
  }

  /// Unwrap `wsl.exe … /linux/bin` only when the home starter is already WSL
  /// or SSH (POSIX host). On native Windows, keep `wsl.exe` so
  /// [LocalHostProcessStarter] launches WSL correctly.
  static bool _shouldUnwrapWsl(StorageBackendMode? modeOverride) {
    final mode = _resolvedMode(modeOverride);
    return mode == StorageBackendMode.wsl || mode == StorageBackendMode.ssh;
  }

  static String? _wslLinuxExecutable(List<String> prefixArgs) {
    for (final arg in prefixArgs.reversed) {
      if (arg.startsWith('/')) return arg;
    }
    return prefixArgs.isEmpty ? null : prefixArgs.last;
  }
}
