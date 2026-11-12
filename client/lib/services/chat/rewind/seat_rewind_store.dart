import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/rewind/rewind_work_gate.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/utils/logging/logger.dart';

String _personalize(SeatRewindTarget source, String path) {
  final member = source.memberId?.trim() ?? '';
  if (member.isEmpty) return path;
  final prefix = '$member/${source.tool}/';
  if (path.startsWith(prefix)) {
    return '${source.tool}/${path.substring(prefix.length)}';
  }
  if (path == 'acp-transcript-$member.jsonl') return 'acp-transcript.jsonl';
  if (path == 'acp-session-$member.json') return 'acp-session.json';
  return path;
}

/// [commitTurn] refused because a rewind or fork already owns this git dir.
final class RewindTurnSkipped implements Exception {
  const RewindTurnSkipped();
}

/// One recorded turn in a seat's private rewind repository.
final class RewindCheckpoint {
  const RewindCheckpoint({
    required this.commit,
    required this.parentCommit,
    required this.messageId,
    required this.userMessageId,
    required this.turnAt,
    required this.nativeSessionId,
  });

  final String commit;

  /// Empty for a root commit.
  final String parentCommit;

  /// Last message of the turn.
  final String messageId;

  /// User message that opened the turn. Empty for commits written before
  /// user-message branches existed.
  final String userMessageId;

  /// Milliseconds since epoch; orders sibling turns.
  final int turnAt;

  final String? nativeSessionId;
}

/// Private Git store for one seat's rewind checkpoints.
///
/// [gitDir] is the repository itself. [workTree] is the seat runtime directory.
/// Commands never create a `.git` directory inside [workTree].
final class SeatRewindStore {
  SeatRewindStore({
    required this.gitDir,
    required this.workTree,
    required this.target,
    GitCommandRunner? git,
    Filesystem? fs,
    String gitExecutable = 'git',
    this.commandTimeout = const Duration(seconds: 30),
  })  : gitExecutable = gitExecutable,
        git = git ?? LocalGitCommandRunner(gitExecutable: gitExecutable),
        fs = fs ?? LocalFilesystem();

  /// Resolves the one canonical repository location for a seat.
  ///
  /// Checkpoint writers and the history/UI path must share this factory; a
  /// second copy of the path rule silently splits one seat into two repos.
  factory SeatRewindStore.forSession({
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required SeatRewindTarget target,
    String gitExecutable = 'git',
    Duration commandTimeout = const Duration(seconds: 30),
  }) {
    return SeatRewindStore(
      gitDir: layout.pathContext.join(
        layout.workspace.sessionDir(workspaceId, sessionId),
        'rewind',
        target.seatKey,
      ),
      workTree: layout.workspace.sessionRuntimeDir(workspaceId, sessionId),
      target: target,
      gitExecutable: gitExecutable,
      commandTimeout: commandTimeout,
    );
  }

  /// Resolves the canonical repository for the active [RuntimeContext], wiring
  /// the context's [Filesystem] and the backend-matched [GitCommandRunner].
  factory SeatRewindStore.forContext({
    required RuntimeContext context,
    required String workspaceId,
    required String sessionId,
    required SeatRewindTarget target,
    String? gitExecutable,
    Duration commandTimeout = const Duration(seconds: 30),
  }) => SeatRewindStore(
    gitDir: context.layout.pathContext.join(
      context.layout.workspace.sessionDir(workspaceId, sessionId),
      'rewind',
      target.seatKey,
    ),
    workTree: context.layout.workspace.sessionRuntimeDir(workspaceId, sessionId),
    target: target,
    git: gitCommandRunnerForContext(context, gitExecutable: gitExecutable),
    fs: context.filesystem,
    commandTimeout: commandTimeout,
  );

  final String gitDir;
  final String workTree;
  final SeatRewindTarget target;
  final String gitExecutable;
  final GitCommandRunner git;
  final Filesystem fs;

  /// Path joins use the injected filesystem's context so remote (posix) planes
  /// build their paths with the right style. The local default is [p.context].
  p.Context get paths => fs.pathContext;

  /// Upper bound for one git process. A checkpoint runs before the seat is
  /// published idle, so a stuck git process must never latch the turn forever.
  final Duration commandTimeout;

  static const _gitIdentity = {
    'GIT_AUTHOR_NAME': 'TeamPilot',
    'GIT_AUTHOR_EMAIL': 'teampilot@localhost',
    'GIT_COMMITTER_NAME': 'TeamPilot',
    'GIT_COMMITTER_EMAIL': 'teampilot@localhost',
  };

  List<String> get _repoArgs => ['--git-dir', gitDir, '--work-tree', workTree];

  /// Whether this seat has a rewind repository yet.
  Future<bool> repoExists() async => (await fs.stat(gitDir)).exists;

  Future<void> ensureRepo() async {
    if (!(await fs.stat(paths.join(gitDir, 'HEAD'))).exists) {
      await fs.ensureDir(gitDir);
      await _runGit(['--git-dir', gitDir, 'init']);
      // Runtime bytes must round-trip verbatim. A user/global git config with
      // autocrlf, executable-bit tracking, or symlink checkout would rewrite
      // JSONL/DB sidecars and break a restore. Repo-local config is written
      // once at init, not on every turn.
      for (final entry in const {
        'core.autocrlf': 'false',
        'core.fileMode': 'false',
        'core.symlinks': 'false',
      }.entries) {
        await _runGit(['--git-dir', gitDir, 'config', entry.key, entry.value]);
      }
    }
    final excludePath = paths.join(gitDir, 'info', 'exclude');
    await fs.ensureDir(paths.dirname(excludePath));
    await fs.writeString(excludePath, '${rewindExcludeNames.join('\n')}\n');
  }

  Future<RewindCheckpoint> commitTurn({
    required String messageId,
    String userMessageId = '',
    String? nativeSessionId,
    RewindWorkGate? gate,
  }) async {
    if (gate != null && gate.isInProgress(gitDir)) {
      AppLogger.instance.d(
        '[rewind] commitTurn skipped; rewind or fork in progress '
        'gitDir=$gitDir',
      );
      throw const RewindTurnSkipped();
    }
    await ensureRepo();
    await _dropStaleSeatIndexEntries();
    await _addIncludedFiles(await _includedRuntimeFiles());
    final tree = (await _runGit([..._repoArgs, 'write-tree'])).trim();
    final parent = await checkedOut() ?? await root();
    final turnAt = DateTime.now().millisecondsSinceEpoch;
    final message =
        'checkpoint\n'
        '\n'
        'Turn-Message: $messageId\n'
        'Turn-User: $userMessageId\n'
        'Turn-At: $turnAt\n'
        'Native-Session: ${nativeSessionId ?? ''}';
    final commit = (await _runGit([
      ..._repoArgs,
      'commit-tree',
      tree,
      '-p',
      parent,
      '-m',
      message,
    ], environment: _gitIdentity)).trim();
    await _runGit([
      ..._repoArgs,
      'update-ref',
      'refs/rewind/keep/$messageId',
      commit,
    ]);
    await _runGit([..._repoArgs, 'update-ref', 'refs/rewind/live', commit]);
    await _runGit([
      ..._repoArgs,
      'update-ref',
      'refs/rewind/checked-out',
      commit,
    ]);
    return RewindCheckpoint(
      commit: commit,
      parentCommit: parent,
      messageId: messageId,
      userMessageId: userMessageId,
      turnAt: turnAt,
      nativeSessionId: nativeSessionId,
    );
  }

  /// Adds every included file in one git process.
  ///
  /// One process per file is both slow on Windows and amplifies a streaming
  /// turn into hundreds of spawns. Older git versions without
  /// `--pathspec-from-file` fall back to the per-file path.
  Future<void> _addIncludedFiles(List<String> files) async {
    if (files.isEmpty) return;
    try {
      await _runGit([
        ..._repoArgs,
        'add',
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ], stdinText: '${files.join('\x00')}\x00');
    } on StateError {
      for (final relative in files) {
        await _runGit([..._repoArgs, 'add', '--', relative]);
      }
    }
  }

  Future<void> restore(String commit) async {
    final previous = await checkedOut();
    try {
      await _writeSeatFromCommit(commit);
    } catch (_) {
      if (previous != null) {
        await _writeSeatFromCommit(previous);
      }
      rethrow;
    }
    await _runGit([
      ..._repoArgs,
      'update-ref',
      'refs/rewind/checked-out',
      commit,
    ]);
  }

  Future<String?> checkedOut() async {
    if (!(await fs.stat(gitDir)).exists) return null;
    final result = await _runGit([
      ..._repoArgs,
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/rewind/checked-out',
    ], allowFailure: true);
    final sha = result.trim();
    return sha.isEmpty ? null : sha;
  }

  /// Empty seat state, used as the parent of the first turn.
  ///
  /// Written once per seat. Restoring it clears the seat's included files so
  /// the next launch starts a fresh agent session.
  Future<String> root() async {
    if (!(await fs.stat(gitDir)).exists) await ensureRepo();
    final existing = (await _runGit([
      ..._repoArgs,
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/rewind/root',
    ], allowFailure: true)).trim();
    if (existing.isNotEmpty) return existing;
    final indexFile = paths.join(gitDir, 'root-index');
    try {
      final tree = (await _runGit(
        [..._repoArgs, 'write-tree'],
        environment: {'GIT_INDEX_FILE': indexFile},
      )).trim();
      final commit = (await _runGit([
        ..._repoArgs,
        'commit-tree',
        tree,
        '-m',
        'root',
      ], environment: _gitIdentity)).trim();
      await _runGit([..._repoArgs, 'update-ref', 'refs/rewind/root', commit]);
      return commit;
    } finally {
      if ((await fs.stat(indexFile)).exists) {
        await fs.removeRecursive(indexFile);
      }
    }
  }

  /// Newest descendant of [commit], including [commit] itself.
  Future<String> branchTip(String commit) async {
    final turns = await checkpoints();
    final byCommit = {for (final turn in turns) turn.commit: turn};
    final start = byCommit[commit];
    if (start == null) return commit;
    final children = <String, List<RewindCheckpoint>>{};
    for (final turn in turns) {
      if (turn.parentCommit.isEmpty) continue;
      children.putIfAbsent(turn.parentCommit, () => []).add(turn);
    }
    var best = start;
    final stack = <String>[start.commit];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final child in children[current] ?? const <RewindCheckpoint>[]) {
        if (child.turnAt >= best.turnAt) best = child;
        stack.add(child.commit);
      }
    }
    return best.commit;
  }

  /// Checkpoints oldest first, ordered by ancestry so turns that end in the
  /// same second still list deterministically. A commit without a keep ref is
  /// never a checkpoint and is dropped.
  ///
  /// The history UI reads this on every turn end, so the bodies come back in
  /// one `git log` rather than one process per checkpoint.
  Future<List<RewindCheckpoint>> checkpoints() async {
    if (!(await fs.stat(gitDir)).exists) return const [];
    final listed = await _runGit([
      ..._repoArgs,
      'for-each-ref',
      '--format=%(objectname)',
      'refs/rewind/keep',
    ], allowFailure: true);
    final kept = const LineSplitter()
        .convert(listed)
        .where((commit) => commit.isNotEmpty)
        .toSet();
    if (kept.isEmpty) return const [];
    // Feed revisions through stdin: a long-lived seat can accumulate more
    // keep refs than the Windows command line (or ARG_MAX) allows.
    final walked = const LineSplitter().convert(
      await _runGit(
        [..._repoArgs, 'rev-list', '--reverse', '--topo-order', '--stdin'],
        stdinText: '${kept.join('\n')}\n',
        allowFailure: true,
      ),
    );
    final walkedSet = walked.toSet();
    final ordered = [
      for (final commit in walked)
        if (kept.contains(commit)) commit,
      // A tip the walk cannot reach still lists after the reachable ones.
      for (final commit in kept)
        if (!walkedSet.contains(commit)) commit,
    ];
    if (ordered.isEmpty) return const [];
    final bodies = await _runGit(
      [
        ..._repoArgs,
        'log',
        '--no-walk=unsorted',
        '--format=%H%x00%P%x00%B%x01',
        '--stdin',
      ],
      stdinText: '${ordered.join('\n')}\n',
      allowFailure: true,
    );
    final records = <String, ({String parents, String body})>{};
    for (final record in bodies.split('\x01')) {
      final entry = record.trimLeft();
      final first = entry.indexOf('\x00');
      if (first <= 0) continue;
      final second = entry.indexOf('\x00', first + 1);
      if (second < 0) continue;
      records[entry.substring(0, first).trim()] = (
        parents: entry.substring(first + 1, second).trim(),
        body: entry.substring(second + 1),
      );
    }
    return [
      for (final commit in ordered)
        _parseCheckpoint(
          commit,
          records[commit]?.body ?? '',
          records[commit]?.parents ?? '',
        ),
    ];
  }

  /// Copy [commit] and its ancestors into a new store at [destTarget]'s layout.
  Future<SeatRewindStore> forkAt({
    required String commit,
    required String destGitDir,
    required String destWorkTree,
    required SeatRewindTarget destTarget,
  }) async {
    final dest = SeatRewindStore(
      gitDir: destGitDir,
      workTree: destWorkTree,
      target: destTarget,
      git: git,
      fs: fs,
      gitExecutable: gitExecutable,
      commandTimeout: commandTimeout,
    );
    await dest.ensureRepo();
    await dest._fetchCommit(gitDir, commit);
    await dest._runGit([
      '--git-dir',
      destGitDir,
      'update-ref',
      'refs/rewind/live',
      'FETCH_HEAD',
    ]);
    await dest._runGit([
      '--git-dir',
      destGitDir,
      'update-ref',
      'refs/rewind/checked-out',
      'FETCH_HEAD',
    ]);
    await _copyAncestorKeepRefs(dest, commit);
    await _writePersonalizedWorkTree(dest, commit);
    return dest;
  }

  /// `git show <commit>:<path>` bytes decoded as UTF-8, or null when missing
  /// or not valid UTF-8 (binary CLI files such as `opencode.db`).
  Future<String?> showFile(String commit, String path) async {
    final result = await git.runRaw(
      [..._repoArgs, 'show', '$commit:$path'],
      workingDirectory: workTree,
      allowFailure: true,
      timeout: commandTimeout,
    );
    if (result.exitCode == 0) return _utf8OrNull(result.stdout);
    if (target.seatKey != 'personal') return null;
    final sourcePath = await _personalizedSourcePath(commit, path);
    if (sourcePath == null) return null;
    final mapped = await git.runRaw(
      [..._repoArgs, 'show', '$commit:$sourcePath'],
      workingDirectory: workTree,
      allowFailure: true,
      timeout: commandTimeout,
    );
    if (mapped.exitCode != 0) return null;
    return _utf8OrNull(mapped.stdout);
  }

  String? _utf8OrNull(List<int> stdout) {
    try {
      return utf8.decode(stdout);
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeSeatFromCommit(String commit) async {
    final treePaths = await _treePaths(commit);
    if (treePaths.isEmpty && target.seatKey == 'personal') {
      // The root checkpoint: the seat had no files before its first turn.
      await _deleteIncludedFilesNotIn(const {});
      return;
    }
    if (treePaths.any(target.includes) || target.seatKey != 'personal') {
      // `git checkout <commit> -- <pathspec>` fails when any pathspec matches
      // nothing. A checkpoint can legitimately omit a sidecar (or the whole
      // tool dir), so checkout only paths that actually exist in the commit.
      final existing = [
        for (final path in treePaths)
          if (target.includes(path) && !target.isExcluded(path)) path,
      ];
      if (existing.isNotEmpty) {
        await _runGit([..._repoArgs, 'checkout', commit, '--', ...existing]);
      }
      await _deleteIncludedFilesNotIn(treePaths.toSet());
      return;
    }
    final memberId = _inferSourceMemberId(treePaths);
    if (memberId == null) return;
    final source = SeatRewindTarget(
      kind: target.kind,
      tool: target.tool,
      memberId: memberId,
    );
    final names = <String>{};
    for (final path in treePaths) {
      final relative = _personalize(source, path);
      if (!target.includes(relative) || target.isExcluded(relative)) {
        continue;
      }
      names.add(relative);
      await _writeRawBlob(commit, path, relative);
    }
    if (names.isEmpty) return;
    await _deleteIncludedFilesNotIn(names);
  }

  /// Drops index entries for this seat that are no longer a regular work-tree
  /// file. Leaves other seats, excluded paths, and never-added symlinks alone.
  Future<void> _dropStaleSeatIndexEntries() async {
    final listed = await _runGit([
      ..._repoArgs,
      'ls-files',
      '-z',
    ], allowFailure: true);
    final stale = <String>[];
    for (final relative in listed.split('\x00')) {
      if (relative.isEmpty) continue;
      if (!target.includes(relative) || target.isExcluded(relative)) {
        continue;
      }
      final kind = (await fs.lstat(paths.join(workTree, relative))).kind;
      if (kind == FsEntityKind.file) continue;
      stale.add(relative);
    }
    if (stale.isEmpty) return;
    try {
      await _runGit([
        ..._repoArgs,
        'rm',
        '--cached',
        '--ignore-unmatch',
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ], stdinText: '${stale.join('\x00')}\x00');
    } on StateError {
      for (final relative in stale) {
        await _runGit([
          ..._repoArgs,
          'rm',
          '--cached',
          '--ignore-unmatch',
          '--',
          relative,
        ]);
      }
    }
  }

  RewindCheckpoint _parseCheckpoint(
    String commit,
    String body,
    String parents,
  ) {
    String messageId = '';
    String userMessageId = '';
    var turnAt = 0;
    String? nativeSessionId;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('Turn-Message:')) {
        messageId = line.substring('Turn-Message:'.length).trim();
      } else if (line.startsWith('Turn-User:')) {
        userMessageId = line.substring('Turn-User:'.length).trim();
      } else if (line.startsWith('Turn-At:')) {
        turnAt = int.tryParse(line.substring('Turn-At:'.length).trim()) ?? 0;
      } else if (line.startsWith('Native-Session:')) {
        final value = line.substring('Native-Session:'.length).trim();
        nativeSessionId = value.isEmpty ? null : value;
      }
    }
    return RewindCheckpoint(
      commit: commit,
      parentCommit: parents.split(' ').first.trim(),
      messageId: messageId,
      userMessageId: userMessageId,
      turnAt: turnAt,
      nativeSessionId: nativeSessionId,
    );
  }

  Future<void> _fetchCommit(String sourceGitDir, String commit) async {
    final fetched = await _runGitResult([
      '--git-dir',
      gitDir,
      'fetch',
      sourceGitDir,
      commit,
    ], allowFailure: true);
    if (fetched.exitCode == 0) return;
    final fetchSource = paths.style == p.Style.posix
        ? sourceGitDir
        : Uri.file(sourceGitDir).toString();
    await _runGit([
      '--git-dir',
      gitDir,
      'fetch',
      fetchSource,
      commit,
    ]);
  }

  Future<void> _copyAncestorKeepRefs(
    SeatRewindStore dest,
    String commit,
  ) async {
    final listed = await _runGit([
      '--git-dir',
      gitDir,
      'for-each-ref',
      '--format=%(objectname) %(refname)',
      'refs/rewind/keep',
    ], allowFailure: true);
    final reachable = const LineSplitter()
        .convert(
          await _runGit([
            '--git-dir',
            gitDir,
            'rev-list',
            commit,
          ], allowFailure: true),
        )
        .where((line) => line.isNotEmpty)
        .toSet();
    if (reachable.isEmpty) return;
    final updates = <String>[];
    for (final line in const LineSplitter().convert(listed)) {
      if (line.isEmpty) continue;
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      final keepCommit = line.substring(0, space);
      final refName = line.substring(space + 1);
      if (!reachable.contains(keepCommit)) continue;
      updates.add('update $refName $keepCommit');
    }
    if (updates.isEmpty) return;
    await dest._runGit([
      '--git-dir',
      dest.gitDir,
      'update-ref',
      '--stdin',
    ], stdinText: '${updates.join('\n')}\n');
  }

  Future<void> _writePersonalizedWorkTree(
    SeatRewindStore dest,
    String commit,
  ) async {
    final listed = await _runGit([
      '--git-dir',
      gitDir,
      'ls-tree',
      '-r',
      '--name-only',
      commit,
    ]);
    for (final path in const LineSplitter().convert(listed)) {
      if (path.isEmpty) continue;
      await dest._writeRawBlob(commit, path, _personalize(target, path));
    }
  }

  Future<List<String>> _treePaths(
    String commit, {
    bool allowFailure = false,
  }) async {
    final listed = await _runGit([
      ..._repoArgs,
      'ls-tree',
      '-r',
      '--name-only',
      commit,
    ], allowFailure: allowFailure);
    return [
      for (final line in const LineSplitter().convert(listed))
        if (line.isNotEmpty) line,
    ];
  }

  Future<String?> _personalizedSourcePath(String commit, String path) async {
    final treePaths = await _treePaths(commit, allowFailure: true);
    final memberId = _inferSourceMemberId(treePaths);
    if (memberId == null) return null;
    final source = SeatRewindTarget(
      kind: target.kind,
      tool: target.tool,
      memberId: memberId,
    );
    String? unique;
    for (final treePath in treePaths) {
      if (_personalize(source, treePath) != path) continue;
      if (unique != null) return null;
      unique = treePath;
    }
    return unique;
  }

  String? _inferSourceMemberId(Iterable<String> paths) {
    final ids = <String>{};
    for (final path in paths) {
      final id = _memberIdFromTreePath(path);
      if (id != null) ids.add(id);
    }
    return ids.length == 1 ? ids.single : null;
  }

  String? _memberIdFromTreePath(String path) {
    final slash = path.indexOf('/');
    if (slash > 0) {
      final rest = path.substring(slash + 1);
      if (rest == target.tool || rest.startsWith('${target.tool}/')) {
        return path.substring(0, slash);
      }
    }
    return _sidecarMemberId(path, 'acp-session-', '.json') ??
        _sidecarMemberId(path, 'acp-transcript-', '.jsonl');
  }

  String? _sidecarMemberId(String path, String prefix, String suffix) {
    if (path.contains('/')) return null;
    if (!path.startsWith(prefix) || !path.endsWith(suffix)) return null;
    final id = path.substring(prefix.length, path.length - suffix.length);
    return id.isEmpty ? null : id;
  }

  Future<void> _writeRawBlob(
    String commit,
    String sourcePath,
    String destRelative,
  ) async {
    final destPath = paths.join(workTree, destRelative);
    await fs.ensureDir(paths.dirname(destPath));
    // Never follow a CLI-created symlink out of the work tree.
    if ((await fs.lstat(destPath)).isSymlink) {
      await fs.removeRecursive(destPath);
    }
    final args = [
      '--git-dir',
      gitDir,
      'show',
      '$commit:$sourcePath',
    ];
    await git.runToFile(
      args,
      destPath,
      workingDirectory: args.contains('--work-tree') ? workTree : null,
      timeout: commandTimeout,
    );
  }

  Future<void> _deleteIncludedFilesNotIn(Set<String> keep) async {
    for (final relative in await _includedRuntimeFiles()) {
      if (keep.contains(relative)) continue;
      await fs.removeRecursive(paths.join(workTree, relative));
    }
  }

  /// Regular files of this seat under [workTree], walked from the included
  /// prefixes only.
  ///
  /// Excluded names and symlinks are skipped without descending, so a shared
  /// plugin or cache tree never enters the walk. A directory that disappears
  /// or cannot be listed mid-walk (a marketplace refresh pruning a plugin
  /// tree) is skipped instead of failing the whole checkpoint.
  Future<List<String>> _includedRuntimeFiles() async {
    final found = <String>[];
    if (!(await fs.stat(workTree)).exists) return found;

    Future<void> visit(String dirPath, String relative) async {
      List<FsDirEntry> entries;
      try {
        entries = await fs.listDir(dirPath);
      } on Object catch (error) {
        if (error is TypeError ||
            error is NoSuchMethodError ||
            error is ArgumentError) {
          rethrow;
        }
        AppLogger.instance.w(
          '[rewind] skipped runtime directory $dirPath: $error',
        );
        return;
      }
      for (final entry in entries) {
        final name = entry.name;
        final child = relative.isEmpty ? name : '$relative/$name';
        final childPath = paths.join(dirPath, name);
        final kind = (await fs.lstat(childPath)).kind;
        if (kind == FsEntityKind.directory) {
          if (target.isExcluded(child) || !_mayIncludeUnder(child)) continue;
          await visit(childPath, child);
          continue;
        }
        if (kind != FsEntityKind.file) continue;
        if (!target.includes(child) || target.isExcluded(child)) continue;
        found.add(child);
      }
    }

    await visit(workTree, '');
    return found;
  }

  /// Whether [directory] can hold files this seat includes, either because it
  /// sits under an included prefix or because it is an ancestor of one.
  bool _mayIncludeUnder(String directory) {
    for (final prefix in target.includedPrefixes) {
      if (prefix == directory ||
          directory.startsWith('$prefix/') ||
          prefix.startsWith('$directory/')) {
        return true;
      }
    }
    return false;
  }

  Future<({String stdout, int exitCode})> _runGitResult(
    List<String> args, {
    bool allowFailure = false,
    Map<String, String>? environment,
    String? stdinText,
  }) async {
    final result = await git.runRaw(
      args,
      workingDirectory: args.contains('--work-tree') ? workTree : null,
      environment: environment,
      stdinText: stdinText,
      allowFailure: allowFailure,
      timeout: commandTimeout,
    );
    return (
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      exitCode: result.exitCode,
    );
  }

  Future<String> _runGit(
    List<String> args, {
    bool allowFailure = false,
    Map<String, String>? environment,
    String? stdinText,
  }) async {
    final result = await _runGitResult(
      args,
      allowFailure: allowFailure,
      environment: environment,
      stdinText: stdinText,
    );
    return result.stdout;
  }
}
