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

  test('CliTool has an antigravity value that parses round-trip', () {
    expect(CliTool.antigravity.value, 'antigravity');
    expect(CliTool.tryParse('antigravity'), CliTool.antigravity);
    expect(CliTool.tryParse('Antigravity'), CliTool.antigravity);
  });

  test('CliTool has a qoder value that parses round-trip', () {
    expect(CliTool.qoder.value, 'qoder');
    expect(CliTool.tryParse('qoder'), CliTool.qoder);
    expect(CliTool.tryParse('Qoder'), CliTool.qoder);
  });

  test('CliTool has a qoder-cn value that parses round-trip', () {
    expect(CliTool.qoderCn.value, 'qoder-cn');
    expect(CliTool.tryParse('qoder-cn'), CliTool.qoderCn);
    expect(CliTool.tryParse('Qoder-CN'), CliTool.qoderCn);
  });

  test('CliTool has a grok value that parses round-trip', () {
    expect(CliTool.grok.value, 'grok');
    expect(CliTool.tryParse('grok'), CliTool.grok);
    expect(CliTool.tryParse('Grok'), CliTool.grok);
  });

  test('CliTool.values length is 11 after adding grok', () {
    expect(CliTool.values.length, 11);
  });
}
