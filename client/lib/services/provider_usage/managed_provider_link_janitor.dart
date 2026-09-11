import 'dart:async';

import '../../cubits/app_provider_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';

/// Clears `credentialLink` references to a deleted managed-provider entry.
///
/// Owned by the managed-provider delete hook. Best-effort: failures are
/// logged and never propagate to the delete flow.
class ManagedProviderLinkJanitor {
  ManagedProviderLinkJanitor({required AppProviderCubit appProviderCubit})
    : _appProviderCubit = appProviderCubit;

  final AppProviderCubit _appProviderCubit;

  Future<void> clearLinksFor(String managedProviderId) async {
    final id = managedProviderId.trim();
    if (id.isEmpty) return;
    for (final cli in CliTool.values) {
      final List<AppProviderConfig> rows;
      try {
        rows = await _appProviderCubit.loadProvidersFor(cli);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[managed-provider] link janitor failed to load ${cli.value} rows: $error',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
      for (final row in rows) {
        if (row.credentialLink.trim() != id) continue;
        try {
          await _appProviderCubit.upsertProvider(
            row.copyWith(credentialLink: ''),
          );
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[managed-provider] link janitor failed to clear link on '
            '${cli.value}/${row.id}: $error',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }
}
