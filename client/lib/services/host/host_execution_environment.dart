import 'dart:io' show Platform;

import '../storage/runtime_storage_context.dart';
import 'host_script_dialect.dart';
import 'host_script_runner.dart';

/// Resolved host context for script dialect and executable lookup.
final class HostExecutionEnvironment {
  const HostExecutionEnvironment({
    required this.dialect,
    required this.isWindowsHost,
    required this.storageMode,
  });

  final HostScriptDialect dialect;
  final bool isWindowsHost;
  final StorageBackendMode storageMode;

  bool get usesPosixExecution => dialect == HostScriptDialect.bash;

  HostScriptRunner get scriptRunner => HostScriptRunner(this);

  /// Windows native app data → PowerShell; WSL / Linux / macOS / SSH → bash.
  static HostExecutionEnvironment resolve({
    bool? isWindowsHost,
    StorageBackendMode? storageMode,
    bool forceRemoteUnix = false,
  }) {
    final windows = isWindowsHost ?? Platform.isWindows;
    final mode = storageMode ?? _currentStorageMode() ?? StorageBackendMode.native;

    final dialect = _resolveDialect(
      isWindowsHost: windows,
      storageMode: mode,
      forceRemoteUnix: forceRemoteUnix,
    );

    return HostExecutionEnvironment(
      dialect: dialect,
      isWindowsHost: windows,
      storageMode: mode,
    );
  }

  static HostExecutionEnvironment fromStorage(RuntimeStorageContext ctx) {
    return resolve(
      storageMode: ctx.mode,
      isWindowsHost: Platform.isWindows,
      forceRemoteUnix: ctx.mode == StorageBackendMode.ssh,
    );
  }

  static HostScriptDialect _resolveDialect({
    required bool isWindowsHost,
    required StorageBackendMode storageMode,
    required bool forceRemoteUnix,
  }) {
    if (forceRemoteUnix) return HostScriptDialect.bash;
    if (!isWindowsHost) return HostScriptDialect.bash;
    if (storageMode == StorageBackendMode.wsl) return HostScriptDialect.bash;
    if (storageMode == StorageBackendMode.ssh) return HostScriptDialect.bash;
    return HostScriptDialect.powershell;
  }

  static StorageBackendMode? _currentStorageMode() {
    try {
      return RuntimeStorageContext.current.mode;
    } on Object {
      return null;
    }
  }
}
