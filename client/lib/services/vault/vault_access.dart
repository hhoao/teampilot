import '../../models/vault_entry.dart';
import 'vault_service.dart';

/// The single read policy for functional credential access.
///
/// Functional readers (SSH dial, provider catalogs, usage probes, relay
/// grants) must never prompt. They try the remembered master password first
/// and otherwise return null; explicit viewing goes through the reveal flow,
/// which always re-authenticates.
class VaultAccess {
  VaultAccess(this._vault);

  final VaultService _vault;

  VaultService get vault => _vault;

  bool get isEncrypted => _vault.isEncrypted;

  bool get isUnlocked => _vault.isUnlocked;

  Future<void> tryAutoUnlock() async {
    try {
      await _vault.tryAutoUnlock();
    } on Object {
      // A failed auto-unlock leaves the vault locked; readers return null.
    }
  }

  Future<String?> functionalField(String entryId, String field) async {
    if (!_vault.isUnlocked) await tryAutoUnlock();
    try {
      return await _vault.readField(entryId, field);
    } on Object {
      return null;
    }
  }

  Future<VaultEntry?> functionalEntry(String entryId) async {
    if (!_vault.isUnlocked) await tryAutoUnlock();
    try {
      return await _vault.get(entryId);
    } on Object {
      return null;
    }
  }
}
