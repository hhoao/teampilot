import 'package:teampilot/services/git/git_command_runner.dart';

/// Instant git responses for widget tests — avoids pending [Process] timers.
class TestGitCommandRunner implements GitCommandRunner {
  const TestGitCommandRunner();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    if (args.contains('worktree') && args.contains('list')) {
      return const GitCommandResult(exitCode: 0, stdout: '', stderr: '');
    }
    return const GitCommandResult(
      exitCode: 128,
      stdout: '',
      stderr: 'not a git repository',
    );
  }
}
