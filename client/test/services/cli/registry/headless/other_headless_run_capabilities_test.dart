import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_headless_launch_context.dart';
import 'package:teampilot/services/cli/codex/capabilities/headless.dart';
import 'package:teampilot/services/cli/cursor/capabilities/headless.dart';
import 'package:teampilot/services/cli/opencode/capabilities/headless.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/headless.dart';

HeadlessRunContext ctx({String effort = '', String model = 'm'}) =>
    HeadlessRunContext(
      prompt: 'P',
      model: model,
      effort: effort,
      configDir: '/tmp/c',
    );

void main() {
  test('codex: exec + model + effort override + CODEX_HOME', () {
    const cap = CodexHeadlessCapability();
    expect(cap.isSupported, isTrue);
    final run = ctx(effort: 'high');
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.codex)!,
      run,
    );
    expect(args.first, 'exec');
    expect(args, containsAllInOrder(['--model', 'm']));
    expect(args, containsAllInOrder(['-c', 'model_reasoning_effort=high']));
    expect(args.last, 'P');
    expect(cap.buildEnvironment(run)['CODEX_HOME'], '/tmp/c');
    expect(cap.extractText(ProcessResult(0, 0, ' out ', '')), 'out');
  });

  test('cursor: -p prompt without --model + CURSOR_CONFIG_DIR', () {
    const cap = CursorHeadlessCapability();
    final run = ctx();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.cursor)!,
      run,
    );
    expect(args, containsAllInOrder(['-p', 'P']));
    expect(args, isNot(contains('--model')));
    expect(cap.buildEnvironment(run)['CURSOR_CONFIG_DIR'], '/tmp/c');
  });

  test('opencode: run prompt + model + OPENCODE_CONFIG_DIR', () {
    const cap = OpencodeHeadlessCapability();
    final run = ctx();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.opencode)!,
      run,
    );
    expect(args.first, 'run');
    expect(args, containsAllInOrder(['--model', 'm', 'P']));
    expect(cap.buildEnvironment(run)['OPENCODE_CONFIG_DIR'], '/tmp/c');
  });

  test('flashskyai: -p print mode', () {
    const cap = FlashskyaiHeadlessCapability();
    final run = ctx();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.flashskyai)!,
      run,
    );
    expect(args, containsAllInOrder(['-p', 'P']));
  });
}
