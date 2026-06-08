import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/codex_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/cursor_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/opencode_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/flashskyai_headless_run_capability.dart';

HeadlessRunContext ctx({String effort = '', String model = 'm'}) =>
    HeadlessRunContext(
      prompt: 'P',
      model: model,
      effort: effort,
      configDir: '/tmp/c',
    );

void main() {
  test('codex: exec + model + effort override + CODEX_HOME', () {
    const cap = CodexHeadlessRunCapability();
    expect(cap.isSupported, isTrue);
    final inv = cap.buildInvocation(ctx(effort: 'high'));
    expect(inv.executable, 'codex');
    expect(inv.arguments.first, 'exec');
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.arguments, containsAllInOrder(['-c', 'model_reasoning_effort=high']));
    expect(inv.arguments.last, 'P');
    expect(inv.environment['CODEX_HOME'], '/tmp/c');
    expect(cap.extractText(ProcessResult(0, 0, ' out ', '')), 'out');
  });

  test('cursor: -p prompt + model + CURSOR_CONFIG_DIR', () {
    const cap = CursorHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'cursor-agent');
    expect(inv.arguments, containsAllInOrder(['-p', 'P']));
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.environment['CURSOR_CONFIG_DIR'], '/tmp/c');
  });

  test('opencode: run prompt + model + OPENCODE_CONFIG_DIR', () {
    const cap = OpencodeHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'opencode');
    expect(inv.arguments.first, 'run');
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.environment['OPENCODE_CONFIG_DIR'], '/tmp/c');
  });

  test('flashskyai: -p print mode', () {
    const cap = FlashskyaiHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'flashskyai');
    expect(inv.arguments, containsAllInOrder(['-p', 'P']));
  });
}
