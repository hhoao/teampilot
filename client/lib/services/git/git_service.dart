import 'dart:convert';

import '../../models/git_status.dart';
import '../../utils/logging/logger.dart';
import '../storage/runtime_context.dart';
import 'git_command_runner.dart';

export 'git_command_runner.dart'
    show GitCommandRunner, gitCommandRunnerForContext;

/// Thrown when a git command exits non-zero; [message] carries stderr.
class GitException implements Exception {
  GitException(this.message);
  final String message;
  @override
  String toString() => 'GitException: $message';
}

/// Runs `git` for the source control panel on the active storage backend
/// (native, WSL, or SSH remote host).
class GitService {
  GitService({GitCommandRunner? runner})
    : _runner = runner ?? LocalGitCommandRunner();

  /// Builds a service for [ctx]'s storage backend (local / WSL / SSH).
  factory GitService.forContext(RuntimeContext ctx) =>
      GitService(runner: gitCommandRunnerForContext(ctx));

  /// Test seam: when set, the default [GitCubit] builds this instead of a
  /// real process-backed service, so widget tests never spawn `git` (mirrors
  /// `AppStorage` test injection). See `setUpTestAppStorage`.
  static GitService Function()? debugOverrideFactory;

  final GitCommandRunner _runner;

  /// Resets static caches on local/remote runners. Tests call this in setUp.
  static void debugResetExecutableCache() {
    configuredGitExecutable = null;
    LocalGitCommandRunner.debugResetExecutableCache();
    RemoteGitCommandRunner.debugResetAvailabilityCache();
  }

  Future<bool> get isAvailable => _runner.isAvailable;

  /// Runs `git -C dir <args>`; throws [GitException] on non-zero exit.
  Future<String> _run(String dir, List<String> args) async {
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode != 0) {
      final err = result.stderr.trim();
      final out = result.stdout.trim();
      final detail = err.isEmpty ? out : err;
      appLogger.d('[Git] ${args.join(' ')} exit ${result.exitCode}: $detail');
      throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
    }
    return result.stdout;
  }

  /// Parses `git status --porcelain=v2 --branch` into a [GitRepoStatus].
  ///
  /// Returns [GitRepoStatus.notARepository] when [dir] is outside a work tree.
  Future<GitRepoStatus> status(String dir) async {
    if (!await isAvailable) {
      throw GitException('git executable not found on PATH');
    }
    final probe = await _runner.runInDirectory(dir, [
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    if (probe.exitCode != 0 || probe.stdout.trim() != 'true') {
      return GitRepoStatus.notARepository;
    }

    final out = await _run(dir, [
      'status',
      '--porcelain=v2',
      '--branch',
      '--untracked-files=all',
    ]);
    return _parseStatus(out);
  }

  static GitRepoStatus _parseStatus(String out) {
    String? branch;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    final staged = <GitFileChange>[];
    final unstaged = <GitFileChange>[];

    for (final line in const LineSplitter().convert(out)) {
      if (line.isEmpty) continue;
      if (line.startsWith('# ')) {
        final header = line.substring(2);
        if (header.startsWith('branch.head ')) {
          final value = header.substring('branch.head '.length).trim();
          branch = value == '(detached)' ? null : value;
        } else if (header.startsWith('branch.upstream ')) {
          upstream = header.substring('branch.upstream '.length).trim();
        } else if (header.startsWith('branch.ab ')) {
          // Format: "+<ahead> -<behind>"
          for (final tok
              in header
                  .substring('branch.ab '.length)
                  .trim()
                  .split(RegExp(r'\s+'))) {
            final n = int.tryParse(tok.substring(1)) ?? 0;
            if (tok.startsWith('+')) ahead = n;
            if (tok.startsWith('-')) behind = n;
          }
        }
        continue;
      }
      final type = line[0];
      if (type == '?') {
        // "? <path>"
        unstaged.add(
          GitFileChange(
            path: line.substring(2),
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        );
      } else if (type == 'u') {
        // Unmerged: "u <XY> ... <path>"
        final path = line.split(' ').last;
        unstaged.add(
          GitFileChange(
            path: path,
            kind: GitChangeKind.conflicted,
            staged: false,
          ),
        );
      } else if (type == '1' || type == '2') {
        _parseTrackedEntry(line, type, staged, unstaged);
      }
    }

    return GitRepoStatus(
      isRepository: true,
      branch: branch,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      staged: staged,
      unstaged: unstaged,
    );
  }

  /// Parses an ordinary ("1") or renamed/copied ("2") changed entry.
  ///
  /// Field 2 is the two-char XY status; X is the index (staged) state and Y
  /// the worktree (unstaged) state. A path may appear in both areas.
  static void _parseTrackedEntry(
    String line,
    String type,
    List<GitFileChange> staged,
    List<GitFileChange> unstaged,
  ) {
    final parts = line.split(' ');
    if (parts.length < 9) return;
    final xy = parts[1];
    final x = xy[0];
    final y = xy[1];

    String path;
    String? originalPath;
    if (type == '2') {
      // "2 <xy> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<orig>"
      final tail = parts.sublist(9).join(' ');
      final tabIdx = tail.indexOf('\t');
      if (tabIdx >= 0) {
        path = tail.substring(0, tabIdx);
        originalPath = tail.substring(tabIdx + 1);
      } else {
        path = tail;
      }
    } else {
      path = parts.sublist(8).join(' ');
    }

    if (x != '.') {
      staged.add(
        GitFileChange(
          path: path,
          originalPath: originalPath,
          kind: _kindFromCode(x),
          staged: true,
        ),
      );
    }
    if (y != '.') {
      unstaged.add(
        GitFileChange(
          path: path,
          originalPath: originalPath,
          kind: _kindFromCode(y),
          staged: false,
        ),
      );
    }
  }

  static GitChangeKind _kindFromCode(String code) => switch (code) {
    'A' => GitChangeKind.added,
    'D' => GitChangeKind.deleted,
    'R' => GitChangeKind.renamed,
    'C' => GitChangeKind.renamed,
    'M' => GitChangeKind.modified,
    _ => GitChangeKind.modified,
  };

  /// Unified diff for [change]. Untracked files are shown as a full addition.
  Future<String> diff(
    String dir,
    GitFileChange change, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    // A very large unified context makes git emit the whole file (all unchanged
    // lines), so the viewer can show full text instead of only the hunks.
    final context = fullContext ? '-U1000000' : null;
    if (change.kind == GitChangeKind.untracked) {
      return _runDiff(dir, [
        'diff',
        '--no-index',
        if (ignoreWhitespace) '-w',
        if (context != null) context,
        '/dev/null',
        change.path,
      ]);
    }
    return _runDiff(dir, [
      'diff',
      if (change.staged) '--cached',
      if (ignoreWhitespace) '-w',
      if (context != null) context,
      '--',
      change.path,
    ]);
  }

  /// Uncommitted diff for [relativePath]: working tree vs HEAD (staged +
  /// unstaged combined). Untracked paths use `--no-index` against `/dev/null`.
  Future<String> diffAgainstHead(
    String dir,
    String relativePath, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
    bool untracked = false,
  }) async {
    final context = fullContext ? '-U1000000' : null;
    if (untracked) {
      return _runDiff(dir, [
        'diff',
        '--no-index',
        if (ignoreWhitespace) '-w',
        if (context != null) context,
        '/dev/null',
        relativePath,
      ]);
    }
    return _runDiff(dir, [
      'diff',
      'HEAD',
      if (ignoreWhitespace) '-w',
      if (context != null) context,
      '--',
      relativePath,
    ]);
  }

  /// `git diff` exits 1 when the sides differ; treat that as success and return
  /// stdout. Other non-zero exits still throw [GitException].
  Future<String> _runDiff(String dir, List<String> args) async {
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode == 0 || result.exitCode == 1) {
      return result.stdout;
    }
    final err = result.stderr.trim();
    final out = result.stdout.trim();
    final detail = err.isEmpty ? out : err;
    appLogger.d('[Git] ${args.join(' ')} exit ${result.exitCode}: $detail');
    throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
  }

  /// Unified diff of staged changes (`git diff --cached`), capped at
  /// [maxChars] to bound prompt size.
  Future<String> stagedDiff(String dir, {int maxChars = 12000}) async {
    final out = await _run(dir, ['diff', '--cached', '--no-color']);
    if (out.length <= maxChars) return out;
    final dropped = out.length - maxChars;
    return '${out.substring(0, maxChars)}\n\n'
        '[diff truncated: $dropped more characters]';
  }

  /// Concatenated HEAD-vs-worktree diffs for [paths], each path handled like
  /// [diffAgainstHead] (untracked via --no-index). Used to summarize the
  /// selected changes for a generated commit message.
  Future<String> diffSelectedPaths(String dir, List<String> paths) async {
    final parts = <String>[];
    for (final path in paths) {
      final d = await diffAgainstHead(dir, path);
      if (d.isNotEmpty) parts.add(d);
    }
    return parts.join('\n');
  }

  Future<void> stage(String dir, List<String> paths) =>
      _run(dir, ['add', '--', ...paths]);

  Future<void> unstage(String dir, List<String> paths) =>
      _run(dir, ['reset', '-q', 'HEAD', '--', ...paths]);

  Future<void> stageAll(String dir) => _run(dir, ['add', '-A']);

  Future<void> unstageAll(String dir) => _run(dir, ['reset', '-q', 'HEAD']);

  Future<void> discard(String dir, GitFileChange change) {
    if (change.kind == GitChangeKind.untracked) {
      return _run(dir, ['clean', '-f', '--', change.path]);
    }
    return _run(dir, ['restore', '--', change.path]);
  }

  /// Discards all unstaged changes to tracked files. Untracked files are
  /// left alone (they would need `git clean`, which is destructive).
  Future<void> discardAll(String dir) => _run(dir, ['restore', '.']);

  /// Discards unstaged changes to tracked files under [folderPath].
  Future<void> discardFolder(String dir, String folderPath) =>
      _run(dir, ['restore', '--', folderPath]);

  Future<void> commit(String dir, String message) =>
      _run(dir, ['commit', '-m', message]);

  /// Stages [paths] then commits exactly those paths. `git add` handles
  /// untracked and deleted files; `git commit -- <paths>` restricts the commit
  /// to the selected set, leaving any other index entries alone.
  Future<void> commitSelected(
    String dir,
    String message,
    List<String> paths,
  ) async {
    await _run(dir, ['add', '--', ...paths]);
    await _run(dir, ['commit', '-m', message, '--', ...paths]);
  }

  Future<void> push(String dir) => _run(dir, ['push']);

  Future<void> pull(String dir) => _run(dir, ['pull']);

  /// Local branch names (current branch first is not guaranteed).
  Future<List<String>> branches(String dir) async {
    final out = await _run(dir, ['branch', '--format=%(refname:short)']);
    return const LineSplitter()
        .convert(out)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Remote-tracking branch names (e.g. `origin/main`); omits `*/HEAD`.
  Future<List<String>> remoteBranches(String dir) async {
    final out = await _run(dir, ['branch', '-r', '--format=%(refname:short)']);
    return const LineSplitter()
        .convert(out)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.endsWith('/HEAD'))
        .toList();
  }

  Future<void> checkout(String dir, String name) =>
      _run(dir, ['checkout', name]);

  Future<void> createBranch(String dir, String name) =>
      _run(dir, ['checkout', '-b', name]);
}
