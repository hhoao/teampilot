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
    // Functional paths unlock silently with the remembered master password;
    // only an explicit reveal prompts for a fresh password.
    try {
      if (await _vault.tryAutoUnlock()) return true;
    } on Object {
      // Fall through to the prompt; a broken auto-unlock must not block saves.
    }
    final prompted = await _prompt();
    return prompted && _vault.isUnlocked;
  }
}
