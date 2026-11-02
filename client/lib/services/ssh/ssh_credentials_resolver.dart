import '../../models/ssh_profile.dart';

typedef VaultCredentialReader =
    Future<String?> Function(String entryId, String field);

class ResolvedSshCredentials {
  const ResolvedSshCredentials({
    this.password,
    this.privateKey,
    this.passphrase,
  });

  final String? password;
  final String? privateKey;
  final String? passphrase;
}

/// 显式的凭据来源优先级：`vaultEntryId` > 钥匙串。
Future<ResolvedSshCredentials> resolveSshCredentials(
  SshProfile profile, {
  VaultCredentialReader? vault,
  required Future<String?> Function(String profileId) legacyPassword,
  required Future<String?> Function(String profileId) legacyPrivateKey,
  required Future<String?> Function(String profileId) legacyPassphrase,
}) async {
  final entryId = profile.vaultEntryId;
  final useVault = entryId != null && entryId.isNotEmpty && vault != null;

  switch (profile.authType) {
    case SshAuthType.password:
      final password = useVault
          ? await vault(entryId, 'password')
          : await legacyPassword(profile.id);
      return ResolvedSshCredentials(password: password);
    case SshAuthType.privateKey:
      final privateKey = useVault
          ? await vault(entryId, 'privateKey')
          : await legacyPrivateKey(profile.id);
      final passphrase = useVault
          ? await vault(entryId, 'passphrase')
          : await legacyPassphrase(profile.id);
      return ResolvedSshCredentials(
        privateKey: privateKey,
        passphrase: passphrase,
      );
  }
}
