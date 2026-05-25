import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import '../../utils/logger.dart';
import '../cli/cli_tool_locator.dart';
import '../io/filesystem.dart';
import 'plugin_exceptions.dart';
import '../skill/skill_fetch_service.dart';

/// Uses local `git` for repo SHA checks and shallow clones (no GitHub REST API).
class PluginRepoGitService {
  PluginRepoGitService({
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? gitLocator,
  }) : _runner = runner,
       _gitLocator = gitLocator ?? const CliToolLocator('git');

  final ProcessRunner _runner;
  final CliToolLocator _gitLocator;

  String? _gitExecutable;

  Future<String?> get _git async {
    _gitExecutable ??= await _gitLocator.locate(runner: _runner);
    return _gitExecutable;
  }

  Future<bool> get isAvailable async => (await _git) != null;

  static String cloneUrl(String owner, String name) =>
      'https://github.com/$owner/$name.git';

  /// Latest commit on [branch] via `git ls-remote` (null if unavailable).
  Future<String?> resolveRemoteSha(
    String owner,
    String name,
    String branch,
  ) async {
    final git = await _git;
    if (git == null) return null;

    final url = cloneUrl(owner, name);
    final ref = 'refs/heads/$branch';
    try {
      final result = await _runner(git, ['ls-remote', url, ref]);
      if (result.exitCode != 0) {
        appLogger.d(
          '[PluginRepoGit] ls-remote $owner/$name@$branch exit ${result.exitCode}',
        );
        return null;
      }
      final line = _firstStdoutLine(result.stdout);
      if (line == null || line.isEmpty) return null;
      final sha = line.split(RegExp(r'\s+')).first.trim();
      return sha.isEmpty ? null : sha;
    } catch (e) {
      appLogger.d('[PluginRepoGit] ls-remote $owner/$name@$branch: $e');
      return null;
    }
  }

  /// Tries [configuredBranch] then main/master fallbacks.
  Future<({String sha, String branch})?> resolveRemoteShaWithFallback(
    String owner,
    String name,
    String configuredBranch,
  ) async {
    for (final branch in skillRepoBranchCandidates(configuredBranch)) {
      final sha = await resolveRemoteSha(owner, name, branch);
      if (sha != null) return (sha: sha, branch: branch);
    }
    return null;
  }

  /// Shallow clone or fetch into [workDirPath]; returns file entries + resolved branch + HEAD sha.
  Future<({
    Map<String, Uint8List> entries,
    String branch,
    String commitSha,
  })> syncCheckout(PluginMarketplace marketplace, Filesystem fs, String workDirPath) async {
    final git = await _git;
    if (git == null) {
      throw StateError('git executable not found on PATH');
    }

    final url = cloneUrl(marketplace.owner, marketplace.name);
    Object? lastError;

    for (final branch in skillRepoBranchCandidates(marketplace.branch)) {
      try {
        await _cloneOrUpdate(git, url, fs, workDirPath, branch);
        final sha = await _headSha(git, workDirPath);
        final entries = await _collectRepoFiles(fs, workDirPath);
        return (entries: entries, branch: branch, commitSha: sha);
      } catch (e) {
        lastError = e;
        appLogger.d('[PluginRepoGit] checkout ${marketplace.fullName}@$branch: $e');
      }
    }

    throw MarketplaceUnreachableException(
      'git sync failed for ${marketplace.fullName} (tried ${skillRepoBranchCandidates(marketplace.branch).join(", ")})',
      cause: lastError,
    );
  }

  /// Shallow-clone [url] into [workDirPath], optionally at [ref] (branch/tag) or [sha].
  Future<String> syncCheckoutFromUrl(
    String url,
    Filesystem fs,
    String workDirPath, {
    String? ref,
    String? sha,
  }) async {
    final git = await _git;
    if (git == null) {
      throw StateError('git executable not found on PATH');
    }

    final normalized = url.trim();
    if (normalized.isEmpty) {
      throw MarketplaceUnreachableException('empty git url');
    }

    if (sha != null && sha.isNotEmpty) {
      await _checkoutPinnedCommit(
        git,
        normalized,
        fs,
        workDirPath,
        sha,
        ref: ref,
      );
      return _headSha(git, workDirPath);
    }

    final branch = (ref != null && ref.isNotEmpty) ? ref : 'main';
    for (final candidate in skillRepoBranchCandidates(branch)) {
      try {
        await _cloneOrUpdate(git, normalized, fs, workDirPath, candidate);
        return _headSha(git, workDirPath);
      } catch (e) {
        appLogger.d('[PluginRepoGit] checkout $normalized@$candidate: $e');
      }
    }

    throw MarketplaceUnreachableException(
      'git sync failed for $normalized (tried ${skillRepoBranchCandidates(branch).join(", ")})',
    );
  }

  Future<void> _checkoutPinnedCommit(
    String git,
    String url,
    Filesystem fs,
    String workDirPath,
    String sha, {
    String? ref,
  }) async {
    if (ref != null && ref.isNotEmpty) {
      try {
        await _cloneOrUpdate(git, url, fs, workDirPath, ref);
        final head = await _headSha(git, workDirPath);
        if (head == sha || head.startsWith(sha) || sha.startsWith(head)) {
          return;
        }
      } catch (e) {
        appLogger.d('[PluginRepoGit] ref checkout before sha ($ref): $e');
      }
    }

    if ((await fs.stat(workDirPath)).exists) {
      await fs.removeRecursive(workDirPath);
    }
    await fs.ensureDir(workDirPath);

    var result = await _runner(git, ['clone', url, workDirPath]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git clone failed: ${_stderrSnippet(result)}',
      );
    }

    result = await _runner(git, [
      '-C',
      workDirPath,
      'fetch',
      '--depth',
      '1',
      'origin',
      sha,
    ]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git fetch commit failed: ${_stderrSnippet(result)}',
      );
    }

    result = await _runner(git, ['-C', workDirPath, 'checkout', sha]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git checkout commit failed: ${_stderrSnippet(result)}',
      );
    }
  }

  Future<void> _cloneOrUpdate(
    String git,
    String url,
    Filesystem fs,
    String workDirPath,
    String branch,
  ) async {
    final gitDirStat = await fs.stat(fs.pathContext.join(workDirPath, '.git'));
    if (gitDirStat.isDirectory) {
      var result = await _runner(git, [
        '-C',
        workDirPath,
        'fetch',
        '--depth',
        '1',
        'origin',
        branch,
      ]);
      if (result.exitCode != 0) {
        throw MarketplaceUnreachableException(
          'git fetch failed: ${_stderrSnippet(result)}',
        );
      }
      result = await _runner(git, [
        '-C',
        workDirPath,
        'checkout',
        '-f',
        'FETCH_HEAD',
      ]);
      if (result.exitCode != 0) {
        throw MarketplaceUnreachableException(
          'git checkout failed: ${_stderrSnippet(result)}',
        );
      }
      return;
    }

    if ((await fs.stat(workDirPath)).exists) {
      await fs.removeRecursive(workDirPath);
    }
    await fs.ensureDir(workDirPath);

    final result = await _runner(git, [
      'clone',
      '--depth',
      '1',
      '--branch',
      branch,
      url,
      workDirPath,
    ]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git clone failed: ${_stderrSnippet(result)}',
      );
    }
  }

  /// HEAD commit in an existing checkout under [workDirPath].
  Future<String?> readHeadSha(Filesystem fs, String workDirPath) async {
    final git = await _git;
    if (git == null) return null;
    if (!(await fs.stat(fs.pathContext.join(workDirPath, '.git'))).isDirectory) return null;
    try {
      return await _headSha(git, workDirPath);
    } catch (e) {
      appLogger.d('[PluginRepoGit] rev-parse HEAD: $e');
      return null;
    }
  }

  Future<String> _headSha(String git, String workDirPath) async {
    final result = await _runner(git, [
      '-C',
      workDirPath,
      'rev-parse',
      'HEAD',
    ]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git rev-parse failed: ${_stderrSnippet(result)}',
      );
    }
    return _firstStdoutLine(result.stdout)?.trim() ?? '';
  }

  Future<Map<String, Uint8List>> _collectRepoFiles(Filesystem fs, String rootPath) async {
    final out = <String, Uint8List>{};
    if (!(await fs.stat(rootPath)).exists) return out;

    final entries = await fs.listDirRecursive(rootPath);
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final rel = entry.name.replaceAll('\\', '/');
      if (rel.startsWith('..') || _shouldSkipRelativePath(rel)) continue;
      final fullPath = fs.pathContext.join(rootPath, entry.name);
      final bytes = await fs.readBytes(fullPath);
      if (bytes != null) {
        out[rel] = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      }
    }
    return out;
  }

  bool _shouldSkipRelativePath(String rel) {
    final parts = p.split(rel);
    return parts.isEmpty || parts.first == '.git' || parts.contains('.git');
  }

  String? _firstStdoutLine(Object? stdout) {
    final text = stdout?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text.split('\n').first.trim();
  }

  String _stderrSnippet(ProcessResult result) {
    final err = result.stderr?.toString().trim() ?? '';
    if (err.isEmpty) return 'exit ${result.exitCode}';
    final line = err.split('\n').first;
    return line.length > 200 ? '${line.substring(0, 200)}…' : line;
  }
}
