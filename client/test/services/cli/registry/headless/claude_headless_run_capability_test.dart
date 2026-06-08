import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/claude_headless_run_capability.dart';

HeadlessRunContext _ctx({
  String model = 'sonnet',
  String effort = '',
  bool expectJson = false,
}) => HeadlessRunContext(
      prompt: 'Write a commit message',
      model: model,
      effort: effort,
      configDir: '/tmp/cfg',
      expectJson: expectJson,
    );

void main() {
  const cap = ClaudeHeadlessRunCapability();

  test('isSupported is true', () => expect(cap.isSupported, isTrue));

  test('buildInvocation passes -p, model, json flag and CONFIG_DIR env', () {
    final inv = cap.buildInvocation(_ctx(expectJson: true));
    expect(inv.executable, 'claude');
    expect(inv.arguments, [
      '-p', 'Write a commit message',
      '--model', 'sonnet',
      '--output-format', 'json',
    ]);
    expect(inv.environment['CLAUDE_CONFIG_DIR'], '/tmp/cfg');
  });

  test('buildInvocation omits json flag when expectJson is false', () {
    final inv = cap.buildInvocation(_ctx());
    expect(inv.arguments.contains('--output-format'), isFalse);
  });

  test('configFiles is empty (settings come from HeadlessProvisionCapability)', () {
    expect(cap.configFiles(_ctx(effort: 'high')), isEmpty);
  });

  test('extractText unwraps the JSON result field', () {
    final r = ProcessResult(0, 0, '{"result":"feat: add thing"}', '');
    expect(cap.extractText(r), 'feat: add thing');
  });

  test('extractText returns raw stdout when not JSON', () {
    final r = ProcessResult(0, 0, 'feat: plain text', '');
    expect(cap.extractText(r), 'feat: plain text');
  });
}
