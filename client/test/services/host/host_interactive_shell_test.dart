import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/services/host/host_interactive_shell_kind.dart';

void main() {
  group('HostInteractiveShellKind', () {
    test('fromExecutable recognizes common shells', () {
      expect(
        HostInteractiveShellKind.fromExecutable('/bin/bash'),
        HostInteractiveShellKind.bash,
      );
      expect(
        HostInteractiveShellKind.fromExecutable(r'C:\Windows\System32\cmd.exe'),
        HostInteractiveShellKind.cmd,
      );
      expect(
        HostInteractiveShellKind.fromExecutable('pwsh.exe'),
        HostInteractiveShellKind.pwsh,
      );
    });
  });

  group('HostInteractiveShell', () {
    test('resolvePath falls back to an existing shell', () {
      final resolved = HostInteractiveShell.resolvePath('/no/such/shell');
      expect(File(resolved).existsSync(), isTrue);
    });

    test('resolveSpec attaches login flags for bash', () {
      if (Platform.isWindows) return;
      final spec = HostInteractiveShell.resolveSpec('/bin/bash');
      expect(spec.kind, HostInteractiveShellKind.bash);
      expect(spec.launchArguments, const ['-l']);
    });

    test('discoverPaths only returns existing executables', () {
      for (final path in HostInteractiveShell.discoverPaths()) {
        expect(File(path).existsSync(), isTrue);
      }
    });

    test('menuLabelFor uses friendly names', () {
      expect(
        HostInteractiveShell.menuLabelFor('/bin/zsh'),
        'zsh (/bin/zsh)',
      );
    });
  });
}
