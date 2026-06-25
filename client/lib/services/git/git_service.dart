import 'dart:convert';

import '../../models/git_status.dart';
import '../../utils/logger.dart';
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
      return _run(dir, [
        'diff',
        '--no-index',
        if (ignoreWhitespace) '-w',
        if (context != null) context,
        '/dev/null',
        change.path,
      ]).catchError((Object e) {
        // `--no-index` exits 1 when files differ; surface the diff text.
        if (e is GitException) return e.message;
        throw e;
      });
    }
    final args = [
      'diff',
      if (change.staged) '--cached',
      if (ignoreWhitespace) '-w',
      if (context != null) context,
      '--',
      change.path,
    ];
    return _run(dir, args);
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

  Future<void> commit(String dir, String message) =>
      _run(dir, ['commit', '-m', message]);

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

  Future<void> checkout(String dir, String name) =>
      _run(dir, ['checkout', name]);

  Future<void> createBranch(String dir, String name) =>
      _run(dir, ['checkout', '-b', name]);
}
