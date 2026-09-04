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
/// credentials gone) and the startup sweep (orphaned `-mp-` rows and the
/// legacy shared rows are reclaimed). All operations are best-effort:
/// failures are logged and never propagate to callers.
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
  /// and the legacy shared rows. Never creates or rewrites rows.
  Future<void> sweep({required Iterable<ManagedProvider> entries}) async {
    final binding = const ManagedProviderCliBinding();
    final liveRowIds = <String>{
      for (final entry in entries)
        binding.rowIdForCredentialSource(
              entry.endpointConfig.credentialSource.trim(),
            ) ??
            '',
    }..remove('');
    final cubit = _appProviderCubit;
    for (final cli in _clis) {
      final List<AppProviderConfig> rows;
      try {
        rows = cubit == null
            ? const []
            : await cubit.loadProvidersFor(cli);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] sweep failed to load ${cli.value} rows: $error',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      for (final row in rows) {
        final isShared = row.id == _sharedRowIds[cli];
        final isOrphan = row.id.startsWith('${cli.value}-mp-') &&
            !liveRowIds.contains(row.id);
        if (!isShared && !isOrphan) continue;
        await removeDedicatedRow(cli: cli, rowId: row.id);
      }
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
}
