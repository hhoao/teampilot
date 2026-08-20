import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Fake [ProcessRunner]: answers the locate probe with a git path, records the
/// git subcommand (the args after `-C <dir>`, ignoring leading global `-c` flags)
/// and returns mapped results by command prefix.
class _FakeRunner {
  _FakeRunner(this.responses);

  /// Keyed by the command after `-C <dir>` (prefix match). Missing keys → ok.
  final Map<String, ProcessResult> responses;

  /// The subcommand of each invocation, i.e. the args following `-C <dir>`.
  final List<List<String>> calls = [];

  /// Full argv of the last recorded invocation (incl. global flags).
  List<String>? lastArgs;
  Encoding? lastStdoutEncoding;

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    final cIdx = arguments.indexOf('-C');
    if (cIdx < 0) {
      // Locate probe (`which git` etc.).
      return ProcessResult(0, 0, '/usr/bin/git\n', '');
    }
    lastArgs = arguments;
    lastStdoutEncoding = stdoutEncoding;
    final cmd = arguments.sublist(cIdx + 2);
    calls.add(cmd);
    final key = cmd.join(' ');
    for (final entry in responses.entries) {
      if (key.startsWith(entry.key)) return entry.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}

const _inRepo = 'rev-parse --is-inside-work-tree';

ProcessResult _ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');

void main() {
  // The located git path is cached process-wide; reset it so each case's
  // scripted runner controls location independently.
  setUp(GitService.debugResetExecutableCache);

  group('GitService.status', () {
    test(
      'parses porcelain v2 into staged/unstaged/branch/ahead-behind',
      () async {
        const statusOut =
            '# branch.oid abcdef\n'
            '# branch.head main\n'
            '# branch.upstream origin/main\n'
            '# branch.ab +2 -1\n'
            '1 M. N... 100644 100644 100644 h h staged_mod.txt\n'
            '1 .M N... 100644 100644 100644 h h worktree_mod.txt\n'
            '1 MM N... 100644 100644 100644 h h both.txt\n'
            '2 R. N... 100644 100644 100644 h h R100 new_name.txt\told_name.txt\n'
            '? untracked.txt\n'
            'u UU N... 100644 100644 100644 100644 h h h conflict.txt\n';
        final runner = _FakeRunner({
          _inRepo: _ok('true\n'),
          'status': _ok(statusOut),
        });
        final service = GitService(
          runner: LocalGitCommandRunner(runner: runner.call),
        );

        final status = await service.status('/repo');

        expect(status.isRepository, isTrue);
        expect(status.branch, 'main');
        expect(status.upstream, 'origin/main');
        expect(status.ahead, 2);
        expect(status.behind, 1);
        expect(status.hasCommits, isTrue);

        // staged: staged_mod (M.), both (MM → X=M), renamed (R.)
        expect(
          status.staged.map((c) => c.path).toList(),
          containsAll(<String>['staged_mod.txt', 'both.txt', 'new_name.txt']),
        );
        final renamed = status.staged.firstWhere(
          (c) => c.path == 'new_name.txt',
        );
        expect(renamed.kind, GitChangeKind.renamed);
        expect(renamed.originalPath, 'old_name.txt');

        // unstaged: worktree_mod (.M), both (MM → Y=M), untracked, conflicted
        expect(
          status.unstaged.map((c) => c.path).toList(),
          containsAll(<String>[
            'worktree_mod.txt',
            'both.txt',
            'untracked.txt',
            'conflict.txt',
          ]),
        );
        expect(
          status.unstaged.firstWhere((c) => c.path == 'untracked.txt').kind,
          GitChangeKind.untracked,
        );
        expect(
          status.unstaged.firstWhere((c) => c.path == 'conflict.txt').kind,
          GitChangeKind.conflicted,
        );
      },
    );

    test('returns notARepository when outside a work tree', () async {
      final runner = _FakeRunner({_inRepo: ProcessResult(0, 128, '', 'fatal')});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      final status = await service.status('/tmp');

      expect(status.isRepository, isFalse);
    });

    test('reports hasCommits=false for an unborn branch', () async {
      const statusOut =
          '# branch.oid abcdef\n'
          '# branch.head (initial)\n'
          '1 M. N... 100644 100644 100644 h h staged_mod.txt\n';
      final runner = _FakeRunner({
        _inRepo: _ok('true\n'),
        'status': _ok(statusOut),
      });
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      final status = await service.status('/repo');

      expect(status.isRepository, isTrue);
      expect(status.hasCommits, isFalse);
    });
  });

  group('GitService mutations', () {
    test('commit issues the expected argv', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.commit('/repo', 'msg');

      expect(runner.calls, [['commit', '-m', 'msg']]);
    });

    test('commitSelected stages the paths then commits only those paths', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.commitSelected('/repo', 'feat: x', ['a.txt', 'b.dart']);

      expect(runner.calls, [
        ['add', '--', 'a.txt', 'b.dart'],
        ['commit', '-m', 'feat: x', '--', 'a.txt', 'b.dart'],
      ]);
    });

    test('commitAmend stages the paths then amends those paths', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.commitAmend('/repo', 'feat: x', ['a.txt', 'b.dart']);

      expect(runner.calls, [
        ['add', '--', 'a.txt', 'b.dart'],
        ['commit', '--amend', '-m', 'feat: x', '--', 'a.txt', 'b.dart'],
      ]);
    });

    test('commitAmend with no paths amends the message only', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.commitAmend('/repo', 'fix typo', const []);

      expect(runner.calls, [
        ['commit', '--amend', '-m', 'fix typo'],
      ]);
    });

    test('diffSelectedPaths diffs each path against HEAD and joins', () async {
      final runner = _FakeRunner({
        'diff HEAD --no-color -- a.txt': _ok('diff a\n'),
        'diff HEAD --no-color -- b.txt': _ok('diff b\n'),
      });
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      final out = await service.diffSelectedPaths('/repo', ['a.txt', 'b.txt']);

      expect(runner.calls, [
        ['diff', 'HEAD', '--no-color', '--', 'a.txt'],
        ['diff', 'HEAD', '--no-color', '--', 'b.txt'],
      ]);
      expect(out, 'diff a\n\ndiff b\n');
    });

    test('diffSelectedPaths skips empty per-path diffs', () async {
      final runner = _FakeRunner({
        'diff HEAD --no-color -- a.txt': _ok('diff a\n'),
        'diff HEAD --no-color -- b.txt': _ok(''),
      });
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      final out = await service.diffSelectedPaths('/repo', ['a.txt', 'b.txt']);

      expect(runner.calls, [
        ['diff', 'HEAD', '--no-color', '--', 'a.txt'],
        ['diff', 'HEAD', '--no-color', '--', 'b.txt'],
      ]);
      expect(out, 'diff a\n');
    });

    test('diffSelectedPaths truncates an oversized joined diff', () async {
      final runner = _FakeRunner({
        'diff HEAD --no-color -- big.txt': _ok('${'x' * 8000}\n'),
        'diff HEAD --no-color -- other.txt': _ok('${'y' * 8000}\n'),
      });
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      final out = await service.diffSelectedPaths('/repo', [
        'big.txt',
        'other.txt',
      ]);

      // ~16000 joined chars exceed the 12000 cap; the tail is trimmed and
      // annotated rather than handed to the prompt in full.
      expect(out.length, lessThan(12000 + 200));
      expect(out, contains('diff truncated'));
      expect(out, contains('more characters'));
    });

    test(
      'diffSelectedPaths skips a stale path whose diff throws',
      () async {
        final runner = _FakeRunner({
          'diff HEAD --no-color -- a.txt': _ok('diff a\n'),
          'diff --no-index --no-color /dev/null stale.txt': ProcessResult(
            0,
            128,
            '',
            'fatal: Pathspec stale.txt is in submodule',
          ),
        });
        final service = GitService(
          runner: LocalGitCommandRunner(runner: runner.call),
        );

        final out = await service.diffSelectedPaths(
          '/repo',
          ['a.txt', 'stale.txt'],
          untrackedPaths: {'stale.txt'},
        );

        // The stale (deleted) untracked path must not abort the whole prompt;
        // it is skipped and the healthy path's diff is still returned.
        expect(out, 'diff a\n');
      },
    );

    test(
      'diffSelectedPaths uses --no-index for paths in untrackedPaths',
      () async {
        final runner = _FakeRunner({
          'diff HEAD --no-color -- a.txt': _ok('diff a\n'),
          'diff --no-index --no-color /dev/null new.txt': _ok('diff new\n'),
        });
        final service = GitService(
          runner: LocalGitCommandRunner(runner: runner.call),
        );

        final out = await service.diffSelectedPaths(
          '/repo',
          ['a.txt', 'new.txt'],
          untrackedPaths: {'new.txt'},
        );

        // Tracked path diffs against HEAD; the untracked path goes through
        // --no-index against /dev/null instead of an (empty) HEAD diff.
        expect(runner.calls, [
          ['diff', 'HEAD', '--no-color', '--', 'a.txt'],
          ['diff', '--no-index', '--no-color', '/dev/null', 'new.txt'],
        ]);
        expect(out, 'diff a\n\ndiff new\n');
      },
    );

    test(
      'discard chooses restore for tracked and clean for untracked',
      () async {
        final runner = _FakeRunner({});
        final service = GitService(
          runner: LocalGitCommandRunner(runner: runner.call),
        );

        await service.discard(
          '/repo',
          const GitFileChange(
            path: 'a.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        );
        await service.discard(
          '/repo',
          const GitFileChange(
            path: 'b.txt',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        );

        expect(runner.calls[0], ['restore', '--', 'a.txt']);
        expect(runner.calls[1], ['clean', '-f', '--', 'b.txt']);
      },
    );

    test('discardAll issues `restore .`', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.discardAll('/repo');

      expect(runner.calls, [['restore', '.']]);
    });

    test('discardFolder issues `restore -- <folder>` for tracked changes', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.discardFolder(
        '/repo',
        'src/utils',
        changes: const [
          GitFileChange(
            path: 'src/utils/a.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        ],
      );

      expect(runner.calls, [['restore', '--', 'src/utils']]);
    });

    test('discardFolder issues `clean -ffd -- <folder>` for untracked', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.discardFolder(
        '/repo',
        'docs/new',
        changes: const [
          GitFileChange(
            path: 'docs/new/file.txt',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      );

      expect(runner.calls, [['clean', '-ffd', '--', 'docs/new']]);
    });

    test('discardFolder restores then cleans a mixed folder', () async {
      final runner = _FakeRunner({});
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      await service.discardFolder(
        '/repo',
        'src',
        changes: const [
          GitFileChange(
            path: 'src/a.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          GitFileChange(
            path: 'src/b.txt',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      );

      expect(runner.calls, [
        ['restore', '--', 'src'],
        ['clean', '-ffd', '--', 'src'],
      ]);
    });

    test('throws GitException with stderr on non-zero exit', () async {
      final runner = _FakeRunner({
        'push': ProcessResult(0, 1, '', 'remote rejected'),
      });
      final service = GitService(
        runner: LocalGitCommandRunner(runner: runner.call),
      );

      expect(
        () => service.push('/repo'),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            contains('remote rejected'),
          ),
        ),
      );
    });
  });

  group('text encoding', () {
    test(
      'decodes git output as lenient UTF-8 with quotePath disabled',
      () async {
        final runner = _FakeRunner({_inRepo: _ok('true\n'), 'status': _ok('')});
        final service = GitService(
          runner: LocalGitCommandRunner(runner: runner.call),
        );

        await service.status('/repo');

        // Global flags arrive before `-C`: no optional locks (so status never
        // rewrites the index), and non-ASCII paths literal rather than octal.
        expect(runner.lastArgs, isNotNull);
        final argv = runner.lastArgs!;
        final cIdx = argv.indexOf('-C');
        expect(argv.sublist(0, cIdx), [
          '--no-optional-locks',
          '-c',
          'core.quotePath=false',
        ]);

        // Output decoded as UTF-8 (git emits UTF-8, not the host ANSI codepage)…
        final enc = runner.lastStdoutEncoding;
        expect(enc, isNotNull);
        expect(enc!.name, 'utf-8');
        // …tolerating malformed bytes so a non-UTF-8 file's diff never throws.
        expect(enc.decode(const [0xff, 0xfe]), isNotEmpty);
      },
    );
  });

  test('branches parses one name per line', () async {
    final runner = _FakeRunner({'branch': _ok('main\ndev\nfeature/x\n')});
    final service = GitService(
      runner: LocalGitCommandRunner(runner: runner.call),
    );

    expect(await service.branches('/repo'), ['main', 'dev', 'feature/x']);
  });

  test('remoteBranches parses remote refs and omits HEAD', () async {
    final runner = _FakeRunner({
      'branch -r': _ok('origin/main\norigin/feature/x\norigin/HEAD\n'),
    });
    final service = GitService(
      runner: LocalGitCommandRunner(runner: runner.call),
    );

    expect(await service.remoteBranches('/repo'), [
      'origin/main',
      'origin/feature/x',
    ]);
  });
}
