@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/provider/codex_toml_parser.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';
import 'support/cli_message_matrix_harness.dart';
import 'support/integration_prerequisites.dart';
import 'support/integration_test_setup.dart';

/// Production-shaped codex launch: the session pipeline materializes the full
/// `config.toml` (provider + managed agent-status/team-bus hooks), then the
/// real codex binary must boot to its composer.
///
/// Regression guard for the "unknown variant `http` in `hooks`" failure: the
/// managed hooks stamped on every local seat used to render as an unsupported
/// `type = "http"` row, and codex exited 1 before reaching the TUI. This cell
/// stops at the composer (no model turns), so it stays fast and gateway-free.
///
/// Run:
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test test/integration/codex_config_materialize_launch_integration_test.dart \
///     --tags "integration && linux-pty"
void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test('product codex config.toml with managed hooks boots real codex',
      () async {
    IntegrationPrerequisites.skipUnlessNativePty();
    final codexPath = IntegrationPrerequisites.requireCodexPath();
    if (codexPath == null) return;

    final harness = CliMessageMatrixHarness.forCli(
      CliTool.codex,
      mode: CliMatrixMode.simple,
      cliPath: codexPath,
    );
    final postFrame = PostFrameTestHarness();
    addTearDown(() async {
      await harness.dispose();
      await postFrame.flush();
      await drainPendingAsyncWork();
      // Let Codex PTY children release CODEX_HOME handles before tearDown.
      await Future<void>.delayed(const Duration(seconds: 3));
    });

    await harness.startGateway();
    await harness.writeMockProviders();
    harness.createCubit(postFrame: postFrame);
    await harness.openSession();
    await harness.bootComposeSeatToPrompt();

    // Boot succeeded — that already proves the materialized config.toml was
    // accepted by codex. Verify the hook rows this session shipped really are
    // the loadable command-hook form (and stay under the schema whitelist).
    final tomls = _readCodexConfigTomls();
    expect(tomls, isNotEmpty, reason: 'no codex config.toml materialized');
    for (final toml in tomls) {
      expect(toml, contains('[[hooks.'), reason: 'managed hooks not stamped');
      expect(
        toml,
        isNot(contains('type = "http"')),
        reason: 'unsupported native http hook rendered into config.toml',
      );
      expect(
        CodexTomlParser.invalidHookTypes(toml),
        isEmpty,
        reason: 'config.toml hook rows must pass the schema whitelist',
      );
    }
  });
}

/// All `config.toml` files the session pipeline materialized under the codex
/// runtime dirs (session tool dir), in no particular order.
List<String> _readCodexConfigTomls() {
  final root = Directory(AppStorage.paths.basePath);
  if (!root.existsSync()) return const [];
  final contents = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final segments = entity.path.split(Platform.pathSeparator);
    if (segments.contains('codex') && p.basename(entity.path) == 'config.toml') {
      final text = entity.readAsStringSync();
      if (text.contains('[[hooks.')) contents.add(text);
    }
  }
  return contents;
}