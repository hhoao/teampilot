import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_type_contribution.dart';
import 'package:teampilot/services/run/launch_type_normalize.dart';
import 'package:teampilot/services/run/launch_type_registry.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

LaunchTypeContribution _flutterContrib(String extensionId) {
  return LaunchTypeContribution(
    extensionId: extensionId,
    type: 'flutter',
    kinds: const ['run'],
    adapterCommand: r'${extensionPath}/bin/adapter',
    adapterRuntime: 'workspace',
    lifecycle: LaunchAdapterLifecycle.sticky,
    configurationSchema: const {
      'type': 'object',
      'required': ['device'],
      'properties': {
        'device': {'type': 'string'},
      },
    },
    discover: const {'enabled': true, 'globs': ['pubspec.yaml']},
  );
}

void main() {
  test('shellScript type is always registered; process is not', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    final shell = reg.get(ShellScriptLaunchSchema.typeName);
    expect(shell, isNotNull);
    expect(shell!.extensionId, isNull);
    expect(shell.configurationSchema, isNotNull);
    expect(shell.kinds, ['run']);
    expect(reg.get('process'), isNull);
  });

  test('isBuiltInShellType only matches shellScript', () {
    expect(isBuiltInShellType('shellScript'), isTrue);
    expect(isBuiltInShellType('process'), isFalse);
    expect(isBuiltInShellType('flutter'), isFalse);
  });

  test('duplicate type from two extensions marks conflict', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    final contribFlutterA = _flutterContrib('ext.flutter.a');
    reg.registerExtension(contribFlutterA);
    final result = reg.registerExtension(_flutterContrib('ext.flutter.b'));
    expect(result.isConflict, isTrue);
    expect(reg.get('flutter')?.extensionId, contribFlutterA.extensionId);
  });

  test('isAvailable returns true for shellScript, false for extension types', () {
    final reg = LaunchTypeRegistry.withBuiltIns();
    reg.registerExtension(_flutterContrib('ext.flutter'));
    expect(reg.isAvailable('shellScript', targetId: 'local'), isTrue);
    expect(reg.isAvailable('process', targetId: 'local'), isFalse);
    expect(reg.isAvailable('flutter', targetId: 'local'), isFalse);
  });

  test('shellScript schema requires execute / scriptPath', () {
    final errors = ShellScriptLaunchSchema.validate({
      'id': 'x',
      'name': 'X',
      'type': 'shellScript',
      'execute': 'scriptFile',
    });
    expect(errors, isNotEmpty);
    expect(errors, contains(ShellScriptValidationCodes.scriptPathRequired));
  });

  test('shellScript schema accepts scriptFile with optional fields', () {
    final errors = ShellScriptLaunchSchema.validate({
      'id': 'x',
      'name': 'X',
      'type': 'shellScript',
      'execute': 'scriptFile',
      'scriptPath': './run.sh',
      'env': {'NODE_ENV': 'development'},
      'cwd': r'${workspaceFolder}',
      'executeInTerminal': false,
    });
    expect(errors, isEmpty);
  });
}
