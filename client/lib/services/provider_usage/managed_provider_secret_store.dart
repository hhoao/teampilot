import 'dart:collection';
import 'dart:convert';

import '../../models/managed_provider.dart';
import '../../repositories/ssh_credential_store.dart';

/// A request-scoped view of managed-provider credentials.
///
/// Credential values are available only through this explicit scope. Its
/// diagnostic representation never includes field values.
abstract interface class ProviderCredentialScope {
  bool get isEmpty;
  Iterable<String> get fields;
  String? valueFor(String field);
  ManagedProviderCredentialMap asMap();
}

/// An immutable map view whose diagnostics never include credential values.
class ManagedProviderCredentialMap extends MapBase<String, String> {
  ManagedProviderCredentialMap(Map<String, String> values)
    : _values = Map.unmodifiable(values);

  final Map<String, String> _values;

  @override
  String? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, String value) => _throwImmutable();

  @override
  void clear() => _throwImmutable();

  @override
  Iterable<String> get keys => _values.keys;

  @override
  String? remove(Object? key) => _throwImmutable();

  @override
  String toString() => 'ManagedProviderCredentialMap(<redacted>)';

  Never _throwImmutable() => throw UnsupportedError('immutable');
}

class ManagedProviderCredentialScope implements ProviderCredentialScope {
  ManagedProviderCredentialScope(Map<String, String> values)
    : _values = Map.unmodifiable(values);

  final Map<String, String> _values;

  @override
  bool get isEmpty => _values.isEmpty;

  @override
  Iterable<String> get fields => _values.keys;

  @override
  String? valueFor(String field) => _values[field];

  @override
  ManagedProviderCredentialMap asMap() => ManagedProviderCredentialMap(_values);

  @override
  String toString() => 'ManagedProviderCredentialScope(<redacted>)';
}

enum ManagedProviderCredentialErrorCode {
  invalidReference,
  invalidField,
  manifestMissing,
  manifestCorrupt,
  storageReadFailed,
  storageWriteFailed,
  storageDeleteFailed,
}

/// Secret-free failures from managed-provider credential storage.
class ManagedProviderCredentialError implements Exception {
  const ManagedProviderCredentialError(this.code);

  final ManagedProviderCredentialErrorCode code;

  String get message => 'Managed provider credential ${code.name}.';

  @override
  String toString() => 'ManagedProviderCredentialError: $message';
}

/// Resolves the credentials needed by one managed-provider request.
abstract interface class ProviderCredentialResolver {
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider);
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
  static const _initializedField = '__initialized';

  final SecureKeyValueStore _store;

  /// Reads all credentials stored for [credentialRef].
  Future<ManagedProviderCredentialScope> read(String credentialRef) async {
    final ref = _requireReference(credentialRef);
    final manifest = await _readManifest(ref);
    if (manifest.isMissing) {
      if (manifest.isInitialized) _throwManifestMissing();
      return ManagedProviderCredentialScope(const {});
    }

    final values = <String, String>{};
    for (final field in manifest.fields) {
      final value = await _readKey(_key(ref, field));
      if (value != null) values[field] = value;
    }
    return ManagedProviderCredentialScope(values);
  }

  /// Stores request credentials under the versioned managed-provider namespace.
  Future<void> write(String credentialRef, Map<String, String> values) async {
    final ref = _requireReference(credentialRef);
    final normalized = _normalizeValues(values);
    final manifest = await _readManifest(ref);

    if (manifest.isMissing) {
      if (manifest.isInitialized || normalized.isEmpty) {
        _throwManifestMissing();
      }
      final writtenFields = <String>[];
      var markerAttempted = false;
      var manifestAttempted = false;
      try {
        markerAttempted = true;
        await _writeKey(_key(ref, _initializedField), '1');
        for (final entry in normalized.entries) {
          writtenFields.add(entry.key);
          await _writeKey(_key(ref, entry.key), entry.value);
        }
        manifestAttempted = true;
        await _writeManifest(ref, normalized.keys);
      } on Object {
        await _rollbackNewWrite(
          ref,
          writtenFields,
          markerAttempted: markerAttempted,
          manifestAttempted: manifestAttempted,
        );
        rethrow;
      }
      return;
    }

    final previousValues = <String, String?>{};
    for (final field in manifest.fields) {
      previousValues[field] = await _readKey(_key(ref, field));
    }
    final hadInitializedMarker =
        await _readKey(_key(ref, _initializedField)) != null;
    final touchedFields = <String>[];
    try {
      await _writeKey(_key(ref, _initializedField), '1');
      for (final field in manifest.fields) {
        if (!normalized.containsKey(field)) {
          touchedFields.add(field);
          await _deleteKey(_key(ref, field));
        }
      }
      for (final entry in normalized.entries) {
        touchedFields.add(entry.key);
        await _writeKey(_key(ref, entry.key), entry.value);
      }
      if (normalized.isEmpty) {
        await _deleteKey(_key(ref, _manifestField));
        await _deleteKey(_key(ref, _initializedField));
        return;
      }
      await _writeManifest(ref, normalized.keys);
    } on Object {
      await _rollbackReplacement(
        ref,
        manifest.fields,
        previousValues,
        touchedFields,
        hadInitializedMarker: hadInitializedMarker,
      );
      rethrow;
    }
  }

  /// Deletes every stored field associated with [credentialRef].
  Future<void> delete(String credentialRef) async {
    final ref = _requireReference(credentialRef);
    final manifest = await _readManifest(ref);
    if (manifest.isMissing) {
      if (manifest.isInitialized) _throwManifestMissing();
      return;
    }

    for (final field in manifest.fields) {
      await _deleteKey(_key(ref, field));
    }
    await _deleteKey(_key(ref, _manifestField));
    await _deleteKey(_key(ref, _initializedField));
  }

  /// Returns values suitable for UI display without exposing secret material.
  Future<Map<String, String>> readMasked(String credentialRef) async {
    final values = await read(credentialRef);
    return Map.unmodifiable({
      for (final field in values.fields) field: maskedValue,
    });
  }

  static String? mask(String value) => value.isEmpty ? null : maskedValue;

  String _key(String ref, String field) => '$namespace.$ref.$field';

  Future<void> _rollbackNewWrite(
    String ref,
    List<String> writtenFields, {
    required bool markerAttempted,
    required bool manifestAttempted,
  }) async {
    if (manifestAttempted) {
      await _tryDeleteKey(_key(ref, _manifestField));
    }
    for (final field in writtenFields.reversed) {
      await _tryDeleteKey(_key(ref, field));
    }
    if (markerAttempted) {
      await _tryDeleteKey(_key(ref, _initializedField));
    }
  }

  Future<void> _rollbackReplacement(
    String ref,
    List<String> previousFields,
    Map<String, String?> previousValues,
    List<String> touchedFields, {
    required bool hadInitializedMarker,
  }) async {
    final fieldsToRestore = <String>{...previousFields, ...touchedFields};
    for (final field in fieldsToRestore) {
      final previousValue = previousValues[field];
      if (previousValues.containsKey(field) && previousValue != null) {
        await _tryWriteKey(_key(ref, field), previousValue);
      } else {
        await _tryDeleteKey(_key(ref, field));
      }
    }
    await _tryWriteManifest(ref, previousFields);
    if (hadInitializedMarker) {
      await _tryWriteKey(_key(ref, _initializedField), '1');
    } else {
      await _tryDeleteKey(_key(ref, _initializedField));
    }
  }

  Future<void> _tryWriteManifest(String ref, Iterable<String> fields) async {
    try {
      await _writeManifest(ref, fields);
    } on Object {
      // Preserve the original secret-free operation error.
    }
  }

  Future<void> _tryWriteKey(String key, String value) async {
    try {
      await _writeKey(key, value);
    } on Object {
      // Preserve the original secret-free operation error.
    }
  }

  Future<void> _tryDeleteKey(String key) async {
    try {
      await _deleteKey(key);
    } on Object {
      // Preserve the original secret-free operation error.
    }
  }

  Future<_ManifestRead> _readManifest(String ref) async {
    final raw = await _readKey(_key(ref, _manifestField));
    if (raw == null) {
      final initialized = await _readKey(_key(ref, _initializedField));
      return _ManifestRead.missing(initialized != null);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) _throwManifestCorrupt();

      final fields = <String>[];
      for (final value in decoded) {
        if (value is! String) _throwManifestCorrupt();
        final field = _normalizeField(value);
        if (field == null || fields.contains(field)) _throwManifestCorrupt();
        fields.add(field);
      }
      return _ManifestRead.present(fields);
    } on ManagedProviderCredentialError {
      rethrow;
    } on Object {
      _throwManifestCorrupt();
    }
  }

  Map<String, String> _normalizeValues(Map<String, String> values) {
    final normalized = <String, String>{};
    for (final entry in values.entries) {
      final field = _normalizeField(entry.key);
      if (field == null) _throwInvalidField();
      if (entry.value.isNotEmpty) normalized[field] = entry.value;
    }
    return normalized;
  }

  Future<void> _writeManifest(String ref, Iterable<String> fields) {
    final sortedFields = fields.toList()..sort();
    return _writeKey(_key(ref, _manifestField), jsonEncode(sortedFields));
  }

  Future<String?> _readKey(String key) async {
    try {
      return await _store.read(key);
    } on Object {
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.storageReadFailed,
      );
    }
  }

  Future<void> _writeKey(String key, String value) async {
    try {
      await _store.write(key, value);
    } on Object {
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.storageWriteFailed,
      );
    }
  }

  Future<void> _deleteKey(String key) async {
    try {
      await _store.delete(key);
    } on Object {
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.storageDeleteFailed,
      );
    }
  }

  static String _requireReference(String raw) {
    final value = _normalizeReference(raw);
    if (value == null) _throwInvalidReference();
    return value;
  }

  static String? _normalizeReference(String raw) {
    final value = raw.trim();
    return _isSafeComponent(value) ? value : null;
  }

  static String? _normalizeField(String raw) {
    final value = raw.trim();
    if (value == _manifestField || value == _initializedField) return null;
    return _isSafeComponent(value) ? value : null;
  }

  static bool _isSafeComponent(String value) {
    if (value.isEmpty || value.contains('/') || value.contains('\\')) {
      return false;
    }
    if (value.contains('.')) return false;
    return !value.codeUnits.any((unit) => unit <= 0x1f || unit == 0x7f);
  }

  static Never _throwInvalidReference() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.invalidReference,
      );

  static Never _throwInvalidField() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.invalidField,
      );

  static Never _throwManifestMissing() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.manifestMissing,
      );

  static Never _throwManifestCorrupt() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.manifestCorrupt,
      );
}

class _ManifestRead {
  const _ManifestRead.present(this.fields)
    : isInitialized = true,
      isMissing = false;

  const _ManifestRead.missing(this.isInitialized)
    : fields = const [],
      isMissing = true;

  final List<String> fields;
  final bool isInitialized;
  final bool isMissing;
}

/// Resolves a managed provider's reference only for the current request.
class ManagedProviderCredentialResolver implements ProviderCredentialResolver {
  const ManagedProviderCredentialResolver(this._store);

  final ManagedProviderSecretStore _store;

  @override
  Future<ProviderCredentialScope?> resolve(ManagedProvider provider) async {
    final ref = provider.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;

    final credentials = await _store.read(ref);
    if (credentials.isEmpty) return null;
    return credentials;
  }
}
