import '../../repositories/extension_repository.dart';

/// One-time migrations of legacy settings into [ExtensionRepository].
class ExtensionStateMigration {
  static const _rtkFlagKey = 'rtk_flag_v1';

  /// Copies the legacy `AppSettingsRepository.loadRtkEnabled` value into
  /// `globalEnabled` exactly once (guarded by a marker), so the old rtk
  /// toggle's state carries over to the unified store.
  static Future<void> run({
    required ExtensionRepository repository,
    required Future<bool> Function() legacyRtkEnabled,
  }) async {
    if (await repository.isMigrated(_rtkFlagKey)) return;
    if (await legacyRtkEnabled()) {
      await repository.setGlobalEnabled('rtk', true);
    }
    await repository.markMigrated(_rtkFlagKey);
  }
}
