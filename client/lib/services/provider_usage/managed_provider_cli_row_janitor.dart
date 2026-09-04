import 'dart:async';

import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/team_config.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'managed_provider_cli_binding.dart';

/// Removes dedicated CLI provider rows and their isolated HOME directories.
///
/// Owned by the managed-provider delete hook (entry deleted → row + disk
/// credentials gone) and the startup sweep (orphaned `-mp-` rows reclaimed
/// every boot; legacy shared rows reclaimed exactly once, guarded by a
/// marker file). All operations are best-effort: failures are logged and
/// never propagate to callers.
class ManagedProviderCliRowJanitor {
  ManagedProviderCliRowJanitor({
    required Filesystem fs,
    required String basePath,
    AppProviderCubit? appProviderCubit,
  }) : _fs = fs,
       _basePath = basePath.trim(),
       _appProviderCubit = appProviderCubit;

  static const _sharedRowIds = <CliTool, String>{
    CliTool.cursor: 'cursor-account',
    CliTool.claude: 'claude-official',
    CliTool.codex: 'openai-official',
  };

  /// One-shot marker for the legacy shared-row deletion. Provider add-forms
  /// derive row ids from preset names (slugify), so a user re-adding the
  /// official preset recreates exactly these ids — deleting them on every
  /// boot would wipe the re-added row and its OAuth credentials in a loop.
  static const _sweptMarkerFile = '.managed-provider-shared-rows-swept';

  static const _clis = <CliTool>{
    CliTool.cursor,
    CliTool.claude,
    CliTool.codex,
  };

  final Filesystem _fs;
  final String _basePath;
  final AppProviderCubit? _appProviderCubit;

  /// Removes [rowId] from [cli]'s catalog and deletes
  /// `providers/<cli>/<rowId>/` from disk (credentials included).
  Future<void> removeDedicatedRow({
    required CliTool cli,
    required String rowId,
  }) async {
    final cubit = _appProviderCubit;
    if (cubit != null) {
      try {
        await cubit.removeProviderRow(cli, rowId);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] failed to remove CLI row $rowId: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await _removeProviderDir(cli, rowId);
  }

  /// Deletes orphaned `-mp-` rows (no corresponding managed-provider entry)
  /// on every boot, and the legacy shared rows exactly once (guarded by a
  /// marker file). Never creates or rewrites rows.
  Future<void> sweep({required Iterable<ManagedProvider> entries}) async {
    final binding = const ManagedProviderCliBinding();
    final liveRowIds = <String>{
      for (final entry in entries)
        binding.rowIdForCredentialSource(
              entry.endpointConfig.credentialSource.trim(),
            ) ??
            '',
    }..remove('');
    final sharedRowsSwept = await _hasSweptMarker();
    var allCatalogsLoaded = true;
    final cubit = _appProviderCubit;
    for (final cli in _clis) {
      final List<AppProviderConfig> rows;
      try {
        rows = cubit == null
            ? const []
            : await cubit.loadProvidersFor(cli);
      } on Object catch (error, stackTrace) {
        allCatalogsLoaded = false;
        appLogger.w(
          '[managed-provider] sweep failed to load ${cli.value} rows: $error',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      for (final row in rows) {
        final isShared =
            !sharedRowsSwept && row.id == _sharedRowIds[cli];
        final isOrphan = row.id.startsWith('${cli.value}-mp-') &&
            !liveRowIds.contains(row.id);
        if (!isShared && !isOrphan) continue;
        await removeDedicatedRow(cli: cli, rowId: row.id);
      }
    }
    // Only stamp the one-shot marker once every catalog was visited, so a
    // failed load retries the shared-row deletion on the next boot. The
    // deletion itself is idempotent either way.
    if (!sharedRowsSwept && allCatalogsLoaded) {
      await _writeSweptMarker();
    }
  }

  Future<void> _removeProviderDir(CliTool cli, String rowId) async {
    final dir = _fs.pathContext.join(
      _basePath,
      'providers',
      cli.value,
      rowId.trim(),
    );
    try {
      if ((await _fs.stat(dir)).exists) {
        await _fs.removeRecursive(dir);
      }
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[managed-provider] failed to remove directory $dir: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String get _sweptMarkerPath => _fs.pathContext.join(
    _basePath,
    'providers',
    _sweptMarkerFile,
  );

  Future<bool> _hasSweptMarker() async {
    try {
      return (await _fs.stat(_sweptMarkerPath)).exists;
    } on Object catch (error, stackTrace) {
      // Treat as unswept: the shared-row deletion is idempotent, so a
      // retry on the next boot is safe.
      appLogger.w(
        '[managed-provider] failed to read sweep marker $_sweptMarkerPath: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _writeSweptMarker() async {
    try {
      await _fs.ensureDir(_fs.pathContext.join(_basePath, 'providers'));
      await _fs.writeString(_sweptMarkerPath, '');
    } on Object catch (error, stackTrace) {
      // Best-effort: without the marker the next boot retries the (idempotent)
      // shared-row deletion.
      appLogger.w(
        '[managed-provider] failed to write sweep marker $_sweptMarkerPath: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
