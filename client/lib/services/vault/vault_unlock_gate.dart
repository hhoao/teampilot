import 'vault_service.dart';

class VaultSaveBlockedException implements Exception {
  const VaultSaveBlockedException();

  @override
  String toString() => 'VaultSaveBlockedException';
}

/// Ensures the vault is writable before a credential is captured.
class VaultUnlockGate {
  VaultUnlockGate({
    required VaultService vault,
    required Future<bool> Function() prompt,
  }) : _vault = vault,
       _prompt = prompt;

  final VaultService _vault;
  final Future<bool> Function() _prompt;

  Future<bool> ensureUnlocked() async {
    if (_vault.isUnlocked) return true;
    final prompted = await _prompt();
    return prompted && _vault.isUnlocked;
  }
}
