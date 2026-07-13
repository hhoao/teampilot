import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/services/run/shell_script_command_builder.dart';
import 'package:teampilot/services/run/shell_script_configuration.dart';

void main() {
  const builder = ShellScriptCommandBuilder();

  group('buildInjectLine', () {
    test('scriptFile inject line with cd + bash + path + options', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptFile',
          scriptPath: './scripts/a.sh',
          scriptOptions: '--flag',
          interpreterPath: '/bin/bash',
          cwd: '/proj',
        ),
      );
      expect(line, "cd '/proj' && '/bin/bash' './scripts/a.sh' --flag");
    });

    test('scriptText with -c and quoting', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptText',
          scriptText: 'echo hi',
          interpreterPath: '/bin/bash',
          cwd: '/proj',
        ),
      );
      expect(line, "cd '/proj' && '/bin/bash' -c 'echo hi'");
    });

    test('env export prefix after cd', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptFile',
          scriptPath: './a.sh',
          interpreterPath: '/bin/bash',
          cwd: '/proj',
          env: {'FOO': 'bar'},
        ),
      );
      expect(
        line,
        "cd '/proj' && export 'FOO'='bar' && '/bin/bash' './a.sh'",
      );
    });

    test('multiple env exports are &&-joined and keys quoted', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptFile',
          scriptPath: './a.sh',
          interpreterPath: '/bin/bash',
          cwd: '/proj',
          env: {'FOO': 'bar', 'BAZ': 'qux'},
        ),
      );
      expect(
        line,
        "cd '/proj' && export 'FOO'='bar' && export 'BAZ'='qux' && "
        "'/bin/bash' './a.sh'",
      );
    });

    test('paths with spaces are quoted', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptFile',
          scriptPath: '/my scripts/run me.sh',
          interpreterPath: '/usr/local/bin/my bash',
          interpreterOptions: '-x',
          cwd: '/proj with spaces',
        ),
      );
      expect(
        line,
        "cd '/proj with spaces' && '/usr/local/bin/my bash' -x "
        "'/my scripts/run me.sh'",
      );
    });

    test('scriptText escapes embedded single quotes', () {
      final line = builder.buildInjectLine(
        const ShellScriptConfiguration(
          execute: 'scriptText',
          scriptText: "echo 'hi'",
          interpreterPath: '/bin/bash',
          cwd: '/proj',
        ),
      );
      expect(line, "cd '/proj' && '/bin/bash' -c 'echo '\\''hi'\\'''");
    });
  });

  group('buildProcessInvocation', () {
    test('non-terminal uses host shell -c with full inject line', () {
      final invocation = builder.buildProcessInvocation(
        const ShellScriptConfiguration(
          execute: 'scriptText',
          scriptText: 'echo hi',
          interpreterPath: '/bin/bash',
          cwd: '/proj',
          env: {'FOO': 'bar'},
        ),
      );
      expect(invocation.shell, isTrue);
      expect(invocation.command, HostInteractiveShell.defaultExecutable());
      expect(invocation.args, [
        '-c',
        "cd '/proj' && export 'FOO'='bar' && '/bin/bash' -c 'echo hi'",
      ]);
      expect(invocation.cwd, '/proj');
      expect(invocation.env, {'FOO': 'bar'});
    });
  });
}
