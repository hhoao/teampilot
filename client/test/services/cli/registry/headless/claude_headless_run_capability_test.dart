import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/headless.dart';
import 'package:teampilot/services/cli/claude/claude_tool.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';

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
  const cap = ClaudeHeadlessCapability();

  test('isSupported is true', () => expect(cap.isSupported, isTrue));

  test('headless assembler passes prompt, model, json flag and config env', () {
    final ctx = _ctx(expectJson: true);
    final args = const CliLaunchArgAssembler().assembleHeadless(
      ClaudeCliTool(),
      ctx,
    );
    expect(args, [
      '-p',
      '--model',
      'sonnet',
      'Write a commit message',
      '--output-format',
      'json',
    ]);
    expect(cap.buildEnvironment(ctx)['CLAUDE_CONFIG_DIR'], '/tmp/cfg');
  });

  test('headless assembler omits json flag when expectJson is false', () {
    final args = const CliLaunchArgAssembler().assembleHeadless(
      ClaudeCliTool(),
      _ctx(),
    );
    expect(args.contains('--output-format'), isFalse);
  });

  test('configFiles is empty (settings come from provision)', () {
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

  test('supportsStreaming and stream args', () {
    expect(cap.supportsStreaming, isTrue);
    final args = const CliLaunchArgAssembler().assembleHeadless(
      ClaudeCliTool(),
      _ctx(),
    );
    // non-stream ctx: no stream flags
    expect(args.contains('stream-json'), isFalse);
  });

  test('streamResultText extracts the terminal result event', () {
    expect(cap.streamResultText('{"type":"result","result":"hello"}'), 'hello');
    expect(cap.streamResultText('{"type":"assistant"}'), isNull);
    expect(cap.streamResultText('not json'), isNull);
  });

  test('stream ctx adds --output-format stream-json --verbose', () {
    final args = const CliLaunchArgAssembler().assembleHeadless(
      ClaudeCliTool(),
      const HeadlessLaunchContext(
        prompt: 'x',
        model: 'sonnet',
        effort: '',
        configDir: '/tmp/cfg',
        stream: true,
      ),
    );
    expect(
      args,
      containsAllInOrder(['--output-format', 'stream-json', '--verbose']),
    );
  });
}
