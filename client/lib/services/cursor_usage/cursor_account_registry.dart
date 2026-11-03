import 'dart:convert';

import 'package:collection/collection.dart';

import '../../models/cursor_usage_account.dart';
import '../../repositories/managed_provider_storage_lock.dart';
import '../cli/cursor/provider/cursor_usage_auth_resolver.dart';
import '../io/filesystem.dart';
import 'cursor_account_credential_store.dart';

/// Merges auto-discovered Cursor logins with manually pasted ones.
///
/// Precedence on the same [CursorUsageAccount.accountId]: the manual entry owns
/// `label`, `enabled`, `teamId`, and `owningUser`; the token always comes from
/// whichever credential is still valid, so a stale pasted token cannot shadow a
/// fresh provider-home token.
abstract interface class CursorAccountDirectory {
  Future<List<CursorUsageAccount>> list();

  Future<CursorAccountCredentials?> credentialFor(String accountId);

  Future<void> remove(String accountId);

  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  });
}

final class CursorAccountRegistry implements CursorAccountDirectory {
  CursorAccountRegistry({
    required Filesystem fs,
    required String accountsPath,
    required CursorAccountCredentialStore credentials,
    required Future<List<CursorUsageAuth>> Function() resolveAuths,
    Future<String?> Function(String providerId)? providerNameFor,
    DateTime Function()? now,
  }) : _fs = fs,
       _path = accountsPath,
       _credentials = credentials,
       _resolveAuths = resolveAuths,
       _providerNameFor = providerNameFor,
       _now = now ?? DateTime.now;

  final Filesystem _fs;
  final String _path;
  final CursorAccountCredentialStore _credentials;
  final Future<List<CursorUsageAuth>> Function() _resolveAuths;
  final Future<String?> Function(String providerId)? _providerNameFor;
  final DateTime Function() _now;

  @override
  Future<List<CursorUsageAccount>> list() async {
    final stored = await _readAccounts();
    final discoveredAccounts = await _resolveAuths();
    final providerNames = await _resolveProviderNames(discoveredAccounts);
    final out = <String, CursorUsageAccount>{};

    for (final auth in discoveredAccounts) {
      final override = stored[auth.account];
      final providerId = auth.providerId;
      out[auth.account] = CursorUsageAccount(
        accountId: auth.account,
        userId: auth.userId,
        label: override?.label ?? _defaultLabel(auth.account),
        source: override?.source ?? CursorAccountSource.discovered,
        enabled: override?.enabled ?? true,
        expiresAtMs: auth.expiresAtMs,
        owningUser: override?.owningUser,
        teamId: override?.teamId ?? 0,
        hasCredential: true,
        providerId: providerId,
        providerName: providerId == null
            ? null
            : providerNames[providerId],
      );
    }

    for (final entry in stored.entries) {
      if (out.containsKey(entry.key)) continue;
      final manual = await _credentials.read(entry.key);
      out[entry.key] = CursorUsageAccount(
        accountId: entry.key,
        userId: manual?.userId ?? entry.value.userId,
        label: entry.value.label.isEmpty
            ? _defaultLabel(entry.key)
            : entry.value.label,
        source: CursorAccountSource.manual,
        enabled: entry.value.enabled,
        expiresAtMs: manual?.expiresAtMs,
        owningUser: entry.value.owningUser,
        teamId: entry.value.teamId,
        hasCredential: manual != null,
      );
    }

    return out.values.toList()..sort((a, b) {
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  /// Resolves display names for the distinct provider ids in one batch, so a
  /// list render costs at most one catalog lookup per provider.
  Future<Map<String, String>> _resolveProviderNames(
    List<CursorUsageAuth> accounts,
  ) async {
    final resolver = _providerNameFor;
    if (resolver == null) return const {};
    final names = <String, String>{};
    for (final id in accounts
        .map((auth) => auth.providerId)
        .whereType<String>()
        .toSet()) {
      try {
        final name = await resolver(id);
        if (name != null && name.trim().isNotEmpty) names[id] = name.trim();
      } on Object {
        // The catalog is display-only here; a missing name falls back to the id.
      }
    }
    return names;
  }

  @override
  Future<CursorAccountCredentials?> credentialFor(String accountId) async {
    final stored = await _credentials.read(accountId);
    // [_resolveAuths] may include expired tokens so the list can show them;
    // syncing still requires a live one.
    final nowMs = _now().millisecondsSinceEpoch;
    final discoveredAccounts = (await _resolveAuths())
        .where((auth) => auth.expiresAtMs > nowMs + 60000)
        .toList();
    final match = discoveredAccounts
        .where((auth) => auth.account == accountId)
        .firstOrNull;
    final discoveredExpires = match?.expiresAtMs ?? 0;
    if (stored != null && stored.expiresAtMs >= discoveredExpires) {
      return stored;
    }
    if (match == null) return stored;
    return CursorAccountCredentials(
      accountId: match.account,
      userId: match.userId,
      token: match.token,
      expiresAtMs: match.expiresAtMs,
    );
  }

  @override
  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  }) async {
    await _mutate((accounts) {
      final previous =
          accounts[accountId] ??
          CursorUsageAccount(
            accountId: accountId,
            userId: '',
            label: _defaultLabel(accountId),
            source: CursorAccountSource.discovered,
          );
      accounts[accountId] = previous.copyWith(
        label: label,
        enabled: enabled,
        teamId: teamId,
        owningUser: owningUser,
      );
    });
  }

  @override
  Future<void> remove(String accountId) async {
    await _credentials.delete(accountId);
    await _mutate((accounts) => accounts.remove(accountId));
  }

  Future<Map<String, CursorUsageAccount>> _readAccounts() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final accounts = decoded['accounts'];
      if (accounts is! Map) return {};
      final out = <String, CursorUsageAccount>{};
      for (final entry in accounts.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final account = CursorUsageAccount.fromJson(
          Map<String, Object?>.from(value),
        );
        if (account.accountId.isEmpty) continue;
        out[account.accountId] = account;
      }
      return out;
    } on Object {
      return {};
    }
  }

  Future<void> _mutate(
    void Function(Map<String, CursorUsageAccount> accounts) change,
  ) async {
    await ManagedProviderStorageLock.run(_path, () async {
      final accounts = await _readAccounts();
      change(accounts);
      await _fs.ensureDir(_fs.pathContext.dirname(_path));
      await _fs.atomicWrite(
        _path,
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'accounts': {
            for (final entry in accounts.entries)
              entry.key: entry.value.toJson(),
          },
        }),
      );
    });
  }

  static String _defaultLabel(String accountId) =>
      'Cursor · ${accountId.length >= 6 ? accountId.substring(0, 6) : accountId}';
}
