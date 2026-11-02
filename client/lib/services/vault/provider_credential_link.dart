const vaultCredentialLinkPrefix = 'vault:';

/// 从 `AppProviderConfig.credentialLink` 取出保险库条目 id。
///
/// 非保险库链接（托管供应商 id）返回 null。
String? vaultEntryIdFromCredentialLink(String link) {
  final trimmed = link.trim();
  if (!trimmed.startsWith(vaultCredentialLinkPrefix)) return null;
  final id = trimmed.substring(vaultCredentialLinkPrefix.length);
  return id.isEmpty ? null : id;
}
