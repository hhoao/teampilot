import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart';

/// 与 test/services/git/git_service_test.dart 的 _FakeRunner 同款：
/// 记录 `-C <dir>` 之后的子命令，按前缀匹配返回 ProcessResult。
class _FakeRunner {
  _FakeRunner(this.responses);
  final Map<String, ProcessResult> responses;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    final cIdx = arguments.indexOf('-C');
    if (cIdx < 0) return ProcessResult(0, 0, '/usr/bin/git\n', '');
    final cmd = arguments.sublist(cIdx + 2);
    calls.add(cmd);
    final key = cmd.join(' ');
    for (final e in responses.entries) {
      if (key.startsWith(e.key)) return e.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}

ProcessResult ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');

/// graphRows 每次还会探测 `git remote`（remotePrefixes 解析装饰用），
/// 这里只取（且仅一条）log 调用做断言。
List<String> _logCall(_FakeRunner fake) =>
    fake.calls.where((c) => c.first == 'log').single;

List<List<String>> _logCalls(_FakeRunner fake) =>
    fake.calls.where((c) => c.first == 'log').toList();

/// exit 128 + stderr：模拟坏引用仓库的 `git log --all` 失败。
ProcessResult _badRef([String detail = 'fatal: bad object refs/remotes/origin/xxx']) =>
    ProcessResult(0, 128, '', '$detail\n');

/// 一条可解析的 commit 行：`*` + \x1e + 七字段。
const String _oneRow = '*\x1eh1\x1f\x1fAnn\x1fann@x\x1f1700000000\x1f\x1fsubj\n';

void main() {
  setUp(GitService.debugResetExecutableCache);

  test('graphRows builds log args with paging and default --all', () async {
    final fake = _FakeRunner({'log': ok('')});
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await svc.graphRows('/repo', limit: 100, skip: 300);
    final cmd = _logCall(fake);
    expect(cmd.first, 'log');
    expect(cmd, containsAll(['--all', '--date-order', '--graph']));
    expect(cmd[cmd.indexOf('--max-count') + 1], '100');
    expect(cmd[cmd.indexOf('--skip') + 1], '300');
    // %x1e/%x1f 是 git 端的记录/字段转义，输出层还原为 \x1e/\x1f 供解析器切分。
    expect(
      cmd,
      contains('--pretty=format:%x1e%H\x1f%P\x1f%an\x1f%ae\x1f%at\x1f%d\x1f%s'),
    );
  });

  test('graphRows message search appends grep flags', () async {
    final fake = _FakeRunner({'log': ok('')});
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await svc.graphRows('/repo', query: 'fix bug', mode: GitSearchMode.message);
    final cmd = _logCall(fake);
    expect(cmd.contains('--grep=fix bug'), isTrue);
    expect(cmd, contains('-i'));
  });

  test('graphRows author search appends author flag', () async {
    final fake = _FakeRunner({'log': ok('')});
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await svc.graphRows('/repo', query: 'Alice', mode: GitSearchMode.author);
    expect(_logCall(fake).contains('--author=Alice'), isTrue);
  });

  test('graphRows hash mode adds no server-side filter (client filters)', () async {
    final fake = _FakeRunner({'log': ok('')});
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await svc.graphRows('/repo', query: 'abc12', mode: GitSearchMode.hash);
    expect(_logCall(fake).any((a) => a.startsWith('--grep=')), isFalse);
  });

  test('graphRows falls back to --branches --tags when --all hits bad ref', () async {
    final fake = _FakeRunner({
      'log --all': _badRef(),
      'log --branches --tags': ok(_oneRow),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    final rows = await svc.graphRows('/repo');
    final logs = _logCalls(fake);
    expect(logs, hasLength(2));
    expect(logs[0], contains('--all'));
    expect(logs[1], containsAllInOrder(['--branches', '--tags']));
    expect(logs[1].contains('--all'), isFalse);
    expect(rows.whereType<GitCommitRow>().map((r) => r.hash), ['h1']);
  });

  test('graphRows degrades --branches --tags to HEAD when both fail', () async {
    final fake = _FakeRunner({
      'log --all': _badRef('fatal: bad object refs/remotes/origin/a'),
      'log --branches --tags': _badRef('fatal: bad object refs/tags/t'),
      'log HEAD': ok(_oneRow),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    final rows = await svc.graphRows('/repo');
    final logs = _logCalls(fake);
    expect(logs, hasLength(3));
    expect(logs[2], containsAllInOrder(['HEAD', '--date-order']));
    expect(logs[2].contains('--all'), isFalse);
    expect(logs[2].contains('--branches'), isFalse);
    expect(rows.whereType<GitCommitRow>().map((r) => r.hash), ['h1']);
  });

  test('graphRows throws last GitException after exhausting fallbacks', () async {
    final fake = _FakeRunner({
      'log --all': _badRef('fatal: bad object refs/remotes/origin/a'),
      'log --branches --tags': _badRef('fatal: bad object refs/tags/t'),
      'log HEAD': _badRef('fatal: your current branch appears to be broken'),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await expectLater(
      svc.graphRows('/repo'),
      throwsA(
        isA<GitException>().having(
          (e) => e.message,
          'message',
          contains('your current branch appears to be broken'),
        ),
      ),
    );
    expect(_logCalls(fake), hasLength(3));
  });

  test('commitDetail parses show + diff-tree name-status', () async {
    const sep = '\x1e';
    const f = '\x1f';
    final fake = _FakeRunner({
      'show': ok('$sep h1${f}h0${f}Ann${f}ann@x${f}1700000000${f}subj'
          '${f}full body\n'),
      // diff-tree --name-status 的 R/C 行为 <status>\t<old>\t<new>。
      'diff-tree': ok('M\tsrc/a.dart\nR100\tsrc/old.dart\tsrc/b.dart\n'),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    final d = await svc.commitDetail('/repo', 'h1');
    expect(d.parents, ['h0']);
    expect(d.subject, 'subj');
    expect(d.body.trim(), 'full body');
    expect(d.files.map((e) => e.path), ['src/a.dart', 'src/b.dart']);
    expect(d.files[1].status, GitCommitFileStatus.renamed);
    expect(d.files[1].previousPath, 'src/old.dart');
  });

  test('commitFileDiff uses diff-tree --root for root commit', () async {
    final fake = _FakeRunner({});
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    await svc.commitFileDiff('/repo', hash: 'r1', path: 'a.dart');
    expect(
      fake.calls.single,
      containsAll(['diff-tree', '-p', '--root', '--no-commit-id']),
    );
  });

  test('branches merges local+remote with current flag', () async {
    final f = '\x1f';
    final fake = _FakeRunner({
      'for-each-ref refs/heads': ok('main${f}h1$f*\n'
          'dev${f}h2$f \n'),
      'for-each-ref refs/remotes': ok('origin/main${f}h1$f \n'),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    final list = await svc.branches('/repo');
    expect(list.length, 3);
    expect(list.firstWhere((b) => b.isCurrent).name, 'main');
    expect(list.firstWhere((b) => b.isRemote).name, 'origin/main');
  });

  test('stashList parses selectors; empty output yields empty list', () async {
    final f = '\x1f';
    final fake = _FakeRunner({
      'stash list': ok('stash@{0}${f}abc${f}WIP\nstash@{1}${f}def${f}tmp\n'),
    });
    final svc = GitHistoryService(runner: LocalGitCommandRunner(runner: fake.call));
    final list = await svc.stashList('/repo');
    expect(list.first.selector, 'stash@{0}');
    expect(list, hasLength(2));

    final emptyFake = _FakeRunner({'stash': ok('\n')});
    final svc2 =
        GitHistoryService(runner: LocalGitCommandRunner(runner: emptyFake.call));
    expect(await svc2.stashList('/repo'), isEmpty);
  });
}
