import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/plugin.dart';
import '../utils/logger.dart';
import 'cli_tool_locator.dart';
import 'plugin_exceptions.dart';
import 'skill_fetch_service.dart';

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

  /// Shallow clone or fetch into [workDir]; returns file entries + resolved branch + HEAD sha.
  Future<({
    Map<String, Uint8List> entries,
    String branch,
    String commitSha,
  })> syncCheckout(PluginMarketplace marketplace, Directory workDir) async {
    final git = await _git;
    if (git == null) {
      throw StateError('git executable not found on PATH');
    }

    final url = cloneUrl(marketplace.owner, marketplace.name);
    Object? lastError;

    for (final branch in skillRepoBranchCandidates(marketplace.branch)) {
      try {
        await _cloneOrUpdate(git, url, workDir, branch);
        final sha = await _headSha(git, workDir.path);
        final entries = await _collectRepoFiles(workDir);
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

  /// Shallow-clone [url] into [workDir], optionally at [ref] (branch/tag) or [sha].
  Future<String> syncCheckoutFromUrl(
    String url,
    Directory workDir, {
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
        workDir,
        sha,
        ref: ref,
      );
      return _headSha(git, workDir.path);
    }

    final branch = (ref != null && ref.isNotEmpty) ? ref : 'main';
    for (final candidate in skillRepoBranchCandidates(branch)) {
      try {
        await _cloneOrUpdate(git, normalized, workDir, candidate);
        return _headSha(git, workDir.path);
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
    Directory workDir,
    String sha, {
    String? ref,
  }) async {
    if (ref != null && ref.isNotEmpty) {
      try {
        await _cloneOrUpdate(git, url, workDir, ref);
        final head = await _headSha(git, workDir.path);
        if (head == sha || head.startsWith(sha) || sha.startsWith(head)) {
          return;
        }
      } catch (e) {
        appLogger.d('[PluginRepoGit] ref checkout before sha ($ref): $e');
      }
    }

    if (workDir.existsSync()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    var result = await _runner(git, ['clone', url, workDir.path]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git clone failed: ${_stderrSnippet(result)}',
      );
    }

    result = await _runner(git, [
      '-C',
      workDir.path,
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

    result = await _runner(git, ['-C', workDir.path, 'checkout', sha]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git checkout commit failed: ${_stderrSnippet(result)}',
      );
    }
  }

  Future<void> _cloneOrUpdate(
    String git,
    String url,
    Directory workDir,
    String branch,
  ) async {
    final gitDir = Directory(p.join(workDir.path, '.git'));
    if (gitDir.existsSync()) {
      var result = await _runner(git, [
        '-C',
        workDir.path,
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
        workDir.path,
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

    if (workDir.existsSync()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    final result = await _runner(git, [
      'clone',
      '--depth',
      '1',
      '--branch',
      branch,
      url,
      workDir.path,
    ]);
    if (result.exitCode != 0) {
      throw MarketplaceUnreachableException(
        'git clone failed: ${_stderrSnippet(result)}',
      );
    }
  }

  /// HEAD commit in an existing checkout under [workDir].
  Future<String?> readHeadSha(Directory workDir) async {
    final git = await _git;
    if (git == null) return null;
    if (!Directory(p.join(workDir.path, '.git')).existsSync()) return null;
    try {
      return await _headSha(git, workDir.path);
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

  Future<Map<String, Uint8List>> _collectRepoFiles(Directory root) async {
    final out = <String, Uint8List>{};
    if (!root.existsSync()) return out;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      if (rel.startsWith('..') || _shouldSkipRelativePath(rel)) continue;
      out[rel] = await entity.readAsBytes();
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
