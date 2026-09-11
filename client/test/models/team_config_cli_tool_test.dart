// client/test/models/team_config_cli_tool_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('CliTool has a gemini value that parses round-trip', () {
    expect(CliTool.gemini.value, 'gemini');
    expect(CliTool.tryParse('gemini'), CliTool.gemini);
    expect(CliTool.tryParse('GEMINI'), CliTool.gemini);
    expect(CliTool.tryParse('not-a-cli'), isNull);
  });

  test('CliTool.values length is 6 after adding gemini', () {
    expect(CliTool.values.length, 6);
  });
}
