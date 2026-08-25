import '../../models/git_graph.dart';
import '../../utils/logging/logger.dart';
import '../storage/runtime_context.dart';
import 'git_command_runner.dart';
import 'git_service.dart' show GitException;
import 'parser/git_graph_parser.dart';

/// 只读历史查询：graph / commit 详情 / 分支标签 / stash（`git log/show/
/// diff-tree/for-each-ref/stash list`），不做任何写操作。
class GitHistoryService {
  GitHistoryService({GitCommandRunner? runner})
    : _runner = runner ?? LocalGitCommandRunner();

  factory GitHistoryService.forContext(RuntimeContext ctx) =>
      GitHistoryService(runner: gitCommandRunnerForContext(ctx));

  /// 测试缝（同 [GitService.debugOverrideFactory] 模式）。
  static GitHistoryService Function()? debugOverrideFactory;

  static const int initialLoadCommits = 300;
  static const int loadMoreCommits = 100;

  static const String _recordSep = '\x1e';
  static const String _fieldSep = '\x1f';
  static final String _commitFormat =
      '%x1e${['%H', '%P', '%an', '%ae', '%at', '%d', '%s'].join(_fieldSep)}';
  static final String _showFormat =
      ['%H', '%P', '%an', '%ae', '%at', '%s', '%B'].join(_fieldSep);

  final GitCommandRunner _runner;

  Future<String> _run(String dir, List<String> args) async {
    final result = await _runner.runInDirectory(dir, args);
    if (result.exitCode != 0) {
      final detail = result.stderr.trim().isEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      appLogger.d(
        '[GitHistory] ${args.join(' ')} exit ${result.exitCode}: $detail',
      );
      throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
    }
    return result.stdout;
  }

  Future<List<String>> remotes(String dir) async =>
      (await _run(dir, [
            'remote',
          ]))
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);

  Set<String> remotePrefixes(List<String> remotes) =>
      {for (final r in remotes) '$r/'};

  /// 提交拓扑行。query/mode 组成搜索过滤：
  /// message → `--grep=<q> -i`；author → `--author=<q>`；hash → 客户端过滤。
  /// [revisionRange] 为 null → `--all`；否则替换为给定范围（如 `HEAD`）。
  Future<List<GitGraphRow>> graphRows(
    String dir, {
    int limit = initialLoadCommits,
    int skip = 0,
    String query = '',
    GitSearchMode mode = GitSearchMode.message,
    String? revisionRange,
  }) async {
    final args = <String>[
      'log',
      revisionRange ?? '--all',
      '--date-order',
      if (skip > 0) ...['--skip', '$skip'],
      '--max-count',
      '$limit',
      '--pretty=format:$_commitFormat',
      '--graph',
      if (query.isNotEmpty && mode == GitSearchMode.message) ...[
        '--grep=$query',
        '-i',
      ],
      if (query.isNotEmpty && mode == GitSearchMode.author)
        '--author=$query',
    ];
    return GitGraphParser.parse(
      await _run(dir, args),
      remotePrefixes: remotePrefixes(await remotes(dir)),
    );
  }

  Future<GitCommitDetail> commitDetail(String dir, String hash) async {
    final meta =
        (await _run(dir, ['show', '-s', '--pretty=format:$_showFormat', hash]))
            .trim();
    final fields = meta.startsWith(_recordSep)
        ? meta.substring(1).split(_fieldSep)
        : meta.split(_fieldSep);
    if (fields.length < 7) {
      throw GitException('unexpected git show output for $hash');
    }
    final ts = int.tryParse(fields[4]) ?? 0;
    final files = await commitFiles(dir, hash);
    return GitCommitDetail(
      hash: fields[0],
      parents: fields[1].trim().isEmpty ? const [] : fields[1].trim().split(' '),
      authorName: fields[2],
      authorEmail: fields[3],
      authorDate: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
      subject: fields[5],
      body: fields.sublist(6).join(_fieldSep),
      files: files,
    );
  }

  Future<List<GitCommitFileChange>> commitFiles(String dir, String hash) async {
    final out = await _run(dir, [
      'diff-tree',
      '--no-commit-id',
      '--name-status',
      '-r',
      '--root',
      hash,
    ]);
    final files = <GitCommitFileChange>[];
    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('\t');
      if (parts.isEmpty) continue;
      final statusLetter = parts.first.trim();
      final status = switch (statusLetter.isEmpty
          ? ''
          : statusLetter[0]) {
        'A' => GitCommitFileStatus.added,
        'M' => GitCommitFileStatus.modified,
        'D' => GitCommitFileStatus.deleted,
        'R' => GitCommitFileStatus.renamed,
        'T' => GitCommitFileStatus.typeChanged,
        _ => GitCommitFileStatus.modified,
      };
      // R100\t<old>\t<new> / C100\t<old>\t<new>
      if ((status == GitCommitFileStatus.renamed) && parts.length >= 3) {
        files.add(
          GitCommitFileChange(parts[2], status, previousPath: parts[1]),
        );
      } else if (parts.length >= 2) {
        files.add(GitCommitFileChange(parts[1], status));
      }
    }
    return files;
  }

  Future<String> commitFileDiff(
    String dir, {
    required String hash,
    String? parent,
    required String path,
  }) =>
      parent == null
          ? _run(dir, [
              'diff-tree',
              '-p',
              '--root',
              '--no-commit-id',
              hash,
              '--',
              path,
            ])
          : _run(dir, ['diff', parent, hash, '--', path]);

  Future<List<GitBranchInfo>> branches(String dir) async {
    final local = await _run(dir, [
      'for-each-ref',
      'refs/heads',
      '--format=%(refname:short)\x1f%(objectname)\x1f%(HEAD)',
    ]);
    final remote = await _run(dir, [
      'for-each-ref',
      'refs/remotes',
      '--format=%(refname:short)\x1f%(objectname)',
    ]);
    GitBranchInfo parse(String line, {required bool isRemote}) {
      final p = line.split(_fieldSep);
      return GitBranchInfo(
        p[0].trim(),
        p.length > 1 ? p[1].trim() : '',
        isRemote: isRemote,
        isCurrent: !isRemote && (p.length > 2 ? p[2].trim() == '*' : false),
      );
    }

    return [
      for (final l in local.split('\n'))
        if (l.trim().isNotEmpty) parse(l, isRemote: false),
      for (final l in remote.split('\n'))
        if (l.trim().isNotEmpty) parse(l, isRemote: true),
    ];
  }

  Future<List<GitTagInfo>> tags(String dir) async {
    final out = await _run(dir, [
      'for-each-ref',
      'refs/tags',
      '--format=%(refname:short)\x1f%(objectname)',
    ]);
    return [
      for (final l in out.split('\n'))
        if (l.trim().isNotEmpty)
          () {
            final p = l.split(_fieldSep);
            return GitTagInfo(p[0].trim(), p.length > 1 ? p[1].trim() : '');
          }(),
    ];
  }

  Future<List<GitStashEntry>> stashList(String dir) async {
    final out = await _run(dir, [
      'stash',
      'list',
      '--pretty=format:%gd\x1f%H\x1f%s',
    ]);
    return [
      for (final l in out.split('\n'))
        if (l.trim().isNotEmpty)
          () {
            final p = l.split(_fieldSep);
            return GitStashEntry(
              p[0].trim(),
              p.length > 1 ? p[1].trim() : '',
              p.length > 2 ? p[2].trim() : '',
            );
          }(),
    ];
  }
}
