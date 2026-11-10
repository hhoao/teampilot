import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/provider/codex_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  CodexModelsService serviceWith(CodexModelsProcessRunner runner) =>
      CodexModelsService(
        fs: fs,
        basePath: '/app',
        executable: 'codex',
        processRunner: runner,
      );

  test('keeps listed models and drops hidden ones', () async {
    var calls = 0;
    var notified = 0;
    final service = serviceWith((
      executable,
      arguments, {
      environment,
      workingDirectory,
    }) async {
      calls++;
      expect(executable, 'codex');
      expect(arguments, ['debug', 'models']);
      return const CodexModelsProcessResult(
        exitCode: 0,
        stdout:
            '{"models":['
            '{"slug":"gpt-6-astra","visibility":"list"},'
            '{"slug":"gpt-5.4","visibility":"hide"},'
            '{"slug":"gpt-5.5"},'
            '{"slug":""}'
            ']}',
        stderr: '',
      );
    });
    service.catalogUpdates.addListener(() => notified++);

    await service.ensureLoaded(providerId: 'openai');

    expect(service.modelIdsFor(providerId: 'openai'), [
      'gpt-6-astra',
      'gpt-5.5',
    ]);
    expect(calls, 1);
    expect(notified, 1);

    await service.ensureLoaded(providerId: 'openai');
    expect(calls, 1, reason: 'fresh memory cache is reused');

    await service.ensureLoaded(providerId: 'openai', forceRefresh: true);
    expect(calls, 2);
  });

  test('persists the catalog and reuses it in a new instance', () async {
    final first = serviceWith(
      (executable, arguments, {environment, workingDirectory}) async =>
          const CodexModelsProcessResult(
            exitCode: 0,
            stdout: '{"models":[{"slug":"gpt-6-astra","visibility":"list"}]}',
            stderr: '',
          ),
    );
    await first.ensureLoaded(providerId: 'openai');

    var calls = 0;
    final second = serviceWith((
      executable,
      arguments, {
      environment,
      workingDirectory,
    }) async {
      calls++;
      return const CodexModelsProcessResult(
        exitCode: 0,
        stdout: '{"models":[{"slug":"other"}]}',
        stderr: '',
      );
    });
    await second.ensureLoaded(providerId: 'openai');

    expect(calls, 0, reason: 'fresh disk cache skips the CLI call');
    expect(second.modelIdsFor(providerId: 'openai'), ['gpt-6-astra']);
  });

  test('ignores a failed or malformed listing', () async {
    final service = serviceWith(
      (executable, arguments, {environment, workingDirectory}) async =>
          const CodexModelsProcessResult(
            exitCode: 2,
            stdout: 'not json',
            stderr: 'boom',
          ),
    );

    await service.ensureLoaded(providerId: 'openai');

    expect(service.modelIdsFor(providerId: 'openai'), isEmpty);
  });
}
