import 'package:uuid/uuid.dart';

import '../../models/app_provider_config.dart';
import '../../models/managed_provider.dart';
import '../../models/ssh_profile.dart';
import '../../models/vault_entry.dart';
import 'vault_service.dart';

const vaultOwnerKindSshProfile = 'sshProfile';
const vaultOwnerKindAppProvider = 'appProvider';
const vaultOwnerKindManagedProvider = 'managedProvider';
const vaultOwnerKindGithub = 'github';

class VaultCaptureResult {
  const VaultCaptureResult({
    required this.entryId,
    required this.created,
    this.previous,
  });

  final String entryId;
  final bool created;
  final VaultEntry? previous;
}

class VaultCaptureException implements Exception {
  const VaultCaptureException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultCaptureException($reason)';
}

/// Creates or updates the vault entry that owns a credential.
///
/// Merge semantics for [fields]: `null` keeps the existing value, an empty
/// string removes the field, and a non-empty string overwrites it.
class VaultCredentialCapture {
  VaultCredentialCapture({required VaultService vault, Uuid? uuid})
    : _vault = vault,
      _uuid = uuid ?? const Uuid();

  final VaultService _vault;
  final Uuid _uuid;

  Future<VaultEntry?> findOwner(String ownerKind, String ownerId) async {
    for (final entry in await _vault.list()) {
      if (entry.extra['ownerKind'] == ownerKind &&
          entry.extra['ownerId'] == ownerId) {
        return entry;
      }
    }
    return null;
  }

  Future<VaultCaptureResult> captureSsh(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
    String? relayGrant,
  }) {
    final passwordAuth = profile.authType == SshAuthType.password;
    return _upsert(
      ownerKind: vaultOwnerKindSshProfile,
      ownerId: profile.id,
      type: passwordAuth
          ? VaultEntryType.sshPassword
          : VaultEntryType.sshPrivateKey,
      title: profile.name,
      tags: const ['ssh'],
      revealable: passwordAuth,
      fields: {
        'host': profile.host,
        'port': '${profile.port}',
        'username': profile.username,
        if (password != null) 'password': password,
        if (privateKey != null) 'privateKey': privateKey,
        if (passphrase != null) 'passphrase': passphrase,
        if (relayGrant != null) 'relayGrant': relayGrant,
      },
    );
  }

  /// [apiKey]: null keeps the stored key, an empty string removes it, a
  /// value overwrites it. Callers that have a key must pass it explicitly.
  Future<VaultCaptureResult> captureProvider(
    AppProviderConfig provider, {
    String? apiKey,
  }) {
    return _upsert(
      ownerKind: vaultOwnerKindAppProvider,
      // Provider ids are per-CLI catalogs; qualify to avoid cross-CLI
      // clobbering of the same id.
      ownerId: '${provider.cli.value}:${provider.id.trim()}',
      type: VaultEntryType.apiKey,
      title: provider.name,
      tags: const ['provider'],
      revealable: true,
      fields: {
        'provider': provider.id,
        'baseUrl': provider.baseUrl,
        if (apiKey != null) 'apiKey': apiKey,
      },
    );
  }

  /// Merges [values] into the provider's entry.
  ///
  /// The entry type is chosen from the merged field set: a single field
  /// becomes [VaultEntryType.apiKey], more than one becomes
  /// [VaultEntryType.custom]. [_upsert] writes that type as-is and never
  /// recomputes it, so a later call that only touches one field keeps the
  /// type decided by the total field count at that time.
  Future<VaultCaptureResult> captureManaged(
    ManagedProvider provider,
    Map<String, String> values,
  ) async {
    final existing = await findOwner(
      vaultOwnerKindManagedProvider,
      provider.id,
    );
    final merged = {...?existing?.fields, ...values}
      ..removeWhere((key, value) => value.isEmpty);
    return _upsert(
      ownerKind: vaultOwnerKindManagedProvider,
      ownerId: provider.id,
      type: merged.length <= 1 ? VaultEntryType.apiKey : VaultEntryType.custom,
      title: provider.name,
      tags: const ['usage'],
      revealable: true,
      fields: values,
    );
  }

  Future<Map<String, String>> existingManagedFields(
    ManagedProvider provider,
  ) async {
    final entryId = provider.vaultEntryId?.trim() ?? '';
    if (entryId.isEmpty) return const {};
    final entry = await _vault.get(entryId);
    return entry?.fields ?? const {};
  }

  Future<VaultCaptureResult> captureGithub({
    required String token,
    String? login,
    String? source,
  }) {
    return _upsert(
      ownerKind: vaultOwnerKindGithub,
      ownerId: 'default',
      type: VaultEntryType.token,
      title: 'GitHub',
      tags: const ['github'],
      revealable: true,
      fields: {
        'token': token,
        if (login != null) 'login': login,
        if (source != null) 'source': source,
      },
    );
  }

  Future<void> rollback(VaultCaptureResult result) async {
    if (result.created) {
      await _vault.delete(result.entryId);
      return;
    }
    final previous = result.previous;
    if (previous != null) {
      await _vault.upsert(previous);
    }
  }

  Future<void> deleteOwner(String ownerKind, String ownerId) async {
    final entry = await findOwner(ownerKind, ownerId);
    if (entry != null) await _vault.delete(entry.id);
  }

  Future<VaultCaptureResult> _upsert({
    required String ownerKind,
    required String ownerId,
    required VaultEntryType type,
    required String title,
    required List<String> tags,
    required bool revealable,
    required Map<String, String> fields,
  }) async {
    final existing = await findOwner(ownerKind, ownerId);
    final merged = {
      ...?existing?.fields,
      for (final entry in fields.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    for (final entry in fields.entries) {
      if (entry.value.isEmpty) merged.remove(entry.key);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = VaultEntry(
      id: existing?.id ?? _uuid.v4(),
      type: type,
      title: title,
      fields: merged,
      tags: {...?existing?.tags, ...tags}.toList(growable: false),
      notes: existing?.notes ?? '',
      favorite: existing?.favorite ?? false,
      revealable: type == VaultEntryType.sshPrivateKey ? false : revealable,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      extra: {...?existing?.extra, 'ownerKind': ownerKind, 'ownerId': ownerId},
    );
    await _vault.upsert(entry);
    if (!await _vault.verifyFields(entry.id, merged)) {
      if (existing == null) {
        await _vault.delete(entry.id);
      } else {
        await _vault.upsert(existing);
      }
      throw const VaultCaptureException('verifyFailed');
    }
    return VaultCaptureResult(
      entryId: entry.id,
      created: existing == null,
      previous: existing,
    );
  }
}
