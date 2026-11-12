import '../../models/vault_entry.dart';
import '../../utils/logging/logger.dart';
import '../ssh/ssh_connection_gate.dart';
import 'vault_service.dart';

/// One-shot, zero-loss migration of pre-split business credentials.
///
/// Before the split, provider/GitHub/managed-provider secrets lived in the
/// device vault alongside SSH login credentials. Copy every non-SSH entry to
/// the home plane, keyed by id, and leave the device copy in place — a dropped
/// transport must never lose a credential. Idempotent: an id already present
/// on the home plane is skipped.
Future<int> migrateBusinessVaultEntries({
  required VaultService device,
  required VaultService home,
}) async {
  try {
    await home.initialize();
    if (home.isLocked) return 0;
    final existing = <String>{for (final entry in await home.list()) entry.id};
    var copied = 0;
    for (final entry in await device.list()) {
      if (_isSshCredential(entry)) continue;
      if (existing.contains(entry.id)) continue;
      try {
        await home.upsert(entry);
        copied += 1;
      } on Object catch (error, stackTrace) {
        if (isSshProfileDown(error)) {
          AppLogger.instance.d(
            '[home-vault] migration copy waiting for home transport',
            error: error,
            stackTrace: stackTrace,
          );
          continue;
        }
        AppLogger.instance.w(
          '[home-vault] migration copy failed for ${entry.id}: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return copied;
  } on Object catch (error, stackTrace) {
    if (isSshProfileDown(error)) {
      AppLogger.instance.d(
        '[home-vault] migration waiting for home transport',
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    }
    AppLogger.instance.w(
      '[home-vault] migration skipped: $error',
      error: error,
      stackTrace: stackTrace,
    );
    return 0;
  }
}

bool _isSshCredential(VaultEntry entry) =>
    entry.extra['ownerKind'] == 'sshProfile' ||
    entry.type == VaultEntryType.sshPassword ||
    entry.type == VaultEntryType.sshPrivateKey;
