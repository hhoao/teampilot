import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/launch_config_schema_fields.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

void main() {
  test('shellScript schema yields enum execute and path fields', () {
    final fields = launchConfigSchemaFields(
      ShellScriptLaunchSchema.configurationSchema,
    );
    final byKey = {for (final f in fields) f.key: f};
    expect(
      fields.map((f) => f.key),
      containsAll([
        'execute',
        'scriptPath',
        'scriptText',
        'env',
        'cwd',
        'executeInTerminal',
      ]),
    );
    expect(byKey['execute']!.type, LaunchConfigSchemaFieldType.enumValue);
    expect(byKey['execute']!.enumValues, ['scriptFile', 'scriptText']);
    expect(byKey['scriptPath']!.type, LaunchConfigSchemaFieldType.string);
    expect(byKey['interpreterPath']!.type, LaunchConfigSchemaFieldType.string);
    expect(byKey['executeInTerminal']!.type, LaunchConfigSchemaFieldType.boolean);
  });

  test('parseArgsText splits on whitespace', () {
    expect(parseLaunchArgsText('a b  c'), ['a', 'b', 'c']);
  });

  test('parseEnvText accepts KEY=VALUE lines', () {
    expect(parseLaunchEnvText('A=1\nB=2'), {'A': '1', 'B': '2'});
  });
}
