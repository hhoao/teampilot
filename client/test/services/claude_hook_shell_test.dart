import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/claude_hook_shell.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  test('hookCommandForPath uses bash or powershell', () {
    expect(
      ClaudeHookShellResolver.hookCommandForPath(
        '/tmp/hooks/foo.sh',
        ClaudeHookShell.bash,
      ),
      'bash "/tmp/hooks/foo.sh"',
    );
    expect(
      ClaudeHookShellResolver.hookCommandForPath(
        r'C:\hooks\foo.ps1',
        ClaudeHookShell.powershell,
      ),
      r'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\hooks\foo.ps1"',
    );
  });

  test('resolve uses bash when not Windows native', () {
    if (Platform.isWindows) {
      expect(
        ClaudeHookShellResolver.resolve(storageMode: StorageBackendMode.wsl),
        ClaudeHookShell.bash,
      );
      return;
    }
    expect(
      ClaudeHookShellResolver.resolve(storageMode: StorageBackendMode.native),
      ClaudeHookShell.bash,
    );
  });

  test('resolve uses powershell for Windows native storage', () {
    if (!Platform.isWindows) return;
    expect(
      ClaudeHookShellResolver.resolve(storageMode: StorageBackendMode.native),
      ClaudeHookShell.powershell,
    );
    expect(
      ClaudeHookShellResolver.resolve(storageMode: StorageBackendMode.wsl),
      ClaudeHookShell.bash,
    );
  });
}
