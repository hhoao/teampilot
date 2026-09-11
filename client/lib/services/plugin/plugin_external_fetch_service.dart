import 'dart:io';
import 'package:path/path.dart' as p;

import '../../models/plugin_external_source.dart';
import '../io/filesystem.dart';
import '../storage/home_storage.dart';
import 'plugin_exceptions.dart';
import 'plugin_repo_git_service.dart';

/// Fetches plugin directories from external git URLs (`git-subdir`, `url`, `github`).
class PluginExternalFetchService {
  PluginExternalFetchService({
    required HomeStorage storage,
    PluginRepoGitService? gitService,
    Filesystem? filesystem,
  }) : _storage = storage,
       _git = gitService ?? PluginRepoGitService(),
       _fsOverride = filesystem;

  final HomeStorage _storage;
  final PluginRepoGitService _git;
  final Filesystem? _fsOverride;

  Filesystem get _fs => _fsOverride ?? _storage.fs;

  Future<String> _cacheRoot() async {
    return _storage.paths.pluginExternalCacheDir;
  }

  /// Returns the plugin root directory (contains `.claude-plugin/plugin.json` or plugin files).
  Future<Directory> fetchPluginDirectory(PluginExternalSource spec) async {
    if (!await _git.isAvailable) {
      throw PluginInstallException(
        spec.cloneUrl,
        'git is not available on PATH; cannot fetch external plugin',
      );
    }

    final root = await _cacheRoot();
    final dirPath = p.join(root, spec.cacheKey);
    final head = await _git.readHeadSha(_fs, dirPath);
    final needsSync =
        head == null ||
        (spec.sha != null &&
            spec.sha!.isNotEmpty &&
            head != spec.sha &&
            !head.startsWith(spec.sha!) &&
            !spec.sha!.startsWith(head));

    if (needsSync) {
      await _git.syncCheckoutFromUrl(
        spec.cloneUrl,
        _fs,
        dirPath,
        ref: spec.ref,
        sha: spec.sha,
      );
    }

    final pluginDirPath = spec.subPath.isEmpty
        ? dirPath
        : p.join(dirPath, spec.subPath);
    if (!(await _fs.stat(pluginDirPath)).exists) {
      throw PluginInstallException(
        spec.cloneUrl,
        'Plugin path missing after fetch: ${spec.subPath}',
      );
    }
    return Directory(pluginDirPath);
  }
}
