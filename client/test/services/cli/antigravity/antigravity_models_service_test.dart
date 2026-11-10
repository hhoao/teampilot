import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/antigravity/provider/antigravity_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  AntigravityModelsService serviceWith(AntigravityModelsProcessRunner runner) =>
      AntigravityModelsService(
        fs: fs,
        basePath: '/app',
        executable: 'agy',
        processRunner: runner,
      );

  test(
    'reads agy models, collapses effort tiers and caches the result',
    () async {
      var calls = 0;
      var notified = 0;
      final service = serviceWith((
        executable,
        arguments, {
        environment,
        workingDirectory,
      }) async {
        calls++;
        expect(executable, 'agy');
        expect(arguments, ['models']);
        return const AntigravityModelsProcessResult(
          exitCode: 0,
          stdout:
              'gemini-3.8-flash-high\tGemini 3.8 Flash (High)\n'
              'gemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\n'
              'claude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)\n',
          stderr: '',
        );
      });
      service.catalogUpdates.addListener(() => notified++);

      await service.ensureLoaded(providerId: 'official');

      expect(service.modelIdsFor(providerId: 'official'), [
        'gemini-3.8-flash',
        'claude-sonnet-4-6',
      ]);
      expect(calls, 1);
      expect(notified, 1);

      await service.ensureLoaded(providerId: 'official');
      expect(calls, 1, reason: 'fresh memory cache is reused');

      await service.ensureLoaded(providerId: 'official', forceRefresh: true);
      expect(calls, 2);
    },
  );

  test('persists the catalog and reuses it in a new instance', () async {
    final first = serviceWith(
      (executable, arguments, {environment, workingDirectory}) async =>
          const AntigravityModelsProcessResult(
            exitCode: 0,
            stdout: 'gemini-4-argon-high\tGemini 4 Argon\n',
            stderr: '',
          ),
    );
    await first.ensureLoaded(providerId: 'official');

    var calls = 0;
    final second = serviceWith((
      executable,
      arguments, {
      environment,
      workingDirectory,
    }) async {
      calls++;
      return const AntigravityModelsProcessResult(
        exitCode: 0,
        stdout: 'other\n',
        stderr: '',
      );
    });
    await second.ensureLoaded(providerId: 'official');

    expect(calls, 0, reason: 'fresh disk cache skips the CLI call');
    expect(second.modelIdsFor(providerId: 'official'), ['gemini-4-argon']);
  });

  test('ignores a failed or empty listing', () async {
    final service = serviceWith(
      (executable, arguments, {environment, workingDirectory}) async =>
          const AntigravityModelsProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'not logged in',
          ),
    );

    await service.ensureLoaded(providerId: 'official');

    expect(service.modelIdsFor(providerId: 'official'), isEmpty);
  });
}
