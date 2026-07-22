import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/lock_pool.dart';
import '../../cli/cli_tool_locator.dart';
import '../../io/filesystem.dart';
import '../../storage/runtime_layout.dart';

typedef OpencodePluginVersionResolver = Future<String?> Function();
typedef OpencodeNpmInstall = Future<int> Function(String cwd);

/// Seeds `<teampilotRoot>/cli-defaults/opencode/{package.json,node_modules}`
/// for OpenCode local plugins (`@opencode-ai/plugin`).
final class OpencodeSharedPluginDeps {
  OpencodeSharedPluginDeps({
    required this.layout,
    required this.fs,
    OpencodePluginVersionResolver? resolvePluginVersion,
    OpencodeNpmInstall? npmInstall,
    ProcessRunner? processRunner,
  }) : _resolvePluginVersion = resolvePluginVersion,
       _npmInstall = npmInstall,
       _runner = processRunner ?? cliToolDefaultProcessRun;

  final RuntimeLayout layout;
  final Filesystem fs;
  final OpencodePluginVersionResolver? _resolvePluginVersion;
  final OpencodeNpmInstall? _npmInstall;
  final ProcessRunner _runner;

  static final _locks = LockPool();
  static const _lockKey = 'opencode|plugin-deps';

  String get sharedRoot => layout.appToolRoot('opencode');

  String get _pluginPackageDir =>
      p.join(sharedRoot, 'node_modules', '@opencode-ai', 'plugin');

  Future<bool> get isComplete async =>
      (await fs.stat(_pluginPackageDir)).isDirectory;

  /// Idempotent. Incomplete/failed trees are removed so the next call retries.
  Future<void> ensureSharedInstalled() {
    return _locks.synchronized(_lockKey, _ensureSharedInstalledUnlocked);
  }

  Future<void> _ensureSharedInstalledUnlocked() async {
    if (await isComplete) return;

    final version =
        (await (_resolvePluginVersion ?? _defaultResolvePluginVersion)())
            ?.trim() ??
        '';
    if (version.isEmpty) {
      throw StateError(
        'Cannot seed opencode plugin deps: opencode version unavailable',
      );
    }

    final nodeModules = p.join(sharedRoot, 'node_modules');
    if ((await fs.stat(nodeModules)).exists) {
      await fs.removeRecursive(nodeModules);
    }

    await fs.ensureDir(sharedRoot);
    await fs.atomicWrite(
      p.join(sharedRoot, 'package.json'),
      const JsonEncoder.withIndent('  ').convert({
        'dependencies': {'@opencode-ai/plugin': version},
      }),
    );

    final code = await (_npmInstall ?? _defaultNpmInstall)(sharedRoot);
    if (code != 0 || !(await isComplete)) {
      if ((await fs.stat(nodeModules)).exists) {
        await fs.removeRecursive(nodeModules);
      }
      throw StateError(
        'npm install @opencode-ai/plugin@$version failed (exit $code)',
      );
    }
  }

  Future<String?> _defaultResolvePluginVersion() async {
    try {
      final located = await const CliToolLocator(
        'opencode',
      ).locate(runner: _runner);
      final exe = located ?? 'opencode';
      final result = await _runner(exe, ['--version']);
      if (result.exitCode != 0) return null;
      final text = '${result.stdout}'.trim();
      final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(text);
      return match?.group(1);
    } on Object {
      // Missing binary / PATH (CI without opencode) → treat as unavailable.
      return null;
    }
  }

  Future<int> _defaultNpmInstall(String cwd) async {
    final result = await Process.run(
      'npm',
      ['install', '--omit=dev'],
      workingDirectory: cwd,
      runInShell: Platform.isWindows,
    );
    return result.exitCode;
  }
}
