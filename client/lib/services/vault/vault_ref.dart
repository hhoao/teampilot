const vaultCredentialLinkPrefix = 'vault:';

/// A typed credential reference stored in a provider row.
///
/// The on-disk encoding stays the existing string (`vault:<id>` or a managed
/// provider id); this type is the single parser so new consumers do not repeat
/// prefix checks.
sealed class VaultRef {
  const VaultRef();

  static VaultRef? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith(vaultCredentialLinkPrefix)) {
      final id = trimmed.substring(vaultCredentialLinkPrefix.length).trim();
      return id.isEmpty ? null : VaultEntryRef(id);
    }
    return ManagedProviderRef(trimmed);
  }
}

final class VaultEntryRef extends VaultRef {
  const VaultEntryRef(this.entryId);

  final String entryId;

  String get link => '$vaultCredentialLinkPrefix$entryId';

  @override
  String toString() => link;
}

final class ManagedProviderRef extends VaultRef {
  const ManagedProviderRef(this.providerId);

  final String providerId;

  @override
  String toString() => providerId;
}

/// Returns the vault entry id for a `vault:<id>` link, or null.
String? vaultEntryIdFromCredentialLink(String link) {
  final ref = VaultRef.parse(link);
  return ref is VaultEntryRef ? ref.entryId : null;
}
