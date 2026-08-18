import 'dart:convert';

import '../../models/managed_provider.dart';
import '../../repositories/ssh_credential_store.dart';

/// Resolves the credentials needed by one managed-provider request.
abstract interface class ProviderCredentialResolver {
  Future<Map<String, String>?> resolve(ManagedProvider provider);
}

/// Securely stores credentials referenced by [ManagedProvider.credentialRef].
///
/// The field manifest contains field names only. Secret values are kept in the
/// injected secure backend and are never part of a managed-provider model or
/// usage snapshot.
class ManagedProviderSecretStore {
  ManagedProviderSecretStore(this._store);

  static const namespace = 'teampilot.managed_provider.v1';
  static const maskedValue = '••••••••';
  static const _manifestField = '__fields';

  final SecureKeyValueStore _store;

  /// Reads all credentials stored for [credentialRef].
  Future<Map<String, String>> read(String credentialRef) async {
    final ref = _normalizeReference(credentialRef);
    if (ref == null) return const {};

    final values = <String, String>{};
    for (final field in await _readFields(ref)) {
      final value = await _store.read(_key(ref, field));
      if (value != null) values[field] = value;
    }
    return Map.unmodifiable(values);
  }

  /// Stores request credentials under the versioned managed-provider namespace.
  Future<void> write(String credentialRef, Map<String, String> values) async {
    final ref = _normalizeReference(credentialRef);
    if (ref == null) return;

    final normalized = <String, String>{};
    for (final entry in values.entries) {
      final field = _normalizeField(entry.key);
      if (field == null || entry.value.isEmpty) continue;
      normalized[field] = entry.value;
    }

    final previousFields = await _readFields(ref);
    for (final field in previousFields) {
      if (!normalized.containsKey(field)) {
        await _store.delete(_key(ref, field));
      }
    }
    for (final entry in normalized.entries) {
      await _store.write(_key(ref, entry.key), entry.value);
    }
    if (normalized.isEmpty) {
      await _store.delete(_key(ref, _manifestField));
      return;
    }
    await _store.write(
      _key(ref, _manifestField),
      jsonEncode(normalized.keys.toList()..sort()),
    );
  }

  /// Deletes every stored field associated with [credentialRef].
  Future<void> delete(String credentialRef) async {
    final ref = _normalizeReference(credentialRef);
    if (ref == null) return;

    for (final field in await _readFields(ref)) {
      await _store.delete(_key(ref, field));
    }
    await _store.delete(_key(ref, _manifestField));
  }

  /// Returns values suitable for UI display without exposing secret material.
  Future<Map<String, String>> readMasked(String credentialRef) async {
    final values = await read(credentialRef);
    return Map.unmodifiable({
      for (final field in values.keys) field: maskedValue,
    });
  }

  static String? mask(String value) => value.isEmpty ? null : maskedValue;

  String _key(String ref, String field) => '$namespace.$ref.$field';

  Future<List<String>> _readFields(String ref) async {
    final raw = await _store.read(_key(ref, _manifestField));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final fields = <String>[];
      for (final value in decoded) {
        if (value is String) {
          final field = _normalizeField(value);
          if (field != null) fields.add(field);
        }
      }
      return fields;
    } on Object {
      return const [];
    }
  }

  static String? _normalizeReference(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static String? _normalizeField(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == _manifestField || value.contains('.')) {
      return null;
    }
    return value;
  }
}

/// Resolves a managed provider's reference only for the current request.
class ManagedProviderCredentialResolver implements ProviderCredentialResolver {
  const ManagedProviderCredentialResolver(this._store);

  final ManagedProviderSecretStore _store;

  @override
  Future<Map<String, String>?> resolve(ManagedProvider provider) async {
    final ref = provider.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;

    final credentials = await _store.read(ref);
    if (credentials.isEmpty) return null;
    return Map.unmodifiable(credentials);
  }
}
