import 'dart:async';
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
  rollbackIncomplete,
  recoveryPersistenceFailed,
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
  static final _credentialRefLock = _CredentialRefLock();

  final SecureKeyValueStore _store;

  /// Reads all credentials stored for [credentialRef].
  Future<ManagedProviderCredentialScope> read(String credentialRef) async {
    final ref = _requireReference(credentialRef);
    return await _credentialRefLock.run(ref, () => _readUnlocked(ref));
  }

  /// Stores request credentials under the versioned managed-provider namespace.
  Future<void> write(String credentialRef, Map<String, String> values) async {
    final ref = _requireReference(credentialRef);
    final normalized = _normalizeValues(values);
    await _credentialRefLock.run(ref, () => _writeUnlocked(ref, normalized));
  }

  Future<void> _writeUnlocked(
    String ref,
    Map<String, String> normalized,
  ) async {
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
        final rollbackResult = await _rollbackNewWrite(
          ref,
          writtenFields,
          markerAttempted: markerAttempted,
          manifestAttempted: manifestAttempted,
        );
        _throwForRollbackResult(rollbackResult);
        rethrow;
      }
      return;
    }

    final previousValues = <String, String?>{};
    for (final field in manifest.fields) {
      final value = await _readKey(_key(ref, field));
      if (value == null) _throwManifestCorrupt();
      previousValues[field] = value;
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
      final rollbackResult = await _rollbackReplacement(
        ref,
        manifest.fields,
        previousValues,
        touchedFields,
        hadInitializedMarker: hadInitializedMarker,
      );
      _throwForRollbackResult(rollbackResult);
      rethrow;
    }
  }

  /// Updates credentials and persists the matching Provider under one ref lock.
  ///
  /// If [persistProvider] fails, the previous credential state is restored
  /// before the error is rethrown. Empty credential values intentionally bypass
  /// storage so callers can preserve existing secrets by submitting a blank
  /// secret field.
  Future<T> runCredentialTransaction<T>({
    required String credentialRef,
    required Map<String, String> nextValues,
    required Future<T> Function() persistProvider,
  }) async {
    final values = {
      for (final entry in nextValues.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    if (values.isEmpty) return persistProvider();

    final ref = _requireReference(credentialRef);
    final normalized = _normalizeValues(values);
    return await _credentialRefLock.run(ref, () async {
      final previous = await _readUnlocked(ref);
      final previousValues = {
        for (final field in previous.fields)
          if (previous.valueFor(field) != null)
            field: previous.valueFor(field)!,
      };

      await _writeUnlocked(ref, normalized);
      try {
        return await persistProvider();
      } on Object {
        if (previousValues.isEmpty) {
          await _deleteUnlocked(ref);
        } else {
          await _writeUnlocked(ref, previousValues);
        }
        rethrow;
      }
    });
  }

  /// Deletes every stored field associated with [credentialRef].
  Future<void> delete(String credentialRef) async {
    final ref = _requireReference(credentialRef);
    await _credentialRefLock.run(ref, () => _deleteUnlocked(ref));
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

  Future<ManagedProviderCredentialScope> _readUnlocked(String ref) async {
    final manifest = await _readManifest(ref);
    if (manifest.isMissing) {
      if (manifest.isInitialized) _throwManifestMissing();
      return ManagedProviderCredentialScope(const {});
    }

    final values = <String, String>{};
    for (final field in manifest.fields) {
      final value = await _readKey(_key(ref, field));
      if (value == null) _throwManifestCorrupt();
      values[field] = value;
    }
    return ManagedProviderCredentialScope(values);
  }

  Future<void> _deleteUnlocked(String ref) async {
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

  Future<_RollbackResult> _rollbackNewWrite(
    String ref,
    List<String> writtenFields, {
    required bool markerAttempted,
    required bool manifestAttempted,
  }) async {
    var incomplete = false;
    final recoverableFields = <String>{};
    if (manifestAttempted) {
      if (!await _tryDeleteKey(_key(ref, _manifestField))) {
        incomplete = true;
      }
    }
    for (final field in writtenFields.reversed) {
      if (!await _tryDeleteKey(_key(ref, field))) {
        incomplete = true;
        recoverableFields.add(field);
      }
    }
    if (markerAttempted) {
      if (!await _tryDeleteKey(_key(ref, _initializedField))) {
        incomplete = true;
      }
    }
    if (incomplete) {
      if (!await _tryWriteRecoveryState(ref, recoverableFields)) {
        return _RollbackResult.recoveryPersistenceFailed;
      }
      return _RollbackResult.rollbackIncomplete;
    }
    return _RollbackResult.complete;
  }

  Future<_RollbackResult> _rollbackReplacement(
    String ref,
    List<String> previousFields,
    Map<String, String?> previousValues,
    List<String> touchedFields, {
    required bool hadInitializedMarker,
  }) async {
    var incomplete = false;
    final recoverableFields = <String>{};
    final fieldsToRestore = <String>{...previousFields, ...touchedFields};
    for (final field in fieldsToRestore) {
      final previousValue = previousValues[field];
      if (previousValues.containsKey(field) && previousValue != null) {
        if (await _tryWriteKey(_key(ref, field), previousValue)) {
          recoverableFields.add(field);
        } else {
          incomplete = true;
          recoverableFields.add(field);
        }
      } else {
        if (!await _tryDeleteKey(_key(ref, field))) {
          incomplete = true;
          recoverableFields.add(field);
        }
      }
    }
    if (!await _tryWriteManifest(ref, previousFields)) {
      incomplete = true;
    }
    if (hadInitializedMarker) {
      if (!await _tryWriteKey(_key(ref, _initializedField), '1')) {
        incomplete = true;
      }
    } else if (!await _tryDeleteKey(_key(ref, _initializedField))) {
      incomplete = true;
    }
    if (incomplete) {
      if (!await _tryWriteRecoveryState(ref, recoverableFields)) {
        return _RollbackResult.recoveryPersistenceFailed;
      }
      return _RollbackResult.rollbackIncomplete;
    }
    return _RollbackResult.complete;
  }

  Future<bool> _tryWriteRecoveryState(
    String ref,
    Iterable<String> fields,
  ) async {
    var success = await _tryWriteKey(_key(ref, _initializedField), '1');
    if (!await _tryWriteManifest(ref, fields)) success = false;
    return success;
  }

  Future<bool> _tryWriteManifest(String ref, Iterable<String> fields) async {
    try {
      await _writeManifest(ref, fields);
      return true;
    } on Object {
      // Preserve the original secret-free operation error.
      return false;
    }
  }

  Future<bool> _tryWriteKey(String key, String value) async {
    try {
      await _writeKey(key, value);
      return true;
    } on Object {
      // Preserve the original secret-free operation error.
      return false;
    }
  }

  Future<bool> _tryDeleteKey(String key) async {
    try {
      await _deleteKey(key);
      return true;
    } on Object {
      // Preserve the original secret-free operation error.
      return false;
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

  static Never _throwRollbackIncomplete() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.rollbackIncomplete,
      );

  static void _throwForRollbackResult(_RollbackResult result) {
    switch (result) {
      case _RollbackResult.complete:
        return;
      case _RollbackResult.rollbackIncomplete:
        _throwRollbackIncomplete();
      case _RollbackResult.recoveryPersistenceFailed:
        _throwRecoveryPersistenceFailed();
    }
  }

  static Never _throwRecoveryPersistenceFailed() =>
      throw const ManagedProviderCredentialError(
        ManagedProviderCredentialErrorCode.recoveryPersistenceFailed,
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

enum _RollbackResult { complete, rollbackIncomplete, recoveryPersistenceFailed }

class _CredentialRefLock {
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String ref, Future<T> Function() action) async {
    final previous = _tails[ref] ?? Future<void>.value();
    final release = Completer<void>();
    final queued = previous.then((_) => release.future);
    _tails[ref] = queued;

    await previous;
    try {
      return await action();
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(_tails[ref], queued)) _tails.remove(ref);
    }
  }
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
