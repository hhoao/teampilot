import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/headless.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';

List<String> argsFor(CliHeadlessLaunchContext ctx) =>
    const AntigravityHeadlessCapability()
        .buildHeadlessLaunchArgs(ctx)
        .expand((contribution) => contribution.args)
        .toList();

CliHeadlessLaunchContext ctx({
  String prompt = 'hi',
  String model = 'gemini-3.8-flash-medium',
  String effort = 'high',
  LaunchSecurityPolicy securityPolicy = LaunchSecurityPolicy.fullAccess,
  bool stream = false,
  bool expectJson = false,
  bool promptViaStdin = false,
}) => CliHeadlessLaunchContext(
  prompt: prompt,
  model: model,
  effort: effort,
  configDir: '/cfg',
  securityPolicy: securityPolicy,
  stream: stream,
  expectJson: expectJson,
  promptViaStdin: promptViaStdin,
);

void main() {
  const cap = AntigravityHeadlessCapability();

  group('executable and support flags', () {
    test('runs agy with isolated streaming support', () {
      expect(cap.executable, 'agy');
      expect(cap.isSupported, isTrue);
      expect(cap.supportsStreaming, isTrue);
      expect(cap.supportsPromptStdin, isTrue);
    });
  });

  group('argv', () {
    test('builds agy headless argv', () {
      final args = argsFor(
        ctx(stream: true, securityPolicy: LaunchSecurityPolicy.fullAccess),
      );
      expect(args, containsAllInOrder(['-p', 'hi']));
      expect(args, containsAllInOrder(['--model', 'gemini-3.8-flash-medium']));
      expect(args, containsAllInOrder(['--effort', 'high']));
      expect(args, contains('--dangerously-skip-permissions'));
      expect(args, containsAllInOrder(['--output-format', 'stream-json']));
    });

    test('omits model and effort when unset', () {
      final args = argsFor(ctx(model: '', effort: ''));
      expect(args, containsAllInOrder(['-p', 'hi']));
      expect(args, isNot(contains('--model')));
      expect(args, isNot(contains('--effort')));
    });

    test('omits the dangerous flag outside full access', () {
      final args = argsFor(
        ctx(securityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted),
      );
      expect(args, isNot(contains('--dangerously-skip-permissions')));
    });

    test('expectJson selects the json output format', () {
      final args = argsFor(ctx(expectJson: true));
      expect(args, containsAllInOrder(['--output-format', 'json']));
      expect(args, isNot(contains('stream-json')));
    });

    test('stream wins over expectJson and is never passed twice', () {
      final args = argsFor(ctx(expectJson: true, stream: true));
      expect(args, containsAllInOrder(['--output-format', 'stream-json']));
      expect(args.where((arg) => arg == '--output-format'), hasLength(1));
      expect(args, isNot(contains('json')));
    });

    test('promptViaStdin omits the argv prompt', () {
      final args = argsFor(ctx(promptViaStdin: true));
      expect(args, isNot(contains('hi')));
      expect(args, isNot(contains('-p')));
      expect(args, containsAllInOrder(['--model', 'gemini-3.8-flash-medium']));
    });
  });

  group('environment', () {
    test('pins the isolated home inside the config dir', () {
      final env = cap.buildEnvironment(ctx());
      expect(env['HOME'], '/cfg/home');
      expect(env['USERPROFILE'], '/cfg/home');
      expect(env['GEMINI_HOME'], '/cfg/home/.gemini');
    });

    test('does not duplicate provider credential env', () {
      final env = cap.buildEnvironment(ctx());
      expect(env.keys, unorderedEquals(['HOME', 'USERPROFILE', 'GEMINI_HOME']));
    });
  });

  group('parsing', () {
    test('streamResultText reads the terminal result event', () {
      expect(
        cap.streamResultText('{"event":"result","result":{"response":"done"}}'),
        'done',
      );
    });

    test('streamResultText ignores other and malformed lines', () {
      expect(
        cap.streamResultText('{"event":"message","result":{"response":"x"}}'),
        isNull,
      );
      expect(cap.streamResultText('{"event":"result"}'), isNull);
      expect(cap.streamResultText('not json'), isNull);
    });

    test('extractText unwraps the final json envelope', () {
      expect(
        cap.extractText(
          ProcessResult(0, 0, '{"response":"  final answer  "}', ''),
        ),
        'final answer',
      );
    });

    test('extractText falls back to raw stdout', () {
      expect(
        cap.extractText(ProcessResult(0, 0, ' plain text \n', '')),
        'plain text',
      );
      expect(cap.extractText(ProcessResult(0, 0, '   ', '')), '');
    });
  });
}
