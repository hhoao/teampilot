import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';

AiToolCallPart tool(String name) =>
    AiToolCallPart(toolCallId: '1', toolName: name);

void main() {
  const resolver = defaultToolCallCategoryResolver;

  test('known names resolve to expected categories', () {
    expect(resolver.resolve(tool('Read')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('glob')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('write')), AiToolCallCategory.write);
    expect(resolver.resolve(tool('strreplace')), AiToolCallCategory.edit);
    expect(resolver.resolve(tool('bash')), AiToolCallCategory.command);
    expect(resolver.resolve(tool('web_search')), AiToolCallCategory.search);
    expect(resolver.resolve(tool('browser_act')), AiToolCallCategory.browser);
    expect(resolver.resolve(tool('task')), AiToolCallCategory.subagent);
    expect(resolver.resolve(tool('TodoWrite')), AiToolCallCategory.task);
    expect(
      resolver.resolve(tool('AskUserQuestion')),
      AiToolCallCategory.askUser,
    );
    expect(resolver.resolve(tool('ExitPlanMode')), AiToolCallCategory.plan);
  });

  test('case-insensitive matching', () {
    expect(resolver.resolve(tool('READ')), AiToolCallCategory.read);
    expect(resolver.resolve(tool('Bash')), AiToolCallCategory.command);
  });

  test('mcp__ prefix maps to mcp', () {
    expect(
      resolver.resolve(tool('mcp__github__get_issue')),
      AiToolCallCategory.mcp,
    );
  });

  test('unknown names map to other', () {
    expect(resolver.resolve(tool('custom_tool_call')), AiToolCallCategory.other);
    expect(resolver.resolve(tool('random_thing')), AiToolCallCategory.other);
  });

  test('ConfigurableAiToolCallCategoryResolver supports custom rules', () {
    const custom = ConfigurableAiToolCallCategoryResolver(
      nameRules: {'mine': AiToolCallCategory.task},
      prefixRules: [('ext__', AiToolCallCategory.mcp)],
    );
    expect(custom.resolve(tool('mine')), AiToolCallCategory.task);
    expect(custom.resolve(tool('ext__foo')), AiToolCallCategory.mcp);
    expect(custom.resolve(tool('bash')), AiToolCallCategory.other);
  });
}
