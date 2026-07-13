import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/services/host/host_interactive_shell.dart';
import 'package:teampilot/services/run/launch_config_l10n.dart';
import 'package:teampilot/services/run/shell_script_configuration.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

void main() {
  test('defaults for new shellScript map', () {
    final withDefaults = ShellScriptLaunchSchema.withDefaults({});
    expect(withDefaults['execute'], 'scriptFile');
    expect(withDefaults['scriptOptions'], '');
    expect(withDefaults['interpreterOptions'], '');
    expect(withDefaults['env'], isA<Map>().having((m) => m.isEmpty, 'empty', true));
    expect(withDefaults['executeInTerminal'], true);
    expect(withDefaults['allowMultipleInstances'], false);
    expect(withDefaults['activateToolWindow'], true);
    expect(withDefaults['focusToolWindow'], false);
    expect(withDefaults['cwd'], r'${workspaceFolder}');
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

  test('validate uses shared LaunchConfigValidationCodes for map/env/cwd', () {
    expect(
      ShellScriptLaunchSchema.validate('not-a-map'),
      [LaunchConfigValidationCodes.configurationMustBeMap],
    );
    expect(
      ShellScriptLaunchSchema.validate({
        'execute': 'scriptFile',
        'scriptPath': './ok.sh',
        'env': 'bad',
        'cwd': 1,
      }),
      containsAll([
        LaunchConfigValidationCodes.envMustBeStringMap,
        LaunchConfigValidationCodes.cwdMustBeString,
      ]),
    );
  });

  test('validate collects all invalid boolean fields', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptFile',
      'scriptPath': './ok.sh',
      'executeInTerminal': 'yes',
      'allowMultipleInstances': 1,
      'activateToolWindow': 'true',
      'focusToolWindow': [],
    });
    expect(
      errors,
      containsAll([
        ShellScriptValidationCodes.executeInTerminalMustBeBoolean,
        ShellScriptValidationCodes.allowMultipleInstancesMustBeBoolean,
        ShellScriptValidationCodes.activateToolWindowMustBeBoolean,
        ShellScriptValidationCodes.focusToolWindowMustBeBoolean,
      ]),
    );
  });

  group('ShellScriptConfiguration.fromLaunchConfiguration', () {
    test('merges known fields and extras', () {
      final config = ShellScriptConfiguration.fromLaunchConfiguration(
        const LaunchConfiguration(
          id: '1',
          name: 'Smoke',
          type: 'shellScript',
          cwd: '/tmp',
          env: {'A': '1'},
          extras: {
            'execute': 'scriptFile',
            'scriptPath': './smoke.sh',
            'scriptOptions': '-x',
            'interpreterOptions': '--login',
            'executeInTerminal': false,
            'allowMultipleInstances': true,
            'activateToolWindow': false,
            'focusToolWindow': true,
          },
        ),
      );
      expect(config.execute, 'scriptFile');
      expect(config.scriptPath, './smoke.sh');
      expect(config.scriptOptions, '-x');
      expect(config.interpreterOptions, '--login');
      expect(config.cwd, '/tmp');
      expect(config.env, {'A': '1'});
      expect(config.executeInTerminal, false);
      expect(config.allowMultipleInstances, true);
      expect(config.activateToolWindow, false);
      expect(config.focusToolWindow, true);
      expect(config.isScriptFile, isTrue);
      expect(config.isScriptText, isFalse);
    });

    test('falls back interpreterPath and bool defaults', () {
      final config = ShellScriptConfiguration.fromLaunchConfiguration(
        const LaunchConfiguration(
          id: '2',
          name: 'Defaults',
          type: 'shellScript',
          extras: {
            'execute': 'scriptText',
            'scriptText': 'echo hi',
            'interpreterPath': '  ',
          },
        ),
      );
      expect(config.interpreterPath, ShellScriptLaunchSchema.defaultInterpreterPath());
      expect(config.executeInTerminal, true);
      expect(config.allowMultipleInstances, false);
      expect(config.activateToolWindow, true);
      expect(config.focusToolWindow, false);
      expect(config.isScriptFile, isFalse);
      expect(config.isScriptText, isTrue);
    });

    test('defaults missing or blank cwd to workspaceFolder', () {
      final missing = ShellScriptConfiguration.fromLaunchConfiguration(
        const LaunchConfiguration(
          id: '3',
          name: 'No cwd',
          type: 'shellScript',
          extras: {'execute': 'scriptFile', 'scriptPath': './a.sh'},
        ),
      );
      expect(missing.cwd, r'${workspaceFolder}');

      final blank = ShellScriptConfiguration.fromLaunchConfiguration(
        const LaunchConfiguration(
          id: '4',
          name: 'Blank cwd',
          type: 'shellScript',
          cwd: '   ',
          extras: {'execute': 'scriptFile', 'scriptPath': './a.sh'},
        ),
      );
      expect(blank.cwd, r'${workspaceFolder}');
    });
  });
}
