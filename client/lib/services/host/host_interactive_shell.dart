import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'host_interactive_shell_kind.dart';

/// Resolved argv for spawning an interactive login shell in a PTY.
@immutable
class HostInteractiveShellSpec {
  const HostInteractiveShellSpec({
    required this.executable,
    required this.kind,
    this.launchArguments = const [],
  });

  final String executable;
  final HostInteractiveShellKind kind;
  final List<String> launchArguments;

  String get menuLabel => HostInteractiveShell.menuLabelFor(executable);
}

/// Discovers and launches user-facing interactive shells (bash, zsh, cmd, …).
///
/// Distinct from [HostLoginShellLookup] (runs a command *inside* a login shell to
/// locate CLIs) and from [HostScriptDialect] (installer/hook scripts).
abstract final class HostInteractiveShell {
  HostInteractiveShell._();

  static const remotePosixExecutable = '/bin/bash';

  static const _posixCandidates = [
    '/bin/zsh',
    '/usr/bin/zsh',
    '/bin/bash',
    '/usr/bin/bash',
    '/bin/fish',
    '/usr/bin/fish',
  ];

  /// Default interactive shell for the current host OS.
  static HostInteractiveShellSpec defaultSpec() =>
      resolveSpec(Platform.environment[Platform.isWindows ? 'COMSPEC' : 'SHELL']);

  static String defaultExecutable() => defaultSpec().executable;

  /// Returns a spec with an on-disk [executable], falling back through candidates.
  static HostInteractiveShellSpec resolveSpec(String? preferred) {
    final path = resolvePath(preferred);
    final kind = HostInteractiveShellKind.fromExecutable(path);
    return HostInteractiveShellSpec(
      executable: path,
      kind: kind,
      launchArguments: launchArgumentsFor(kind),
    );
  }

  /// Executable path that exists on disk (last-resort literal if none found).
  static String resolvePath(String? preferred) {
    if (Platform.isWindows) {
      return _resolveWindowsPath(preferred);
    }
    final trimmed = preferred?.trim() ?? '';
    if (trimmed.isNotEmpty && _exists(trimmed)) return trimmed;
    for (final candidate in discoverPaths()) {
      if (_exists(candidate)) return candidate;
    }
    return '/bin/bash';
  }

  static String _resolveWindowsPath(String? preferred) {
    final trimmed = preferred?.trim() ?? '';
    if (trimmed.isNotEmpty && _exists(trimmed)) return trimmed;
    for (final candidate in _windowsCandidatePaths()) {
      if (_exists(candidate)) return candidate;
    }
    return r'cmd.exe';
  }

  static List<String> _windowsCandidatePaths() {
    final systemRoot =
        Platform.environment['SystemRoot']?.trim() ?? r'C:\Windows';
    final sys32 = p.join(systemRoot, 'System32');
    return [
      Platform.environment['COMSPEC'] ?? '',
      p.join(sys32, 'cmd.exe'),
      p.join(sys32, 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
      r'C:\Program Files\PowerShell\7\pwsh.exe',
      r'C:\Program Files (x86)\PowerShell\7\pwsh.exe',
    ].where((path) => path.trim().isNotEmpty).toList(growable: false);
  }

  /// Menu / picker entries — only paths that exist locally.
  static List<HostInteractiveShellSpec> discoverSpecs() {
    return discoverPaths()
        .map(resolveSpec)
        .toList(growable: false);
  }

  static List<String> discoverPaths() {
    if (Platform.isWindows) {
      return _windowsCandidatePaths().where(_exists).toList(growable: false);
    }
    final seen = <String>{};
    final paths = <String>[];
    void add(String? raw) {
      final trimmed = raw?.trim() ?? '';
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      paths.add(trimmed);
    }

    add(Platform.environment['SHELL']);
    for (final candidate in _posixCandidates) {
      add(candidate);
    }
    if (paths.isEmpty) add('/bin/bash');
    return paths.where(_exists).toList(growable: false);
  }

  static String menuLabelFor(String shellPath) {
    final trimmed = shellPath.trim();
    if (trimmed.isEmpty) return 'shell';
    final kind = HostInteractiveShellKind.fromExecutable(trimmed);
    final name = switch (kind) {
      HostInteractiveShellKind.powershell => 'PowerShell',
      HostInteractiveShellKind.pwsh => 'PowerShell 7',
      HostInteractiveShellKind.cmd => 'Command Prompt',
      HostInteractiveShellKind.bash => 'bash',
      HostInteractiveShellKind.zsh => 'zsh',
      HostInteractiveShellKind.fish => 'fish',
      HostInteractiveShellKind.unknown => p.basename(trimmed),
    };
    return '$name ($trimmed)';
  }

  static List<String> launchArgumentsFor(HostInteractiveShellKind kind) {
    return switch (kind) {
      HostInteractiveShellKind.bash ||
      HostInteractiveShellKind.zsh ||
      HostInteractiveShellKind.fish => const ['-l'],
      HostInteractiveShellKind.powershell ||
      HostInteractiveShellKind.pwsh => const ['-NoLogo'],
      HostInteractiveShellKind.cmd || HostInteractiveShellKind.unknown => const [],
    };
  }

  /// PTY argv for `wsl.exe` (basename + login flags).
  static List<String> wslArgumentsFor(HostInteractiveShellSpec shell) {
    return [
      p.basename(shell.executable),
      ...shell.launchArguments,
    ];
  }

  static bool _exists(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }
}
