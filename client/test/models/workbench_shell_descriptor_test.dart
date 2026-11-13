import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workbench_shell_descriptor.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';

void main() {
  test('round-trips every spec variant', () {
    const descriptors = [
      WorkbenchShellDescriptor(
        cwd: '/proj',
        spec: WorkspaceTerminalLocalSpec('/bin/zsh'),
      ),
      WorkbenchShellDescriptor(
        cwd: '',
        spec: WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'),
      ),
      WorkbenchShellDescriptor(
        cwd: '/remote/home',
        spec: WorkspaceTerminalSshProfileSpec('profile-1'),
      ),
    ];
    for (final d in descriptors) {
      final restored = WorkbenchShellDescriptor.fromJson(d.toJson());
      expect(restored, isNotNull);
      expect(restored!.cwd, d.cwd);
      expect(restored.spec, d.spec);
    }
  });

  test('rejects junk shapes and unknown spec types', () {
    expect(WorkbenchShellDescriptor.fromJson(null), isNull);
    expect(WorkbenchShellDescriptor.fromJson('nope'), isNull);
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'cwd': '/p',
        'spec': {'type': 'unknown'},
      }),
      isNull,
    );
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'spec': {'type': 'local', 'shellPath': '/bin/sh'},
      }),
      isNull,
    );
    expect(
      WorkbenchShellDescriptor.fromJson(const {
        'cwd': '/p',
        'spec': {'type': 'local'},
      }),
      isNull,
    );
  });

  test('equality is value-based', () {
    const a = WorkbenchShellDescriptor(
      cwd: '/p',
      spec: WorkspaceTerminalLocalSpec('/bin/sh'),
    );
    const b = WorkbenchShellDescriptor(
      cwd: '/p',
      spec: WorkspaceTerminalLocalSpec('/bin/sh'),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
