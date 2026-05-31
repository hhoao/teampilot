import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_tool_locator.dart';
import 'package:teampilot/services/skill/skill_repo_git_service.dart';

void main() {
  group('SkillRepoGitService', () {
    test('resolveRemoteSha parses ls-remote line', () async {
      final svc = SkillRepoGitService(
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
          expect(executable, '/usr/bin/git');
          expect(arguments, [
            'ls-remote',
            'https://github.com/anthropics/skills.git',
            'refs/heads/main',
          ]);
          return ProcessResult(
            0,
            0,
            'abc123deadbeef\trefs/heads/main\n',
            '',
          );
        },
        gitLocator: _FixedGitLocator('/usr/bin/git'),
      );

      final sha = await svc.resolveRemoteSha('anthropics', 'skills', 'main');
      expect(sha, 'abc123deadbeef');
    });

    test('resolveRemoteShaWithFallback tries main after missing branch', () async {
      var calls = 0;
      final svc = SkillRepoGitService(
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
          calls++;
          final ref = arguments.last;
          if (ref.endsWith('/develop')) {
            return ProcessResult(0, 0, '', '');
          }
          return ProcessResult(
            0,
            0,
            'sha-main\trefs/heads/main\n',
            '',
          );
        },
        gitLocator: _FixedGitLocator('/usr/bin/git'),
      );

      final resolved = await svc.resolveRemoteShaWithFallback(
        'anthropics',
        'skills',
        'develop',
      );
      expect(resolved?.branch, 'main');
      expect(resolved?.sha, 'sha-main');
      expect(calls, greaterThanOrEqualTo(2));
    });
  });
}

class _FixedGitLocator extends CliToolLocator {
  const _FixedGitLocator(this.path) : super('git');
  final String path;

  @override
  Future<String?> locate({
    ProcessRunner runner = cliToolDefaultProcessRun,
    bool? isWindowsOverride,
  }) async =>
      path;
}
