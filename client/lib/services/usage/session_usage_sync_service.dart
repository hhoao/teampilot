import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../cli/registry/capabilities/session_usage_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'usage_cursor_store.dart';
import 'usage_scan_target_provider.dart';
import 'usage_store.dart';
import 'usage_sync_control.dart';

@immutable
class UsageSyncError {
  const UsageSyncError({required this.sourceId, required this.message});

  final String sourceId;
  final String message;
}

@immutable
class UsageSyncResult {
  const UsageSyncResult({
    this.targetsScanned = 0,
    this.sourcesScanned = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
    this.cancelled = false,
    this.prunedCursors = 0,
  });

  final int targetsScanned;
  final int sourcesScanned;
  final int inserted;
  final int updated;
  final int skipped;
  final List<UsageSyncError> errors;
  final bool cancelled;
  final int prunedCursors;
}

final class UsageSyncHandle {
  UsageSyncHandle({
    required this.done,
    required this.progress,
    required void Function() cancel,
  }) : _cancel = cancel;

  final Future<UsageSyncResult> done;
  final Stream<UsageSyncProgress> progress;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// One-shot scanner with optional progress, cancellation, timeout, and
/// bounded target concurrency.
class SessionUsageSyncService {
  SessionUsageSyncService({
    required UsageScanTargetProvider targets,
    required UsageStore store,
    required UsageCursorStore cursors,
    required CliToolRegistry registry,
    this.sourceTimeout = const Duration(seconds: 30),
    this.maxConcurrentTargets = 4,
  }) : _targets = targets,
       _store = store,
       _cursors = cursors,
       _registry = registry;

  final UsageScanTargetProvider _targets;
  final UsageStore _store;
  final UsageCursorStore _cursors;
  final CliToolRegistry _registry;
  final Duration sourceTimeout;
  final int maxConcurrentTargets;

  /// Process-wide: a plane swap can briefly keep an old service alive.
  static final Lock _syncLock = Lock();

  Future<UsageSyncResult> syncAll({
    UsageSyncControl? control,
    void Function(UsageSyncProgress)? onProgress,
  }) {
    final token = control ?? UsageSyncControl();
    return _syncLock.synchronized(
      () => _syncAll(control: token, onProgress: onProgress),
    );
  }

  Future<UsageSyncResult> _syncAll({
    required UsageSyncControl control,
    void Function(UsageSyncProgress)? onProgress,
  }) async {
    final errors = <UsageSyncError>[];
    final seenSources = <String>{};
    var targetsTotal = 0;
    var targetsDone = 0;
    var sourcesDone = 0;
    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    void report({String? currentSourceId}) {
      onProgress?.call(
        UsageSyncProgress(
          targetsTotal: targetsTotal,
          targetsDone: targetsDone,
          sourcesDone: sourcesDone,
          inserted: inserted,
          updated: updated,
          skipped: skipped,
          errors: errors.length,
          currentSourceId: currentSourceId,
          isCancelled: control.isCancelled,
        ),
      );
    }

    report();

    late final List<UsageScanContext> targets;
    try {
      control.throwIfCancelled();
      targets = await _targets.targets();
    } on UsageSyncCancelled {
      return const UsageSyncResult(cancelled: true);
    } on Object catch (error) {
      return UsageSyncResult(
        errors: [UsageSyncError(sourceId: '*', message: '$error')],
      );
    }

    targetsTotal = targets.length;
    report();

    final workerCount = math.min(
      math.max(1, maxConcurrentTargets),
      math.max(1, targets.length),
    );
    var nextTarget = 0;

    Future<void> worker() async {
      while (true) {
        if (control.isCancelled) return;
        final index = nextTarget++;
        if (index >= targets.length) return;
        final ctx = targets[index];
        try {
          control.throwIfCancelled();
          final capability = _registry.capability<SessionUsageCapability>(
            ctx.cli,
          );
          if (capability == null) continue;

          late final List<SessionUsageSource> sources;
          try {
            sources = await capability.discoverUsageSources(ctx);
          } on Object catch (error) {
            errors.add(
              UsageSyncError(
                sourceId: '${ctx.sessionId}/${ctx.memberId}',
                message: '$error',
              ),
            );
            continue;
          }

          for (final source in sources) {
            if (control.isCancelled) return;
            if (!seenSources.add(source.id)) continue;
            sourcesDone++;
            try {
              final cursor = await _cursors
                  .read(source.id)
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              final scan = await capability
                  .scanUsageSource(ctx: ctx, source: source, cursor: cursor)
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              final appended = await _store
                  .upsert(scan.events)
                  .timeout(sourceTimeout);
              control.throwIfCancelled();
              await _cursors
                  .save(source.id, scan.nextCursor)
                  .timeout(sourceTimeout);
              inserted += appended.inserted;
              updated += appended.updated;
              skipped += appended.skipped;
            } on UsageSyncCancelled {
              report(currentSourceId: source.id);
              return;
            } on TimeoutException {
              errors.add(
                UsageSyncError(
                  sourceId: source.id,
                  message: 'timed out after ${sourceTimeout.inMilliseconds}ms',
                ),
              );
            } on Object catch (error) {
              errors.add(
                UsageSyncError(sourceId: source.id, message: '$error'),
              );
            }
            report(currentSourceId: source.id);
          }
        } on UsageSyncCancelled {
          return;
        } finally {
          targetsDone++;
          report();
        }
      }
    }

    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    var prunedCursors = 0;
    if (!control.isCancelled && errors.isEmpty && targets.isNotEmpty) {
      try {
        prunedCursors = await _cursors.prune(seenSources);
      } on Object catch (error) {
        errors.add(
          UsageSyncError(sourceId: '*', message: 'prune failed: $error'),
        );
      }
    }

    report();

    return UsageSyncResult(
      targetsScanned: targetsDone,
      sourcesScanned: sourcesDone,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: List.unmodifiable(errors),
      cancelled: control.isCancelled,
      prunedCursors: prunedCursors,
    );
  }
}
