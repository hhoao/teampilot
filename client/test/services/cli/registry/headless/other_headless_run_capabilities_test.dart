import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/codex/capabilities/headless.dart';
import 'package:teampilot/services/cli/cursor/capabilities/headless.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';
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

  test('codex: promptViaStdin passes - as the prompt positional', () {
    const cap = CodexHeadlessCapability();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.codex)!,
      HeadlessRunContext(
        prompt: 'P',
        model: 'm',
        effort: '',
        configDir: '/tmp/c',
        promptViaStdin: true,
      ),
    );
    expect(cap.supportsPromptStdin, isTrue);
    expect(args.last, '-');
    expect(args.contains('P'), isFalse);
  });

  test('cursor: -p prompt without --model + isolated home env', () {
    const cap = CursorHeadlessCapability();
    final run = ctx();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.cursor)!,
      run,
    );
    expect(args, containsAllInOrder(['-p', 'P']));
    expect(args, isNot(contains('--model')));
    final env = cap.buildEnvironment(run);
    expect(
      env['CURSOR_CONFIG_DIR'],
      p.join('/tmp/c', CursorHomeLayout.cursorDirName),
    );
    expect(env['HOME'], '/tmp/c');
    expect(env['USERPROFILE'], '/tmp/c');
    // POSIX-style temp dir → XDG anchor pinned (deterministic on any host).
    expect(env['XDG_CONFIG_HOME'], '/tmp/c/.config');
    expect(env.containsKey('APPDATA'), isFalse);
    expect(
      env[CursorLaunchEnvironment.credentialStoreEnvKey],
      CursorLaunchEnvironment.credentialStoreFile,
    );
  });

  test('cursor: promptViaStdin omits the argv prompt', () {
    const cap = CursorHeadlessCapability();
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.cursor)!,
      HeadlessRunContext(
        prompt: 'P',
        model: 'm',
        effort: '',
        configDir: '/tmp/c',
        promptViaStdin: true,
      ),
    );
    expect(cap.supportsPromptStdin, isTrue);
    expect(args.contains('P'), isFalse);
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
    final args = const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.flashskyai)!,
      ctx(),
    );
    expect(args, containsAllInOrder(['-p', 'P']));
  });
}
