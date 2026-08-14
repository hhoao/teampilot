import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/hook/import/hook_event_name_mapper.dart';

void main() {
  test('claude maps PascalCase names', () {
    expect(HookEventNameMapper.map(CliTool.claude, 'PreToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.claude, 'StopFailure'),
        HookEvent.stopFailure);
    expect(HookEventNameMapper.map(CliTool.claude, 'Notification'),
        HookEvent.notification);
    expect(HookEventNameMapper.map(CliTool.claude, 'PostCompact'), isNull);
  });

  test('codex maps its subset (no PostToolUseFailure/StopFailure/Notification)',
      () {
    expect(HookEventNameMapper.map(CliTool.codex, 'PreToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.codex, 'PostToolUseFailure'),
        isNull);
    expect(HookEventNameMapper.map(CliTool.codex, 'PostCompact'), isNull);
  });

  test('cursor maps lowercase names incl beforeShellExecution approximation', () {
    expect(HookEventNameMapper.map(CliTool.cursor, 'beforeSubmitPrompt'),
        HookEvent.userPromptSubmit);
    expect(HookEventNameMapper.map(CliTool.cursor, 'preToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.cursor, 'beforeShellExecution'),
        HookEvent.shellCommandRequest);
    expect(HookEventNameMapper.map(CliTool.cursor, 'afterAgentResponse'),
        isNull);
  });

  test('flashskyai shares claude table; opencode unsupported', () {
    expect(HookEventNameMapper.map(CliTool.flashskyai, 'Stop'),
        HookEvent.stop);
    expect(HookEventNameMapper.map(CliTool.opencode, 'PreToolUse'), isNull);
  });
}
