import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/launch_config_schema_fields.dart';
import 'package:teampilot/services/run/process_launch_schema.dart';

void main() {
  test('process schema yields command args cwd env shell fields', () {
    final fields = launchConfigSchemaFields(
      ProcessLaunchSchema.configurationSchema,
    );
    expect(
      fields.map((f) => f.key),
      containsAll(['command', 'args', 'env', 'cwd', 'shell']),
    );
  });

  test('parseArgsText splits on whitespace', () {
    expect(parseLaunchArgsText('a b  c'), ['a', 'b', 'c']);
  });

  test('parseEnvText accepts KEY=VALUE lines', () {
    expect(parseLaunchEnvText('A=1\nB=2'), {'A': '1', 'B': '2'});
  });
}
