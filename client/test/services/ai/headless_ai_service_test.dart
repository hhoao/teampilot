import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/headless_ai_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_provision_capability.dart';

/// Provisioning that reports missing credentials, to exercise the service's
/// not-ready branch without touching storage.
class _NotReadyProvision implements HeadlessProvisionCapability {
  const _NotReadyProvision();
  @override
  Future<HeadlessProvisionResult> provision(HeadlessProvisionContext ctx) async =>
      const HeadlessProvisionResult(
        credentialsReady: false,
        warnings: ['claude_credentials_missing'],
      );
}

void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('tp_headless_test_'));
  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  AiFeatureSetting setting({String effort = ''}) => AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: 'sonnet',
        effort: effort,
      );

  test('runs the resolved invocation and returns extracted text', () async {
    late String ranExecutable;
    late List<String> ranArgs;
    final service = HeadlessAiService(
      resolveProvisionCapability: (_) => null,
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => '/usr/bin/$name',
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory, timeout}) async {
        ranExecutable = exe;
        ranArgs = args;
        return ProcessResult(0, 0, '{"result":"feat: x"}', '');
      },
    );

    final result = await service.run(
      setting: setting(),
      prompt: 'p',
      expectJson: true,
    );

    expect(ranExecutable, '/usr/bin/claude');
    expect(ranArgs, contains('--output-format'));
    expect(result.text, 'feat: x');
    expect(result.exitCode, 0);
  });

  test('throws when credentials are not provisioned', () async {
    final service = HeadlessAiService(
      resolveProvisionCapability: (_) => const _NotReadyProvision(),
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory, timeout}) async =>
          ProcessResult(0, 0, 'ok', ''),
    );

    expect(
      () => service.run(setting: setting(), prompt: 'p'),
      throwsA(
        isA<HeadlessAiException>().having(
          (e) => e.message,
          'message',
          contains('Provider'),
        ),
      ),
    );
  });

  test('throws when executable is not found', () async {
    final service = HeadlessAiService(
      resolveProvisionCapability: (_) => null,
      resolveProvider: (_, __) async => null,
      resolveExecutable: (_) async => null,
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory, timeout}) async =>
          ProcessResult(0, 0, '', ''),
    );

    expect(
      () => service.run(setting: setting(), prompt: 'p'),
      throwsA(isA<HeadlessAiException>()),
    );
  });

  test('throws on non-zero exit code', () async {
    final service = HeadlessAiService(
      resolveProvisionCapability: (_) => null,
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory, timeout}) async =>
          ProcessResult(0, 2, '', 'boom'),
    );

    expect(
      () => service.run(setting: setting(), prompt: 'p'),
      throwsA(
        isA<HeadlessAiException>().having((e) => e.message, 'message', contains('boom')),
      ),
    );
  });
}
