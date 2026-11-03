import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/utils/logging/logger.dart';

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
  }) async {
    await ensureRepo();
    await for (final entity in Directory(
      workTree,
    ).list(recursive: true, followLinks: false)) {
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) continue;
      final relative = _repoRelative(entity.path);
      if (!target.includes(relative) || target.isExcluded(relative)) {
        continue;
      }
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

  Future<String?> checkedOut() async {
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

  Future<List<RewindCheckpoint>> checkpoints() async {
    final listed = await _runGit([
      ..._repoArgs,
      'for-each-ref',
      '--format=%(objectname)',
      'refs/rewind/keep',
    ], allowFailure: true);
    final checkpoints = <RewindCheckpoint>[];
    for (final commit in const LineSplitter().convert(listed)) {
      if (commit.isEmpty) continue;
      final body = await _runGit([
        ..._repoArgs,
        'log',
        '-1',
        '--format=%B',
        commit,
      ]);
      checkpoints.add(_parseCheckpoint(commit, body));
    }
    return checkpoints;
  }

  /// `git show <commit>:<path>` bytes decoded as UTF-8, or null when missing.
  Future<String?> showFile(String commit, String path) async {
    final result = await Process.run(
      gitExecutable,
      [..._repoArgs, 'show', '$commit:$path'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }

  String _repoRelative(String absolutePath) {
    return p
        .relative(p.normalize(absolutePath), from: p.normalize(workTree))
        .replaceAll('\\', '/');
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

  Future<String> _runGit(
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
    return result.stdout as String;
  }
}
