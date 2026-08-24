import 'dart:convert';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_probe.dart';
import '../../../io/filesystem.dart';
import 'opencode_auth_artifacts.dart';
import 'opencode_credential_kind.dart';
import 'opencode_data_layout.dart';

/// Synthesizes OpenCode `auth.json` content and credential probes from catalog
/// providers. Single source of truth: [AppProviderConfig] fields.
abstract final class OpencodeCredentialMaterializer {
  OpencodeCredentialMaterializer._();

  static const _layout = OpencodeDataLayout();

  static bool isReady(AppProviderConfig provider) {
    final kind = OpencodeCredentialKindResolver.forProvider(provider);
    return switch (kind) {
      OpencodeCredentialKind.none => true,
      OpencodeCredentialKind.apiKey => provider.apiKey.trim().isNotEmpty,
      OpencodeCredentialKind.authEntry => _authEntryIndicatesReady(provider),
    };
  }

  static CredentialProbe probe(AppProviderConfig provider) {
    final id = provider.id.trim();
    return CredentialProbe(
      providerId: id,
      status: isReady(provider) ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: _catalogCredentialLabel(provider),
    );
  }

  /// JSON document for `OPENCODE_AUTH_CONTENT` / on-disk `auth.json`.
  static String? authJsonContent(AppProviderConfig provider) {
    final id = provider.id.trim();
    if (id.isEmpty) return null;

    final kind = OpencodeCredentialKindResolver.forProvider(provider);
    return switch (kind) {
      OpencodeCredentialKind.none => null,
      OpencodeCredentialKind.apiKey => _authJsonFromApiKey(id, provider.apiKey),
      OpencodeCredentialKind.authEntry => _authJsonFromStoredEntry(provider),
    };
  }

  /// Extracts an API key from a global `auth.json` provider entry for catalog
  /// import (live import / one-shot migration).
  static String? apiKeyFromAuthEntry(Object? entry) {
    if (entry is! Map) return null;
    final map = entry.cast<String, Object?>();
    final type = map['type']?.toString().trim() ?? '';
    if (type == 'api') {
      final key = map['key']?.toString().trim() ?? '';
      return key.isEmpty ? null : key;
    }
    return null;
  }

  /// Normalizes a live-imported auth entry into catalog fields.
  static ({
    OpencodeCredentialKind kind,
    String apiKey,
    Map<String, Object?> configPatch,
  })? catalogFieldsFromAuthEntry({
    required String providerId,
    required Object? entry,
    required Map<String, Object?> existingConfig,
  }) {
    if (entry is! Map) return null;
    final map = entry.cast<String, Object?>();
    if (!OpencodeAuthArtifacts.entryIndicatesReady({providerId: map}, providerId)) {
      return null;
    }

    final apiKey = apiKeyFromAuthEntry(map);
    if (apiKey != null) {
      return (
        kind: OpencodeCredentialKind.apiKey,
        apiKey: apiKey,
        configPatch: _configWithoutAuthEntry(existingConfig),
      );
    }

    return (
      kind: OpencodeCredentialKind.authEntry,
      apiKey: '',
      configPatch: {
        ...existingConfig,
        OpencodeCredentialConfigKeys.kind: 'authEntry',
        OpencodeCredentialConfigKeys.authEntry: map,
      },
    );
  }

  static Future<bool> writeAuthArtifact({
    required Filesystem fs,
    required String basePath,
    required AppProviderConfig provider,
  }) async {
    final content = authJsonContent(provider);
    if (content == null) return false;

    final providerId = provider.id.trim();
    if (providerId.isEmpty) return false;

    final providerDir = fs.pathContext.join(
      basePath,
      'providers',
      'opencode',
      providerId,
    );
    final authPath = _layout.providerAuthJsonPath(providerDir);
    await fs.ensureDir(_layout.providerDataHome(providerDir));
    await fs.atomicWrite(authPath, content);
    return true;
  }

  static String _catalogCredentialLabel(AppProviderConfig provider) {
    final kind = OpencodeCredentialKindResolver.forProvider(provider);
    return switch (kind) {
      OpencodeCredentialKind.apiKey => 'providers.json#apiKey',
      OpencodeCredentialKind.authEntry => 'providers.json#authEntry',
      OpencodeCredentialKind.none => '',
    };
  }

  static String? _authJsonFromApiKey(String providerId, String apiKey) {
    final key = apiKey.trim();
    if (key.isEmpty) return null;
    final payload = <String, Object?>{
      providerId: {'type': 'api', 'key': key},
    };
    return _encodeAuthPayload(payload, providerId);
  }

  static String? _authJsonFromStoredEntry(AppProviderConfig provider) {
    final entry = _storedAuthEntry(provider);
    if (entry == null) return null;
    final id = provider.id.trim();
    final payload = <String, Object?>{id: entry};
    return _encodeAuthPayload(payload, id);
  }

  static String? _encodeAuthPayload(
    Map<String, Object?> payload,
    String providerId,
  ) {
    if (!OpencodeAuthArtifacts.authJsonIndicatesReady(
      jsonEncode(payload),
      providerId,
    )) {
      return null;
    }
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static bool _authEntryIndicatesReady(AppProviderConfig provider) {
    final entry = _storedAuthEntry(provider);
    if (entry == null) return false;
    final id = provider.id.trim();
    return OpencodeAuthArtifacts.entryIndicatesReady({id: entry}, id);
  }

  static Map<String, Object?>? _storedAuthEntry(AppProviderConfig provider) {
    final raw = provider.config[OpencodeCredentialConfigKeys.authEntry];
    if (raw is! Map) return null;
    return raw.cast<String, Object?>();
  }

  static Map<String, Object?> _configWithoutAuthEntry(
    Map<String, Object?> config,
  ) {
    final next = Map<String, Object?>.from(config);
    next.remove(OpencodeCredentialConfigKeys.authEntry);
    next[OpencodeCredentialConfigKeys.kind] = 'apiKey';
    return next;
  }
}
