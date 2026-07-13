import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

void main() {
  test('defaults for new shellScript map', () {
    final withDefaults = ShellScriptLaunchSchema.withDefaults({});
    expect(withDefaults['execute'], 'scriptFile');
    expect(withDefaults['executeInTerminal'], true);
    expect(withDefaults['allowMultipleInstances'], false);
    expect(withDefaults['activateToolWindow'], true);
    expect(withDefaults['focusToolWindow'], false);
    expect(
      withDefaults['interpreterPath'],
      ShellScriptLaunchSchema.defaultInterpreterPath(),
    );
    expect(
      withDefaults['interpreterPath'],
      HostInteractiveShell.defaultExecutable(),
    );
  });

  test('validate requires scriptPath when execute is scriptFile', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptFile',
      'scriptPath': '',
    });
    expect(errors, contains(ShellScriptValidationCodes.scriptPathRequired));
  });

  test('validate requires scriptText when execute is scriptText', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptText',
      'scriptText': '  ',
    });
    expect(errors, contains(ShellScriptValidationCodes.scriptTextRequired));
  });

  test('validate accepts scriptFile with path', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptFile',
      'scriptPath': './scripts/smoke.sh',
    });
    expect(errors, isEmpty);
  });
}
