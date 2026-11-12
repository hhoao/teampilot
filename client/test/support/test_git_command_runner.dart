import 'package:teampilot/services/git/git_command_runner.dart';

/// Instant git responses for widget tests — avoids pending [Process] timers.
class TestGitCommandRunner implements GitCommandRunner {
  const TestGitCommandRunner();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    if (args.contains('worktree') && args.contains('list')) {
      return const GitCommandResult(exitCode: 0, stdout: '', stderr: '');
    }
    return const GitCommandResult(
      exitCode: 128,
      stdout: '',
      stderr: 'not a git repository',
    );
  }

  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async => const GitRawResult(
    exitCode: 128,
    stdout: [],
    stderr: 'not a git repository',
  );

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async =>
      throw UnsupportedError('runToFile is not supported by test runner');

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async => const GitCommandResult(
    exitCode: 128,
    stdout: '',
    stderr: 'not a git repository',
  );

  @override
  Future<GitCapability> probe() async => GitCapability.unavailable;
}
