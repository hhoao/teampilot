import 'dart:io' show Platform;

import '../storage/runtime_storage_context.dart';

/// Shell used to run Claude Code PreToolUse hook scripts.
enum ClaudeHookShell {
  bash,
  powershell,
}

/// Resolves bash vs PowerShell for hook provisioning on the current host.
abstract final class ClaudeHookShellResolver {
  ClaudeHookShellResolver._();

  /// Windows native app data → PowerShell; WSL / Linux / macOS → bash.
  static ClaudeHookShell resolve({StorageBackendMode? storageMode}) {
    if (!Platform.isWindows) return ClaudeHookShell.bash;
    final mode = storageMode ?? _currentStorageMode();
    if (mode == StorageBackendMode.wsl) return ClaudeHookShell.bash;
    return ClaudeHookShell.powershell;
  }

  static StorageBackendMode? _currentStorageMode() {
    try {
      return RuntimeStorageContext.current.mode;
    } on Object {
      return null;
    }
  }

  /// Claude `settings.json` PreToolUse `command` for [scriptPath].
  static String hookCommandForPath(String scriptPath, ClaudeHookShell shell) {
    switch (shell) {
      case ClaudeHookShell.bash:
        final escaped = scriptPath.replaceAll('"', r'\"');
        return 'bash "$escaped"';
      case ClaudeHookShell.powershell:
        final escaped = scriptPath.replaceAll('"', '""');
        return 'powershell -NoProfile -ExecutionPolicy Bypass -File "$escaped"';
    }
  }
}
