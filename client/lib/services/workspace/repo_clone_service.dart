import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../../utils/logging/logger.dart';
import '../host/host_one_shot_runner.dart';
import '../io/filesystem.dart';
import '../run/process_run_executor.dart';
import '../run/run_target_resolver.dart';
import '../storage/runtime_context.dart';
import '../storage/work_target_canonicalizer.dart';

/// A single `git clone` invocation on a run target.
@immutable
class RepoCloneRequest {
  const RepoCloneRequest({
    required this.url,
    required this.targetId,
    required this.parentDir,
    required this.dirName,
  });

  /// Validated https://, git@, git://, ssh:// URL (see [repoCloneUrlLooksValid]).
  final String url;

  /// Canonical id (`local` / `wsl:<distro>` / `ssh:<profile>`).
  final String targetId;

  /// Absolute path on the target machine.
  final String parentDir;

  /// Clone folder name under [parentDir].
  final String dirName;
}

/// Streaming progress snapshot parsed from `git clone --progress` output.
@immutable
class RepoCloneProgress {
  const RepoCloneProgress({this.fraction, this.subtitle});

  /// Null = indeterminate.
  final double? fraction;

  /// Latest git progress line.
  final String? subtitle;
}

enum RepoCloneOutcome { succeeded, failed, cancelled }

@immutable
class RepoCloneResult {
  const RepoCloneResult({
    required this.outcome,
    required this.destPath,
    this.errorDetail,
  });

  /// Absolute path on the target.
  final String destPath;

  final RepoCloneOutcome outcome;

  /// Git stderr tail on failure, or a stable marker
  /// (`dest-exists` / `git-missing`).
  final String? errorDetail;
}

/// Host-plane seam: git discovery + target-machine filesystem access.
abstract interface class RepoCloneHostRunner {
  /// Verify git exists: `git --version`.
  Future<HostRunResult> checkGit(RepoCloneRequest request);

  /// Target-machine filesystem for destination checks + partial cleanup.
  Future<Filesystem> filesystemFor(String targetId);
}

/// [RepoCloneHostRunner] over the injected [RuntimeContext] resolver.
///
/// Selects [LocalHostOneShotRunner] / [WslHostOneShotRunner] /
/// [RemoteHostOneShotRunner] from the resolved context's backend mode the
/// same way `hostOneShotRunnerForContext` does. The context resolver is
/// injected (DI wiring, Task 4) — this file never touches `AppStorage`.
///
/// Targets are resolved through the injected [RunTargetResolver] (the same
/// home-aware resolution the clone's run plan uses), so `checkGit` /
/// `filesystemFor` always act on the machine the clone actually spawns on —
/// a bare `local` id on an SSH-home device resolves to SSH here too.
class DefaultRepoCloneHostRunner implements RepoCloneHostRunner {
  DefaultRepoCloneHostRunner({
    Future<RuntimeContext> Function(RuntimeTarget target)? contextFor,
    RunTargetResolver? resolver,
  }) : _contextFor = contextFor,
       _resolver = resolver;

  final Future<RuntimeContext> Function(RuntimeTarget target)? _contextFor;
  final RunTargetResolver? _resolver;

  /// Home-aware target resolution matching `RunTargetResolver.resolve`.
  /// The folder path is irrelevant to target resolution; `filesystemFor`
  /// only carries a target id.
  RuntimeTarget _resolveTarget(String targetId) {
    final resolver = _resolver;
    if (resolver != null) {
      return resolver.targetFor(WorkspaceFolder(path: '', targetId: targetId));
    }
    return WorkTargetCanonicalizer.fromId(targetId);
  }

  Future<RuntimeContext> _context(String targetId) async {
    final contextFor = _contextFor;
    if (contextFor == null) {
      throw StateError(
        'DefaultRepoCloneHostRunner requires a RuntimeContext resolver',
      );
    }
    return contextFor(_resolveTarget(targetId));
  }

  @override
  Future<HostRunResult> checkGit(RepoCloneRequest request) async {
    final ctx = await _context(request.targetId);
    final runner = _runnerForContext(ctx);
    return runner.run(
      HostRunRequest(
        executable: 'git',
        arguments: const ['--version'],
        workingDirectory: request.parentDir,
      ),
    );
  }

  @override
  Future<Filesystem> filesystemFor(String targetId) async {
    final ctx = await _context(targetId);
    return ctx.filesystem;
  }

  HostOneShotRunner _runnerForContext(RuntimeContext ctx) {
    return switch (ctx.mode) {
      StorageBackendMode.ssh => RemoteHostOneShotRunner(
        execShell: ctx.remoteFileStore!.execShell,
      ),
      StorageBackendMode.wsl => WslHostOneShotRunner(
        distro: ctx.target.wslDistro,
      ),
      StorageBackendMode.native => LocalHostOneShotRunner(),
    };
  }
}

/// Stable failure markers surfaced through [RepoCloneResult.errorDetail].
const String _kDestExistsMarker = 'dest-exists';
const String _kGitMissingMarker = 'git-missing';
const int _errorTailLines = 40;
const String _repoCloneSessionId = 'repo-clone';

/// Seam used by [RepoCloneCubit] (and tests): one `git clone` invocation.
///
/// Extracted so the cubit depends on the clone contract, not the concrete
/// [RepoCloneService]; fakes in tests implement this interface.
abstract interface class RepoCloneGateway {
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  });
}

/// Clones a repository URL into a folder on a local / WSL / SSH run target.
class RepoCloneService implements RepoCloneGateway {
  RepoCloneService({
    RunTargetResolver? resolver,
    ProcessRunExecutor? executor,
    RepoCloneHostRunner? hostRunner,
  }) : _resolver = resolver ?? RunTargetResolver(),
       _executor = executor ?? ProcessRunExecutor(),
       _hostRunner = hostRunner ?? DefaultRepoCloneHostRunner();

  final RunTargetResolver _resolver;
  final ProcessRunExecutor _executor;
  final RepoCloneHostRunner _hostRunner;

  /// Exposed for cubit-level best-effort cleanup of partial clones
  /// ([RepoCloneHostRunner.filesystemFor]).
  RepoCloneHostRunner get hostRunner => _hostRunner;

  @override
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final owner = WorkspaceFolder(
      path: request.parentDir,
      targetId: request.targetId,
    );
    final plan = _resolver.resolve(owner: owner);
    final fs = await _hostRunner.filesystemFor(request.targetId);
    final destPath = fs.pathContext.join(request.parentDir, request.dirName);
    appLogger.d(
      '[RepoClone] start url=${request.url} target=${request.targetId} '
      'dest=$destPath',
    );

    if (isCancelled()) {
      return _finishCancelled(destPath, fs, mayRemovePartial: false);
    }

    // Destination pre-check: anything already occupying the name is an error.
    // `destWasAbsent` records that the clone owns this name — only then is
    // failure-path cleanup allowed to remove it (see I-1: a raced
    // "destination path already exists" failure must never delete a
    // pre-existing user directory).
    var destWasAbsent = false;
    try {
      final stat = await fs.stat(destPath);
      if (stat.exists) {
        appLogger.d('[RepoClone] destination exists: $destPath');
        return RepoCloneResult(
          outcome: RepoCloneOutcome.failed,
          destPath: destPath,
          errorDetail: _kDestExistsMarker,
        );
      }
      destWasAbsent = stat.kind == FsEntityKind.notFound;
    } catch (error) {
      appLogger.d('[RepoClone] stat failed for $destPath: $error');
    }

    // Git discovery on the target machine.
    final gitCheck = await _hostRunner.checkGit(request);
    if (gitCheck.exitCode != 0) {
      appLogger.d(
        '[RepoClone] git check failed (exit ${gitCheck.exitCode}): '
        '${gitCheck.stderr.trim()}',
      );
      return RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: destPath,
        errorDetail: _kGitMissingMarker,
      );
    }

    final errorTail = <String>[];
    var lastFraction = 0.0;
    var hasFraction = false;
    var cancelRequested = false;
    var stopping = false;
    Future<void>? stopFuture;
    ProcessRunResult? runRef;

    void handleOutput(ProcessRunOutput output) {
      if (isCancelled()) {
        cancelRequested = true;
      }
      // Progress lives on stderr; stdout is never a git progress stream.
      final isStderr = output.category == 'stderr';
      for (final line in output.data.split(RegExp(r'[\r\n]'))) {
        if (line.isEmpty) continue;
        if (isStderr) {
          errorTail.add(line);
          if (errorTail.length > _errorTailLines) {
            errorTail.removeAt(0);
          }
        }
        final parsed = isStderr ? repoCloneParseFraction(line) : null;
        if (parsed != null) {
          lastFraction = parsed;
          hasFraction = true;
        }
        if (!isStderr) continue;
        onProgress(
          RepoCloneProgress(
            fraction: parsed ?? (hasFraction ? lastFraction : null),
            subtitle: line,
          ),
        );
      }
    }

    Future<void> requestStop() {
      if (!stopping) {
        stopping = true;
        final run = runRef;
        stopFuture = run?.stop();
      }
      return stopFuture ?? Future<void>.value();
    }

    // Cleanup is only safe when the pre-check proved the destination was
    // absent AND git did not report a raced "already exists" failure —
    // otherwise removeRecursive could destroy a pre-existing user directory.
    var mayRemovePartial = destWasAbsent;

    Future<RepoCloneResult> finishCancelled() {
      appLogger.d('[RepoClone] cancelled; stopping git process');
      return requestStop().then((_) async {
        final exitCode = await runRef!.exitCode;
        appLogger.d('[RepoClone] cancelled clone exited with $exitCode');
        // The clone may have finished successfully before cancellation was
        // observed — report success and keep the result on disk.
        if (exitCode == 0) {
          return RepoCloneResult(
            outcome: RepoCloneOutcome.succeeded,
            destPath: destPath,
          );
        }
        return _finishCancelled(
          destPath,
          fs,
          mayRemovePartial: mayRemovePartial,
        );
      });
    }

    final ProcessRunResult run;
    try {
      run = await _executor.start(
        sessionId: _repoCloneSessionId,
        command: 'git',
        args: ['clone', '--progress', '--', request.url, request.dirName],
        plan: plan,
        onOutput: handleOutput,
      );
    } catch (error) {
      // Spawn failures (e.g. missing SSH profile) surface as a failed
      // outcome rather than an uncaught StateError out of clone().
      appLogger.d('[RepoClone] failed to spawn git: $error');
      return RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: destPath,
        errorDetail: error.toString(),
      );
    }
    runRef = run;

    // Let buffered stdout/stderr events flush so progress + cancellation
    // flips are observed before deciding how to await the process.
    await _pumpEventLoop();

    if (cancelRequested || isCancelled()) {
      return finishCancelled();
    }

    final exitCode = await run.exitCode;
    // Flush trailing output events before judging the outcome.
    await _pumpEventLoop();
    if (cancelRequested || isCancelled()) {
      return finishCancelled();
    }

    if (exitCode == 0) {
      appLogger.d('[RepoClone] succeeded: $destPath');
      return RepoCloneResult(
        outcome: RepoCloneOutcome.succeeded,
        destPath: destPath,
      );
    }

    appLogger.d('[RepoClone] clone failed with exit $exitCode');
    // Belt and braces (I-1): never clean up when git itself reported a raced
    // "destination path already exists" failure.
    if (errorTail.join('\n').contains('already exists')) {
      mayRemovePartial = false;
    }
    if (mayRemovePartial) {
      await _cleanupPartial(fs, destPath);
    } else {
      appLogger.d(
        '[RepoClone] skipping partial cleanup for $destPath '
        '(destination was not confirmed absent or already-exists failure)',
      );
    }
    return RepoCloneResult(
      outcome: RepoCloneOutcome.failed,
      destPath: destPath,
      errorDetail: errorTail.isEmpty
          ? 'git exit $exitCode'
          : errorTail.join('\n'),
    );
  }

  Future<RepoCloneResult> _finishCancelled(
    String destPath,
    Filesystem fs, {
    required bool mayRemovePartial,
  }) async {
    if (mayRemovePartial) {
      await _cleanupPartial(fs, destPath);
    }
    return RepoCloneResult(
      outcome: RepoCloneOutcome.cancelled,
      destPath: destPath,
    );
  }

  /// Yields a macrotask turn so IO-delivered stream chunks (timer/event
  /// queue) flush before the next decision reads progress/cancel state.
  Future<void> _pumpEventLoop() async {
    await Future<void>.delayed(Duration.zero);
  }

  /// Best-effort removal of a partially cloned directory (git may leave one
  /// behind after a kill).
  Future<void> _cleanupPartial(Filesystem fs, String destPath) async {
    try {
      final stat = await fs.stat(destPath);
      if (stat.exists) {
        await fs.removeRecursive(destPath);
        appLogger.d('[RepoClone] removed partial clone at $destPath');
      }
    } catch (error) {
      appLogger.d('[RepoClone] partial cleanup failed for $destPath: $error');
    }
  }
}

/// 'repo' from .../repo.git; scp-style `git@host:owner/repo.git` supported.
/// Empty string when no usable name remains.
String repoCloneDirNameFromUrl(String url) {
  var candidate = url.trim();
  while (candidate.endsWith('/')) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  // scp-style: the path begins after the last ':' (no scheme separator).
  final colon = candidate.lastIndexOf(':');
  if (colon >= 0 && candidate.indexOf('://') != colon - 1) {
    candidate = candidate.substring(colon + 1);
  }
  final slash = candidate.lastIndexOf('/');
  if (slash >= 0 && slash < candidate.length - 1) {
    candidate = candidate.substring(slash + 1);
  }
  if (candidate.toLowerCase().endsWith('.git')) {
    candidate = candidate.substring(0, candidate.length - 4);
  }
  candidate = candidate.trim();
  if (candidate.isEmpty) return '';
  if (!RegExp(r'\w').hasMatch(candidate)) return '';
  return candidate;
}

/// True when the trimmed url starts with a known git scheme AND yields a
/// non-empty directory name.
bool repoCloneUrlLooksValid(String url) {
  final trimmed = url.trim();
  const schemes = ['https://', 'http://', 'git@', 'git://', 'ssh://'];
  final hasScheme = schemes.any(trimmed.startsWith);
  if (!hasScheme) return false;
  return repoCloneDirNameFromUrl(trimmed).isNotEmpty;
}

final RegExp _progressFraction = RegExp(
  r'^(Receiving objects|Resolving deltas|Compressing objects|Counting objects)'
  r':[^\d]*(\d+)%',
);

/// 'Receiving objects:  45% ...' → 0.45; null when the line carries no
/// percentage.
double? repoCloneParseFraction(String line) {
  final match = _progressFraction.firstMatch(line.trim());
  if (match == null) return null;
  final percent = int.tryParse(match.group(2)!);
  if (percent == null) return null;
  return (percent / 100).clamp(0.0, 1.0);
}
