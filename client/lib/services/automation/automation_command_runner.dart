import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/automation.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../run/process_run_executor.dart';
import '../run/run_target_resolver.dart';
import 'automation_tail_buffer.dart';

class AutomationCommandRequest {
  const AutomationCommandRequest({
    required this.workspaceId,
    required this.command,
    this.workingDirectoryPath,
    this.timeoutSeconds = 300,
    this.outputTailBytes = 4096,
  });

  final String workspaceId;
  final String command;
  final String? workingDirectoryPath;
  final int timeoutSeconds;
  final int outputTailBytes;
}

class AutomationCommandOutcome {
  const AutomationCommandOutcome({
    this.exitCode,
    this.stdoutTail = '',
    this.stderrTail = '',
    this.truncated = false,
    this.timedOut = false,
    this.durationMs = 0,
    this.error,
  });

  final int? exitCode;
  final String stdoutTail;
  final String stderrTail;
  final bool truncated;
  final bool timedOut;
  final int durationMs;
  final String? error;

  AutomationRunStatus get status {
    if (error != null) return AutomationRunStatus.dispatchFailed;
    if (timedOut) return AutomationRunStatus.timedOut;
    return exitCode == 0
        ? AutomationRunStatus.completed
        : AutomationRunStatus.failed;
  }
}

abstract interface class AutomationCommandRunner {
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request);
}

/// Runs an automation command on the workspace folder's runtime target
/// (local / WSL / SSH / Termux) through [ProcessRunExecutor].
class HostAutomationCommandRunner implements AutomationCommandRunner {
  HostAutomationCommandRunner({
    required Workspace? Function(String workspaceId) workspaceById,
    required RunTargetResolver resolver,
    required ProcessRunExecutor executor,
    bool Function()? isWindows,
    this.timeoutGrace = const Duration(seconds: 5),
  }) : _workspaceById = workspaceById,
       _resolver = resolver,
       _executor = executor,
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final Workspace? Function(String workspaceId) _workspaceById;
  final RunTargetResolver _resolver;
  final ProcessRunExecutor _executor;
  final bool Function() _isWindows;

  /// Extra time past `timeoutSeconds` allowed for start/stop to settle before
  /// the whole invocation is abandoned as timed out.
  final Duration timeoutGrace;

  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    final workspace = _workspaceById(request.workspaceId);
    if (workspace == null) {
      return const AutomationCommandOutcome(error: 'workspace_unavailable');
    }
    final folder = _folderFor(workspace, request.workingDirectoryPath);
    if (folder == null) {
      return const AutomationCommandOutcome(error: 'working_directory_invalid');
    }

    final stdout = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final stderr = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final watch = Stopwatch()..start();
    ProcessRunResult? started;
    final deadline = Completer<AutomationCommandOutcome>();
    final timer = Timer(
      Duration(seconds: request.timeoutSeconds) + timeoutGrace,
      () {
        if (deadline.isCompleted) return;
        // The runner invocation may be stuck in start() or stop(); do not wait
        // for it. Kill best-effort and report a terminal timeout so the
        // executor's serial queue always drains.
        final result = started;
        if (result != null) unawaited(_stopQuietly(result));
        deadline.complete(
          AutomationCommandOutcome(
            stdoutTail: stdout.text,
            stderrTail: stderr.text,
            truncated: stdout.truncated || stderr.truncated,
            timedOut: true,
            durationMs: watch.elapsedMilliseconds,
          ),
        );
      },
    );

    unawaited(() async {
      AutomationCommandOutcome outcome;
      try {
        outcome = await _execute(
          request,
          folder,
          stdout: stdout,
          stderr: stderr,
          watch: watch,
          onStarted: (result) {
            started = result;
            if (deadline.isCompleted) {
              // The overall deadline fired while `start()` was still in
              // flight; kill the process that appeared late.
              unawaited(_stopQuietly(result));
              return false;
            }
            return true;
          },
        );
      } on Object {
        outcome = AutomationCommandOutcome(
          stdoutTail: stdout.text,
          stderrTail: stderr.text,
          truncated: stdout.truncated || stderr.truncated,
          durationMs: watch.elapsedMilliseconds,
          error: 'runner_failed',
        );
      }
      if (!deadline.isCompleted) deadline.complete(outcome);
    }());

    return deadline.future.whenComplete(timer.cancel);
  }

  Future<AutomationCommandOutcome> _execute(
    AutomationCommandRequest request,
    WorkspaceFolder folder, {
    required AutomationTailBuffer stdout,
    required AutomationTailBuffer stderr,
    required Stopwatch watch,
    required bool Function(ProcessRunResult) onStarted,
  }) async {
    RuntimeKind? targetKind;
    final ProcessRunResult result;
    try {
      final plan = _resolver.resolve(
        owner: folder,
        cwd: request.workingDirectoryPath,
      );
      targetKind = plan.runtimeTarget.kind;
      // Never use ProcessRunExecutor's `shell:` flag for the command line:
      // `runInShell` passes the whole string as one argv element, so shell
      // syntax (`&&`, pipes) would be treated as an executable name. Always
      // invoke a shell explicitly with the line as a single argument.
      final invocation = _invocationFor(targetKind, request.command);
      result = await _executor.start(
        sessionId: 'automation:${request.workspaceId}',
        command: invocation.command,
        args: invocation.args,
        plan: plan,
        shell: false,
        onOutput: (output) {
          if (output.category == 'stderr') {
            stderr.add(output.data);
          } else {
            stdout.add(output.data);
          }
        },
      );
      if (!onStarted(result)) {
        // The whole invocation was abandoned while spawning; the process has
        // already been killed and the deadline has produced the outcome.
        return AutomationCommandOutcome(
          stdoutTail: stdout.text,
          stderrTail: stderr.text,
          truncated: stdout.truncated || stderr.truncated,
          timedOut: true,
          durationMs: watch.elapsedMilliseconds,
        );
      }
    } on Object {
      final kind = targetKind;
      return AutomationCommandOutcome(
        durationMs: watch.elapsedMilliseconds,
        error: kind != null && _unreachable(kind)
            ? 'target_unreachable'
            : 'spawn_failed',
      );
    }

    final exit = await _awaitExit(result, request.timeoutSeconds, targetKind);
    if (exit.error != null) {
      unawaited(_stopQuietly(result));
      watch.stop();
      return AutomationCommandOutcome(
        stdoutTail: stdout.text,
        stderrTail: stderr.text,
        truncated: stdout.truncated || stderr.truncated,
        durationMs: watch.elapsedMilliseconds,
        error: exit.error,
      );
    }
    if (exit.exitCode == null) {
      await _stopQuietly(result);
    } else {
      await _awaitOutputClosed(result);
    }
    watch.stop();

    return AutomationCommandOutcome(
      exitCode: exit.exitCode,
      stdoutTail: stdout.text,
      stderrTail: stderr.text,
      truncated: stdout.truncated || stderr.truncated,
      timedOut: exit.exitCode == null,
      durationMs: watch.elapsedMilliseconds,
    );
  }

  /// Shell invocation for one command line on [kind].
  ///
  /// Local POSIX and WSL get `sh -c`; Windows local gets `cmd.exe /c`. SSH and
  /// Termux are wrapped by [ProcessRunExecutor] into a remote shell string, so
  /// `sh -c` keeps the line intact as a single argument.
  ({String command, List<String> args}) _invocationFor(
    RuntimeKind kind,
    String line,
  ) {
    if (kind == RuntimeKind.wsl) {
      // `ProcessRunExecutor` passes these args through to `wsl.exe` verbatim
      // (no extra quoting), so the line stays a single `sh -c` argument.
      return (command: 'sh', args: ['-c', line]);
    }
    if (usesSshTransport(kind)) {
      return (command: 'sh', args: ['-c', line]);
    }
    if (_isWindows()) {
      return (command: 'cmd.exe', args: ['/c', line]);
    }
    return (command: 'sh', args: ['-c', line]);
  }

  /// Returns the exit code, an error marker, or neither when timed out.
  Future<({int? exitCode, String? error})> _awaitExit(
    ProcessRunResult result,
    int timeoutSeconds,
    RuntimeKind kind,
  ) {
    final completer = Completer<({int? exitCode, String? error})>();
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        completer.complete((exitCode: null, error: null));
      }
    });
    unawaited(
      result.exitCode.then(
        (code) {
          if (!completer.isCompleted) {
            completer.complete((exitCode: code, error: null));
          }
        },
        onError: (Object _, StackTrace __) {
          if (!completer.isCompleted) {
            completer.complete((
              exitCode: null,
              error: _unreachable(kind)
                  ? 'target_unreachable'
                  : 'spawn_failed',
            ));
          }
        },
      ),
    );
    return completer.future.whenComplete(timer.cancel);
  }

  /// Waits for trailing output, bounded so a stuck stream cannot hang the run.
  Future<void> _awaitOutputClosed(ProcessRunResult result) {
    final completer = Completer<void>();
    final timer = Timer(const Duration(seconds: 2), () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(
      result.outputClosed.then(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object _, StackTrace __) {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    return completer.future.whenComplete(timer.cancel);
  }

  /// Best-effort stop bounded so a hung cancel cannot block the caller.
  Future<void> _stopQuietly(ProcessRunResult result) async {
    try {
      await result.stop().timeout(const Duration(seconds: 2));
    } on Object {
      // The process is already gone or the transport is broken.
    }
  }

  bool _unreachable(RuntimeKind kind) => usesSshTransport(kind);

  WorkspaceFolder? _folderFor(Workspace workspace, String? rawPath) {
    final raw = rawPath?.trim() ?? '';
    if (raw.isEmpty) {
      return workspace.folders.isEmpty ? null : workspace.folders.first;
    }
    // Choose the most specific match: with `/repo` and `/repo/svc` on
    // different targets, `/repo/svc` must resolve to its own folder.
    WorkspaceFolder? best;
    var bestLength = -1;
    for (final folder in workspace.folders) {
      if (!_isUnder(raw, folder.path)) continue;
      final length = folder.path.trim().length;
      if (length > bestLength) {
        best = folder;
        bestLength = length;
      }
    }
    return best;
  }

  bool _isUnder(String child, String parent) {
    final style = Platform.isWindows && !parent.startsWith('/')
        ? p.Style.windows
        : p.Style.posix;
    final ctx = p.Context(style: style);
    final normalizedChild = ctx.normalize(child);
    final normalizedParent = ctx.normalize(parent);
    if (normalizedChild == normalizedParent) return true;
    final prefix = normalizedParent.endsWith(ctx.separator)
        ? normalizedParent
        : '$normalizedParent${ctx.separator}';
    return normalizedChild.startsWith(prefix);
  }
}
