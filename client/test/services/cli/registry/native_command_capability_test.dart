import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('built-in tools expose only the approved native command matrix', () {
    final registry = CliToolRegistry.builtIn();
    List<String> names(CliTool cli) => registry
        .capability<NativeCommandCapability>(cli)!
        .commands
        .map((command) => command.name)
        .toList();

    expect(names(CliTool.codex), ['goal', 'compact', 'help']);
    expect(names(CliTool.claude), ['goal', 'compact', 'plan', 'help']);
    expect(names(CliTool.flashskyai), ['help']);
    expect(names(CliTool.opencode), ['compact', 'help']);
    expect(names(CliTool.cursor), ['goal', 'help']);

    final cursorGoal = registry
        .capability<NativeCommandCapability>(CliTool.cursor)!
        .commands
        .firstWhere((command) => command.name == 'goal');
    expect(cursorGoal.availability, NativeCommandAvailability.experimental);
    expect(cursorGoal.argumentHint, '<objective>');
  });

  test('normalizes one leading slash from command names', () {
    const command = NativeCommand(
      name: '/compact',
      description: NativeCommandDescription.compact,
    );

    expect(command.slashName, 'compact');
    expect(command.insertText, '/compact');
  });

  test('agent-provided descriptions do not require an enum value', () {
    const command = NativeCommand(
      name: 'create_plan',
      descriptionText: 'Create an implementation plan',
      argumentHint: '<what>',
    );

    expect(command.description, isNull);
    expect(command.descriptionText, 'Create an implementation plan');
    expect(command.insertText, '/create_plan ');
  });
}
