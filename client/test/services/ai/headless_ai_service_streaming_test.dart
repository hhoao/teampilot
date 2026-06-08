import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/headless_ai_service.dart';

void main() {
  test('runStreaming emits each line via onEvent and returns result text',
      () async {
    final lines = <String>[];
    final svc = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => '/usr/bin/$name',
      resolveProvisionCapability: (_) => null,
      streamRun: (
        executable,
        arguments, {
        environment,
        workingDirectory,
        timeout,
        required onStdoutLine,
      }) async {
        onStdoutLine('{"type":"assistant","text":"thinking"}');
        onStdoutLine('');
        onStdoutLine('{"type":"result","result":"{\\"members\\":[]}"}');
        return 0;
      },
    );

    final result = await svc.runStreaming(
      setting: const AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'p',
        model: 'sonnet',
      ),
      prompt: 'make a team',
      onEvent: (line) => lines.add(line),
    );

    // empty line skipped, two events delivered
    expect(lines, hasLength(2));
    expect(result.text, '{"members":[]}');
  });

  test('runStreaming throws on non-zero exit', () async {
    final svc = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => '/usr/bin/$name',
      resolveProvisionCapability: (_) => null,
      streamRun: (
        executable,
        arguments, {
        environment,
        workingDirectory,
        timeout,
        required onStdoutLine,
      }) async => 2,
    );

    expect(
      () => svc.runStreaming(
        setting: const AiFeatureSetting(
          cli: CliTool.claude,
          providerId: 'p',
          model: 'sonnet',
        ),
        prompt: 'x',
        onEvent: (_) {},
      ),
      throwsA(isA<HeadlessAiException>()),
    );
  });
}
