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

  test('CliTool has a codebuddy value that parses round-trip', () {
    expect(CliTool.codebuddy.value, 'codebuddy');
    expect(CliTool.tryParse('codebuddy'), CliTool.codebuddy);
    expect(CliTool.tryParse('CodeBuddy'), CliTool.codebuddy);
  });

  test('CliTool has a qoder value that parses round-trip', () {
    expect(CliTool.qoder.value, 'qoder');
    expect(CliTool.tryParse('qoder'), CliTool.qoder);
    expect(CliTool.tryParse('Qoder'), CliTool.qoder);
  });

  test('CliTool.values length is 8 after adding qoder', () {
    expect(CliTool.values.length, 8);
  });
}
