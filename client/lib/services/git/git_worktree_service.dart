import '../../models/git_worktree.dart';
import '../../utils/logger.dart';
import '../storage/runtime_context.dart';
import 'git_command_runner.dart';
import 'git_service.dart' show GitException;

/// Runs `git worktree …` for the worktree sidebar on the active storage
/// backend (native, WSL, or SSH remote host).
class GitWorktreeService {
  GitWorktreeService({GitCommandRunner? runner})
    : _runner = runner ?? LocalGitCommandRunner();

  /// Builds a service for [ctx]'s storage backend.
  factory GitWorktreeService.forContext(RuntimeContext ctx) =>
      GitWorktreeService(runner: gitCommandRunnerForContext(ctx));

  final GitCommandRunner _runner;

  /// Parse `git worktree list --porcelain` output. [nulDelimited] for the
  /// `-z` form (fields NUL-delimited, records terminated by an extra NUL).
  static List<GitWorktree> parseWorktreeList(
    String output, {
    required bool nulDelimited,
  }) {
    final blocks = nulDelimited
        ? _splitNulBlocks(output)
        : _splitLineBlocks(output);
    final result = <GitWorktree>[];
    for (final lines in blocks) {
      if (lines.isEmpty) continue;
      var path = '';
      var head = '';
      var branch = '';
      var isBare = false;
      for (final line in lines) {
        if (line.startsWith('worktree ')) {
          path = line.substring('worktree '.length);
        } else if (line.startsWith('HEAD ')) {
          head = line.substring('HEAD '.length);
        } else if (line.startsWith('branch ')) {
          branch = line.substring('branch '.length);
        } else if (line == 'bare') {
          isBare = true;
        }
        // 'detached' → leave branch empty (isDetached getter returns true).
      }
      if (path.isEmpty) continue;
      result.add(
        GitWorktree(
          path: path,
          head: head,
          branch: branch,
          isBare: isBare,
          isMainWorktree: result.isEmpty,
        ),
      );
    }
    return result;
  }

  static List<List<String>> _splitLineBlocks(String output) => output
      .trim()
      .split(RegExp(r'\r?\n\r?\n'))
      .where((b) => b.trim().isNotEmpty)
      .map((b) => b.trim().split(RegExp(r'\r?\n')))
      .toList();

  /// Split NUL-delimited (`-z`) porcelain output into blocks.
  ///
  /// `git worktree list --porcelain -z` emits fields separated by `\x00`
  /// and terminates each record with an extra `\x00` (so two consecutive
  /// NULs mark the record boundary). Splitting on `\x00` gives a sequence
  /// of field strings; an empty string signals the end of a record.
  static List<List<String>> _splitNulBlocks(String output) {
    const nul = '\x00';
    if (!output.contains(nul)) return _splitLineBlocks(output);
    final blocks = <List<String>>[];
    var current = <String>[];
    for (final field in output.split(nul)) {
      if (field.isNotEmpty) {
        current.add(field);
      } else if (current.isNotEmpty) {
        blocks.add(current);
        current = <String>[];
      }
    }
    if (current.isNotEmpty) blocks.add(current);
    return blocks;
  }

  Future<String> _run(String dir, List<String> args) async {
    if (!await _runner.isAvailable) {
      throw GitException('git executable not found on PATH');
    }
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode != 0) {
      final err = result.stderr.trim();
      final out = result.stdout.trim();
      final detail = err.isEmpty ? out : err;
      appLogger.d(
        '[GitWorktree] ${args.join(' ')} exit ${result.exitCode}: $detail',
      );
      throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
    }
    return result.stdout;
  }

  /// List worktrees; empty list when [repoPath] is not a git repo or git is
  /// unavailable. Never throws — the sidebar treats "no worktrees" as the safe
  /// default (e.g. non-git workspaces, or test/sandbox hosts where locating git
  /// raises a [ProcessException]).
  Future<List<GitWorktree>> list(String repoPath) async {
    try {
      final out = await _run(repoPath, [
        'worktree',
        'list',
        '--porcelain',
        '-z',
      ]);
      return parseWorktreeList(out, nulDelimited: true);
    } on GitException catch (e) {
      // git <2.36 rejects -z; retry the plain form before giving up.
      if (_isUnknownZOption(e.message)) {
        try {
          final out = await _run(repoPath, ['worktree', 'list', '--porcelain']);
          return parseWorktreeList(out, nulDelimited: false);
        } on Object catch (e2) {
          appLogger.d('[GitWorktree] list (no -z) failed for $repoPath: $e2');
          return const [];
        }
      }
      appLogger.d('[GitWorktree] list failed for $repoPath: ${e.message}');
      return const [];
    } on Object catch (e) {
      // e.g. ProcessException when git cannot be spawned at all.
      appLogger.d('[GitWorktree] list errored for $repoPath: $e');
      return const [];
    }
  }

  static bool _isUnknownZOption(String message) => RegExp(
    r'(unknown|invalid) (switch|option).*z',
    caseSensitive: false,
  ).hasMatch(message);

  /// True when [worktreePath] has uncommitted or untracked changes. Returns
  /// false on any error (never blocks the UI on a probe failure).
  Future<bool> isDirty(String worktreePath) async {
    try {
      final out = await _run(worktreePath, [
        'status',
        '--porcelain',
        '--untracked-files=all',
      ]);
      return out.trim().isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Create a worktree. New branch (`--no-track -b`) unless [existingBranch].
  Future<void> add(
    String repoPath,
    String worktreePath, {
    required String branch,
    String? baseRef,
    bool existingBranch = false,
  }) async {
    final args = <String>['worktree', 'add'];
    if (existingBranch) {
      args.addAll([worktreePath, branch]);
    } else {
      args.addAll(['--no-track', '-b', branch, worktreePath]);
      if (baseRef != null && baseRef.isNotEmpty) args.add(baseRef);
    }
    await _run(repoPath, args);
  }

  /// Remove a worktree; optionally safe-delete its branch (`-d`).
  Future<void> remove(
    String repoPath,
    String worktreePath, {
    bool force = false,
    String? deleteBranch,
  }) async {
    final args = <String>['worktree', 'remove'];
    if (force) args.add('--force');
    args.add(worktreePath);
    await _run(repoPath, args);
    if (deleteBranch != null && deleteBranch.isNotEmpty) {
      try {
        await _run(repoPath, ['branch', '-d', '--', deleteBranch]);
      } on GitException catch (e) {
        // -d refuses unmerged branches: preserve work, don't fail the remove.
        appLogger.d('[GitWorktree] kept branch $deleteBranch: ${e.message}');
      }
    }
  }
}
