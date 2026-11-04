import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/rewind/rewind_work_gate.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/utils/logging/logger.dart';

String personalize(SeatRewindTarget source, String path) {
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
    required this.messageId,
    required this.nativeSessionId,
  });

  final String commit;
  final String messageId;
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
    this.gitExecutable = 'git',
  });

  final String gitDir;
  final String workTree;
  final SeatRewindTarget target;
  final String gitExecutable;

  static const _gitIdentity = {
    'GIT_AUTHOR_NAME': 'TeamPilot',
    'GIT_AUTHOR_EMAIL': 'teampilot@localhost',
    'GIT_COMMITTER_NAME': 'TeamPilot',
    'GIT_COMMITTER_EMAIL': 'teampilot@localhost',
  };

  List<String> get _repoArgs => ['--git-dir', gitDir, '--work-tree', workTree];

  Future<void> ensureRepo() async {
    final head = File(p.join(gitDir, 'HEAD'));
    if (!await head.exists()) {
      await Directory(gitDir).create(recursive: true);
      await _runGit(['--git-dir', gitDir, 'init']);
    }
    final exclude = File(p.join(gitDir, 'info', 'exclude'));
    await exclude.parent.create(recursive: true);
    await exclude.writeAsString('${rewindExcludeNames.join('\n')}\n');
  }

  Future<RewindCheckpoint> commitTurn({
    required String messageId,
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
    for (final relative in _includedRuntimeFiles()) {
      await _runGit([..._repoArgs, 'add', '--', relative]);
    }
    final tree = (await _runGit([..._repoArgs, 'write-tree'])).trim();
    final parent = await checkedOut();
    final message =
        'checkpoint\n'
        '\n'
        'Turn-Message: $messageId\n'
        'Native-Session: ${nativeSessionId ?? ''}';
    final commit = (await _runGit([
      ..._repoArgs,
      'commit-tree',
      tree,
      if (parent != null) ...['-p', parent],
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
      messageId: messageId,
      nativeSessionId: nativeSessionId,
    );
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
    if (!Directory(gitDir).existsSync()) return null;
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

  /// Checkpoints oldest first, ordered by ancestry so turns that end in the
  /// same second still list deterministically. A commit without a keep ref is
  /// never a checkpoint and is dropped.
  ///
  /// The history UI reads this on every turn end, so the bodies come back in
  /// one `git log` rather than one process per checkpoint.
  Future<List<RewindCheckpoint>> checkpoints() async {
    if (!Directory(gitDir).existsSync()) return const [];
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
    final walked = const LineSplitter().convert(
      await _runGit([
        ..._repoArgs,
        'rev-list',
        '--reverse',
        '--topo-order',
        ...kept,
      ], allowFailure: true),
    );
    final ordered = [
      for (final commit in walked)
        if (kept.contains(commit)) commit,
      // A tip the walk cannot reach still lists after the reachable ones.
      for (final commit in kept)
        if (!walked.contains(commit)) commit,
    ];
    if (ordered.isEmpty) return const [];
    final bodies = await _runGit([
      ..._repoArgs,
      'log',
      '--no-walk=unsorted',
      '--format=%H%x00%B%x01',
      ...ordered,
    ], allowFailure: true);
    final bodyByCommit = <String, String>{};
    for (final record in bodies.split('\x01')) {
      final entry = record.trimLeft();
      final separator = entry.indexOf('\x00');
      if (separator <= 0) continue;
      bodyByCommit[entry.substring(0, separator).trim()] = entry.substring(
        separator + 1,
      );
    }
    return [
      for (final commit in ordered)
        _parseCheckpoint(commit, bodyByCommit[commit] ?? ''),
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
      gitExecutable: gitExecutable,
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
    final result = await Process.run(
      gitExecutable,
      [..._repoArgs, 'show', '$commit:$path'],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (result.exitCode == 0) return _utf8OrNull(result.stdout);
    if (target.seatKey != 'personal') return null;
    final sourcePath = await _personalizedSourcePath(commit, path);
    if (sourcePath == null) return null;
    final mapped = await Process.run(
      gitExecutable,
      [..._repoArgs, 'show', '$commit:$sourcePath'],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (mapped.exitCode != 0) return null;
    return _utf8OrNull(mapped.stdout);
  }

  String? _utf8OrNull(Object? stdout) {
    if (stdout is String) return stdout;
    if (stdout is! List<int>) return null;
    try {
      return utf8.decode(stdout);
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeSeatFromCommit(String commit) async {
    final treePaths = await _treePaths(commit);
    if (treePaths.any(target.includes) || target.seatKey != 'personal') {
      await _runGit([
        ..._repoArgs,
        'checkout',
        commit,
        '--',
        ...target.includedPrefixes,
      ]);
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
      final relative = personalize(source, path);
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
    for (final relative in listed.split('\x00')) {
      if (relative.isEmpty) continue;
      if (!target.includes(relative) || target.isExcluded(relative)) {
        continue;
      }
      final type = FileSystemEntity.typeSync(
        p.join(workTree, relative),
        followLinks: false,
      );
      if (type == FileSystemEntityType.file) continue;
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

  RewindCheckpoint _parseCheckpoint(String commit, String body) {
    String messageId = '';
    String? nativeSessionId;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('Turn-Message:')) {
        messageId = line.substring('Turn-Message:'.length).trim();
      } else if (line.startsWith('Native-Session:')) {
        final value = line.substring('Native-Session:'.length).trim();
        nativeSessionId = value.isEmpty ? null : value;
      }
    }
    return RewindCheckpoint(
      commit: commit,
      messageId: messageId,
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
    await _runGit([
      '--git-dir',
      gitDir,
      'fetch',
      Uri.file(sourceGitDir).toString(),
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
    for (final line in const LineSplitter().convert(listed)) {
      if (line.isEmpty) continue;
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      final keepCommit = line.substring(0, space);
      final refName = line.substring(space + 1);
      final ancestor = await _runGitResult([
        '--git-dir',
        gitDir,
        'merge-base',
        '--is-ancestor',
        keepCommit,
        commit,
      ], allowFailure: true);
      if (ancestor.exitCode != 0) continue;
      await dest._runGit([
        '--git-dir',
        dest.gitDir,
        'update-ref',
        refName,
        keepCommit,
      ]);
    }
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
      await dest._writeRawBlob(commit, path, personalize(target, path));
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
      if (personalize(source, treePath) != path) continue;
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
    final shown = await Process.run(
      gitExecutable,
      ['--git-dir', gitDir, 'show', '$commit:$sourcePath'],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    if (shown.exitCode != 0) {
      final stderr = shown.stderr as String;
      AppLogger.instance.e(
        'git show $commit:$sourcePath failed (${shown.exitCode}): $stderr',
      );
      throw StateError(
        'git show $commit:$sourcePath failed (${shown.exitCode}): $stderr',
      );
    }
    final destFile = File(p.join(workTree, destRelative));
    await destFile.parent.create(recursive: true);
    await destFile.writeAsBytes(shown.stdout as List<int>);
  }

  Future<void> _deleteIncludedFilesNotIn(Set<String> keep) async {
    for (final relative in _includedRuntimeFiles()) {
      if (keep.contains(relative)) continue;
      await File(p.join(workTree, relative)).delete();
    }
  }

  /// Regular files of this seat under [workTree], walked from the included
  /// prefixes only.
  ///
  /// Excluded names and symlinks are skipped without descending, so a shared
  /// plugin or cache tree never enters the walk. A directory that disappears
  /// or cannot be listed mid-walk (a marketplace refresh pruning a plugin
  /// tree) is skipped instead of failing the whole checkpoint.
  List<String> _includedRuntimeFiles() {
    final found = <String>[];
    final root = Directory(workTree);
    if (!root.existsSync()) return found;

    void visit(Directory dir, String relative) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException catch (error) {
        AppLogger.instance.w(
          '[rewind] skipped unreadable runtime directory ${dir.path}: $error',
        );
        return;
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        final child = relative.isEmpty ? name : '$relative/$name';
        final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          if (target.isExcluded(child) || !_mayIncludeUnder(child)) continue;
          visit(Directory(entry.path), child);
          continue;
        }
        if (type != FileSystemEntityType.file) continue;
        if (!target.includes(child) || target.isExcluded(child)) continue;
        found.add(child);
      }
    }

    visit(root, '');
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
  }) async {
    final result = await Process.run(
      gitExecutable,
      args,
      workingDirectory: args.contains('--work-tree') ? workTree : null,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (!allowFailure && result.exitCode != 0) {
      final stderr = result.stderr as String;
      AppLogger.instance.e(
        'git ${args.join(' ')} failed (${result.exitCode}): $stderr',
      );
      throw StateError(
        'git ${args.join(' ')} failed (${result.exitCode}): $stderr',
      );
    }
    return (stdout: result.stdout as String, exitCode: result.exitCode);
  }

  Future<String> _runGit(
    List<String> args, {
    bool allowFailure = false,
    Map<String, String>? environment,
  }) async {
    final result = await _runGitResult(
      args,
      allowFailure: allowFailure,
      environment: environment,
    );
    return result.stdout;
  }
}
