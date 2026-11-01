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
  }) : _workspaceById = workspaceById,
       _resolver = resolver,
       _executor = executor;

  final Workspace? Function(String workspaceId) _workspaceById;
  final RunTargetResolver _resolver;
  final ProcessRunExecutor _executor;

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

    final plan = _resolver.resolve(
      owner: folder,
      cwd: request.workingDirectoryPath,
    );
    final stdout = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final stderr = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final watch = Stopwatch()..start();

    final ProcessRunResult result;
    try {
      result = await _executor.start(
        sessionId: 'automation:${request.workspaceId}',
        command: request.command,
        args: const [],
        plan: plan,
        shell: true,
        onOutput: (output) {
          if (output.category == 'stderr') {
            stderr.add(output.data);
          } else {
            stdout.add(output.data);
          }
        },
      );
    } on Object {
      return AutomationCommandOutcome(
        durationMs: watch.elapsedMilliseconds,
        error: _unreachable(plan.runtimeTarget.kind)
            ? 'target_unreachable'
            : 'spawn_failed',
      );
    }

    final exitCode = await _awaitExit(result, request.timeoutSeconds);
    if (exitCode == null) {
      await result.stop();
    }
    watch.stop();

    return AutomationCommandOutcome(
      exitCode: exitCode,
      stdoutTail: stdout.text,
      stderrTail: stderr.text,
      truncated: stdout.truncated || stderr.truncated,
      timedOut: exitCode == null,
      durationMs: watch.elapsedMilliseconds,
    );
  }

  /// Returns the exit code, or `null` when the timeout fires first.
  Future<int?> _awaitExit(ProcessRunResult result, int timeoutSeconds) {
    final completer = Completer<int?>();
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    unawaited(
      result.exitCode.then((code) {
        if (!completer.isCompleted) completer.complete(code);
      }),
    );
    return completer.future.whenComplete(timer.cancel);
  }

  bool _unreachable(RuntimeKind kind) =>
      kind == RuntimeKind.ssh || kind == RuntimeKind.termux;

  WorkspaceFolder? _folderFor(Workspace workspace, String? rawPath) {
    final raw = rawPath?.trim() ?? '';
    if (raw.isEmpty) {
      return workspace.folders.isEmpty ? null : workspace.folders.first;
    }
    for (final folder in workspace.folders) {
      if (_isUnder(raw, folder.path)) return folder;
    }
    return null;
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
