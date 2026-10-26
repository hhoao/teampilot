import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../cli/registry/capabilities/session_usage_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'usage_cursor_store.dart';
import 'usage_scan_target_provider.dart';
import 'usage_store.dart';

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
  });

  final int targetsScanned;
  final int sourcesScanned;
  final int inserted;
  final int updated;
  final int skipped;
  final List<UsageSyncError> errors;
}

/// One-shot scanner. No timer and no cubit in this slice.
class SessionUsageSyncService {
  SessionUsageSyncService({
    required UsageScanTargetProvider targets,
    required UsageStore store,
    required UsageCursorStore cursors,
    required CliToolRegistry registry,
  }) : _targets = targets,
       _store = store,
       _cursors = cursors,
       _registry = registry;

  final UsageScanTargetProvider _targets;
  final UsageStore _store;
  final UsageCursorStore _cursors;
  final CliToolRegistry _registry;

  /// Process-wide: a plane swap can briefly keep an old service alive.
  static final Lock _syncLock = Lock();

  Future<UsageSyncResult> syncAll() => _syncLock.synchronized(_syncAll);

  Future<UsageSyncResult> _syncAll() async {
    late final List<UsageScanContext> targets;
    try {
      targets = await _targets.targets();
    } on Object catch (error) {
      return UsageSyncResult(
        errors: [
          UsageSyncError(sourceId: '*', message: '$error'),
        ],
      );
    }

    final errors = <UsageSyncError>[];
    final seenSources = <String>{};
    var sourcesScanned = 0;
    var inserted = 0;
    var updated = 0;
    var skipped = 0;

    for (final ctx in targets) {
      final capability = _registry.capability<SessionUsageCapability>(ctx.cli);
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
        if (!seenSources.add(source.id)) continue;
        sourcesScanned++;
        try {
          final cursor = await _cursors.read(source.id);
          final scan = await capability.scanUsageSource(
            ctx: ctx,
            source: source,
            cursor: cursor,
          );
          final appended = await _store.upsert(scan.events);
          await _cursors.save(source.id, scan.nextCursor);
          inserted += appended.inserted;
          updated += appended.updated;
          skipped += appended.skipped;
        } on Object catch (error) {
          errors.add(
            UsageSyncError(sourceId: source.id, message: '$error'),
          );
        }
      }
    }

    return UsageSyncResult(
      targetsScanned: targets.length,
      sourcesScanned: sourcesScanned,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }
}
