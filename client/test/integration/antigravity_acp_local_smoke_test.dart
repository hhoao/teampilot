@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/antigravity/antigravity_tool.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';

/// End-to-end local smoke for Antigravity's ACP adapter (`agy_acp_server`).
///
/// Spawns the real adapter through the app's production seams
/// (`productionAcpSpawner` + `AcpSessionRuntime`) and drives one prompt turn.
/// Requires the adapter (installed via the app toolchain or on PATH) and a
/// configured Antigravity account; skipped before spawning otherwise.
///
/// The adapter is launched with an isolated HOME, and `session/new` is refused
/// until `auth.type` is known, so the real `~/.gemini/antigravity-acp/settings.json`
/// is copied into the temp HOME when present (the OAuth token itself lives in
/// the OS keyring, which is not HOME-scoped). Without that file a keyring
/// (`oauth-personal`) or `GEMINI_API_KEY` session is seeded instead.
///
/// Probe note: model-call auth failures come back as plain assistant text plus
/// `end_turn`, not as an ACP error. The smoke therefore only asserts that
/// `session/new` succeeded and the prompt was dispatched; the assistant reply is
/// printed for manual inspection.
///
/// ```bash
/// dart run tool/run_tests.dart --tags integration \
///   test/integration/antigravity_acp_local_smoke_test.dart
/// ```
void main() {
  test('antigravity ACP completes initialize / session/new / prompt', () async {
    final adapter = await _locateAdapter();
    if (adapter == null) {
      markTestSkipped('agy_acp_server not installed (toolchain or PATH)');
      return;
    }

    final temp = Directory.systemTemp.createTempSync('antigravity-acp-');
    if (!_seedAuth(temp)) {
      _deleteQuietly(temp);
      markTestSkipped('Antigravity auth not configured');
      return;
    }

    final registry = CliToolRegistry()..register(const AntigravityCliTool());
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.antigravity,
        workingDirectory: temp.path,
        logger: logger,
        handshakeTimeout: const Duration(seconds: 120),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(
        registry,
        discoveredAdapterPath: (_) => adapter,
      ),
    );

    try {
      final apiKey = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';
      try {
        await runtime.start(
          tool: CliTool.antigravity,
          executable: adapter,
          sessionToolDir: temp.path,
          workingDirectory: temp.path,
          baseEnv: <String, String>{
            'PATH': Platform.environment['PATH'] ?? '',
            if (apiKey.isNotEmpty) 'GEMINI_API_KEY': apiKey,
          },
        );
      } on Object catch (error) {
        if (_isAuthRequired(error)) {
          markTestSkipped('agy_acp_server is not authenticated: $error');
          return;
        }
        rethrow;
      }
      expect(runtime.isStarted, isTrue);

      final reply = StringBuffer();
      final updates = runtime.updates.listen((update) {
        if (update is AcpMessageChunk && update.role == AcpRole.assistant) {
          reply.write(update.content);
        }
      });
      try {
        // Model-call auth failures are plain assistant text + end_turn, so a
        // completed prompt is the assertion; content is logged only.
        await runtime.prompt('Reply with exactly: ok');
      } on Object catch (error) {
        if (_isAuthRequired(error)) {
          markTestSkipped('agy_acp_server is not authenticated: $error');
          return;
        }
        rethrow;
      } finally {
        await updates.cancel();
      }

      // ignore: avoid_print
      print('[antigravity-acp] reply: ${reply.toString().trim()}');
    } finally {
      await runtime.close();
      _deleteQuietly(temp);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Seeds the isolated HOME the adapter launches with.
///
/// Returns false when the machine has no Antigravity auth at all, so the test
/// skips before spawning instead of failing `session/new`.
bool _seedAuth(Directory temp) {
  final home = _realHome();
  final settings = home == null
      ? null
      : File(p.join(home, '.gemini', 'antigravity-acp', 'settings.json'));
  final oauthMarker = home == null
      ? null
      : File(p.join(home, '.gemini', 'oauth_creds.json'));
  final apiKey = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';

  Map<String, Object?>? seed;
  if (settings != null && settings.existsSync()) {
    // Prefer the real file byte-for-byte; fall back to a keyring session when
    // it is present but unreadable/corrupt.
    try {
      final decoded = jsonDecode(settings.readAsStringSync());
      if (decoded is Map) seed = Map<String, Object?>.from(decoded);
    } on Object {
      seed = null;
    }
    seed ??= {
      'auth': {'type': 'oauth-personal'},
    };
  } else if (oauthMarker != null && oauthMarker.existsSync()) {
    seed = {
      'auth': {'type': 'oauth-personal'},
    };
  } else if (apiKey.isNotEmpty) {
    seed = {
      'auth': {'type': 'gemini-api-key'},
    };
  }
  if (seed == null) return false;

  final dir = Directory(p.join(temp.path, 'home', '.gemini', 'antigravity-acp'))
    ..createSync(recursive: true);
  File(
    p.join(dir.path, 'settings.json'),
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(seed));
  return true;
}

String? _realHome() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return home.trim().isEmpty ? null : home;
}

/// Resolves the adapter from the installer's toolchain directory (the same
/// probe the readiness UI uses) and falls back to `PATH` (`where` on Windows).
Future<String?> _locateAdapter() async {
  final names = Platform.isWindows
      ? const ['agy_acp_server.exe', 'agy_acp_server.par', 'agy_acp_server']
      : const ['agy_acp_server.par', 'agy_acp_server'];
  for (final name in names) {
    final fromPath = await _which(name);
    if (fromPath != null) return fromPath;
  }

  final home = _realHome();
  if (home == null) return null;
  final roots = <String>[
    AppPaths.defaultTeampilotAppDataDirForHome(home),
    if (Platform.environment['TEAMPILOT_ROOT'] case final root?
        when root.trim().isNotEmpty)
      root,
  ];
  for (final root in roots) {
    final installer = AntigravityAcpAdapterInstaller(
      storage: HomeStorage.forTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths(root),
        home: home,
        cwd: Directory.systemTemp.path,
      ),
    );
    final installed = await installer.resolveInstalledPath();
    if (installed != null) return installed;
  }
  return null;
}

/// Only the adapter's own auth error (ACP `-32000 Authentication required`)
/// means "not logged in"; a model-call auth failure is plain assistant text.
bool _isAuthRequired(Object error) {
  if (error is AcpAuthenticateException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('authentication required') ||
      (text.contains('-32000') && text.contains('auth'));
}

Future<String?> _which(String name) async {
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      name,
    ]);
    if (result.exitCode != 0) return null;
    final output = (result.stdout as String? ?? '').trim();
    if (output.isEmpty) return null;
    // `where` can return several matches; the first one wins.
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final path = line.trim();
      if (path.isNotEmpty) return path;
    }
    return null;
  } on ProcessException {
    return null;
  }
}

void _deleteQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort temp cleanup.
  }
}
