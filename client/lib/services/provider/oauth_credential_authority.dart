import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/credential_lease.dart';
import '../../utils/logging/logger_utils.dart';
import '../io/filesystem.dart';

/// Injected IdP refresh call. Production implementation posts to
/// `https://auth.x.ai` with the stored refresh token; tests use a fake.
abstract interface class CredentialRefresher {
  Future<CredentialRefreshOutcome> refresh(String refreshToken);
}

sealed class CredentialRefreshOutcome {
  const CredentialRefreshOutcome();
}

final class RefreshSucceeded extends CredentialRefreshOutcome {
  const RefreshSucceeded({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

final class RefreshRejected extends CredentialRefreshOutcome {
  const RefreshRejected();
}

/// Control-plane single owner of refresh tokens for one CLI namespace.
///
/// INVARIANT: refresh tokens never leave this class's on-disk store. Sessions
/// receive only [CredentialLease] values. All refreshes for a provider are
/// serialized through [_inFlight] and guarded by a monotonic generation
/// counter, so a late refresh can never overwrite a newer login or resurrect
/// a revoked credential.
final class OAuthCredentialAuthority {
  OAuthCredentialAuthority({
    required this.fs,
    required this.basePath,
    required this.cliNamespace,
    required this.refresher,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final Filesystem fs;
  final String basePath;
  final String cliNamespace;
  final CredentialRefresher refresher;
  final DateTime Function() _now;

  final Map<String, Future<CredentialLease>> _inFlight = {};
  final Set<String> _rejected = {};

  /// Highest epoch ever allocated for a provider in this process. Imports and
  /// refreshes both draw from it, so an in-flight refresh started at epoch N
  /// can never commit once a login (or revoke) advanced the provider past N.
  final Map<String, int> _generation = {};

  final ValueNotifier<Map<String, CredentialHealth>> _healthChanges =
      ValueNotifier<Map<String, CredentialHealth>>(const {});

  ValueListenable<Map<String, CredentialHealth>> get healthChanges =>
      _healthChanges;

  String providerDir(String providerId) => fs.pathContext.join(
        basePath,
        'providers',
        cliNamespace,
        _safe(providerId),
      );

  String credentialPath(String providerId) =>
      fs.pathContext.join(providerDir(providerId), 'credential.json');

  String legacyAuthPath(String providerId) =>
      fs.pathContext.join(providerDir(providerId), 'auth.json');

  /// Imports the `auth.json` produced by an isolated `grok login` /
  /// `importGlobal`. Returns false when it contains no usable tokens.
  ///
  /// The persisted epoch is always newer than whatever is on disk, so a
  /// refresh still in flight for the previous login cannot clobber it.
  Future<bool> importFromLogin(String providerId, List<int> bytes) async {
    _CredentialState? parsed;
    try {
      parsed = _parseAuthJson(providerId, utf8.decode(bytes));
    } on Object catch (error) {
      _logUnreadable(providerId, 'imported auth.json', error);
      return false;
    }
    if (parsed == null) {
      AppLogger.instance.w(
        'OAuthCredentialAuthority: imported auth.json for provider '
        '$providerId has no usable tokens',
      );
      return false;
    }
    final current = await _load(providerId);
    final state = parsed.withEpoch(
      _allocateEpoch(providerId, current?.epoch ?? -1),
    );
    await _persist(providerId, state);
    _rejected.remove(providerId);
    _emitHealth(providerId, _healthOf(state, _now()));
    return true;
  }

  /// One-time migration from the pre-Authority provider store. Deletes the
  /// old file only after a successful import.
  ///
  /// A corrupt-but-present `credential.json` counts as absent, so a broken
  /// store is recoverable from the legacy file; a valid credential still
  /// blocks the migration.
  Future<bool> importLegacyAuthJson(String providerId) async {
    final current = await _load(providerId);
    if (current != null) return false;
    final bytes = await fs.readBytes(legacyAuthPath(providerId));
    if (bytes == null || bytes.isEmpty) return false;
    final ok = await importFromLogin(providerId, bytes);
    if (!ok) return false;
    await fs.removeRecursive(legacyAuthPath(providerId));
    return true;
  }

  /// Throws [CredentialUnavailableException] when no lease can be minted.
  Future<CredentialLease> lease({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  }) async {
    final state = await _load(providerId);
    if (state == null) {
      throw CredentialUnavailableException(
        _rejected.contains(providerId)
            ? CredentialHealth.rejected
            : CredentialHealth.missing,
      );
    }
    if (!forceRefresh && _isUsable(state, _now())) {
      return _leaseFrom(state);
    }
    return _refreshSingleFlight(providerId, state);
  }

  Future<CredentialHealth> status(String providerId) async {
    if (_rejected.contains(providerId)) return CredentialHealth.rejected;
    final state = await _load(providerId);
    if (state == null) return CredentialHealth.missing;
    return _healthOf(state, _now());
  }

  /// Re-mints after ACP `auth_required`. Returns false when a login is needed.
  Future<bool> recover(String providerId, String sessionId) async {
    try {
      await lease(
        providerId: providerId,
        sessionId: sessionId,
        forceRefresh: true,
      );
      return true;
    } on CredentialUnavailableException {
      return false;
    }
  }

  Future<void> revoke(String providerId) async {
    _rejected.remove(providerId);
    _inFlight.remove(providerId);
    // Advance the generation so any refresh already running for the deleted
    // credential fails its commit check instead of validating a stale epoch.
    _generation[providerId] = (_generation[providerId] ?? -1) + 1;
    final path = credentialPath(providerId);
    if ((await fs.stat(path)).exists) await fs.removeRecursive(path);
    _emitHealth(providerId, CredentialHealth.missing);
  }

  Future<CredentialLease> _refreshSingleFlight(
    String providerId,
    _CredentialState state,
  ) {
    final existing = _inFlight[providerId];
    if (existing != null) return existing;
    final future = _doRefresh(providerId, state);
    _inFlight[providerId] = future;
    // Clear on both success and error, but only when this future is still the
    // registered one: revoke or a newer refresh may have replaced it.
    future.then<void>(
      (_) => _clearInFlight(providerId, future),
      onError: (Object error, StackTrace stackTrace) =>
          _clearInFlight(providerId, future),
    );
    return future;
  }

  void _clearInFlight(String providerId, Future<CredentialLease> future) {
    if (identical(_inFlight[providerId], future)) {
      _inFlight.remove(providerId);
    }
  }

  Future<CredentialLease> _doRefresh(
    String providerId,
    _CredentialState state,
  ) async {
    final outcome = await refresher.refresh(state.refreshToken);
    switch (outcome) {
      case RefreshRejected():
        await _markRejected(providerId);
        throw const CredentialUnavailableException(CredentialHealth.rejected);

      case RefreshSucceeded(
          :final accessToken,
          :final refreshToken,
          :final expiresAt,
        ):
        final current = await _load(providerId);
        // Revoked / removed while the IdP call was in flight: deletion is
        // final, so discard the result rather than resurrecting the store.
        if (current == null) {
          throw CredentialUnavailableException(
            _rejected.contains(providerId)
                ? CredentialHealth.rejected
                : CredentialHealth.missing,
          );
        }
        // A newer login or refresh already won: discard this late result.
        if (current.epoch > state.epoch) {
          return _leaseFrom(current);
        }
        final next = _CredentialState(
          providerId: providerId,
          refreshToken: refreshToken,
          accessToken: accessToken,
          expiresAt: expiresAt,
          epoch: _allocateEpoch(providerId, state.epoch),
        );
        await _persist(providerId, next);
        _rejected.remove(providerId);
        _emitHealth(providerId, _healthOf(next, _now()));
        return _leaseFrom(next);
    }
  }

  /// RT was rejected by the IdP. Delete it; NEVER write an empty credential
  /// back (grok wipes its own auth.json on permanent failure).
  Future<void> _markRejected(String providerId) async {
    _rejected.add(providerId);
    final path = credentialPath(providerId);
    if ((await fs.stat(path)).exists) await fs.removeRecursive(path);
    _emitHealth(providerId, CredentialHealth.rejected);
  }

  Future<_CredentialState?> _load(String providerId) async {
    final raw = await fs.readString(credentialPath(providerId));
    if (raw == null || raw.trim().isEmpty) return null;
    _CredentialState? state;
    try {
      state = _CredentialState.fromDiskJson(
        providerId,
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object catch (error) {
      _logUnreadable(providerId, 'credential.json', error);
      return null;
    }
    if (state == null) {
      AppLogger.instance.w(
        'OAuthCredentialAuthority: credential.json for provider $providerId '
        'is missing required fields',
      );
      return null;
    }
    _observeEpoch(providerId, state.epoch);
    return state;
  }

  Future<void> _persist(String providerId, _CredentialState state) async {
    await fs.ensureDir(providerDir(providerId));
    await fs.atomicWrite(
      credentialPath(providerId),
      jsonEncode(state.toDiskJson()),
    );
  }

  CredentialLease _leaseFrom(_CredentialState state) => CredentialLease(
        accessToken: state.accessToken,
        expiresAt: state.expiresAt,
        epoch: state.epoch,
      );

  bool _isUsable(_CredentialState state, DateTime now) =>
      state.accessToken.isNotEmpty &&
      state.expiresAt.isAfter(now.add(const Duration(seconds: 60)));

  CredentialHealth _healthOf(_CredentialState state, DateTime now) =>
      _isUsable(state, now)
          ? CredentialHealth.ready
          : CredentialHealth.expiring;

  void _emitHealth(String providerId, CredentialHealth health) {
    _healthChanges.value = {
      ..._healthChanges.value,
      providerId: health,
    };
  }

  /// Monotonic epoch allocation. [floor] is the epoch of the state being
  /// replaced (-1 when there is none), so a first import gets epoch 0.
  int _allocateEpoch(String providerId, int floor) {
    final next = math.max(_generation[providerId] ?? -1, floor) + 1;
    _generation[providerId] = next;
    return next;
  }

  void _observeEpoch(String providerId, int epoch) {
    if (epoch > (_generation[providerId] ?? -1)) {
      _generation[providerId] = epoch;
    }
  }

  /// Diagnostics only: provider id and failure class. The error object is
  /// deliberately not logged — JSON decode errors quote the source text,
  /// which may contain token material.
  void _logUnreadable(String providerId, String what, Object error) {
    AppLogger.instance.w(
      'OAuthCredentialAuthority: unreadable $what for provider $providerId '
      '(${error.runtimeType})',
    );
  }

  static _CredentialState? _parseAuthJson(String providerId, String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    for (final entry in decoded.values) {
      if (entry is! Map) continue;
      final access = entry['key']?.toString() ?? '';
      final refresh = entry['refresh_token']?.toString() ?? '';
      final expiresRaw = entry['expires_at']?.toString() ?? '';
      if (access.isEmpty || refresh.isEmpty) continue;
      final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
      if (expiresAt == null) continue;
      return _CredentialState(
        providerId: providerId,
        refreshToken: refresh,
        accessToken: access,
        expiresAt: expiresAt,
        epoch: 0,
      );
    }
    return null;
  }

  static String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty || safe == '.' || safe == '..' ? 'provider' : safe;
  }
}

/// Private on-disk state. Never serialized across the session boundary.
final class _CredentialState {
  const _CredentialState({
    required this.providerId,
    required this.refreshToken,
    required this.accessToken,
    required this.expiresAt,
    required this.epoch,
  });

  final String providerId;
  final String refreshToken;
  final String accessToken;
  final DateTime expiresAt;
  final int epoch;

  _CredentialState withEpoch(int nextEpoch) => _CredentialState(
        providerId: providerId,
        refreshToken: refreshToken,
        accessToken: accessToken,
        expiresAt: expiresAt,
        epoch: nextEpoch,
      );

  Map<String, Object?> toDiskJson() => {
        'provider_id': providerId,
        'refresh_token': refreshToken,
        'access_token': accessToken,
        'expires_at': expiresAt.toIso8601String(),
        'epoch': epoch,
      };

  static _CredentialState? fromDiskJson(
    String providerId,
    Map<String, Object?> json,
  ) {
    final refresh = json['refresh_token']?.toString() ?? '';
    final access = json['access_token']?.toString() ?? '';
    final expiresAt =
        DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toUtc();
    if (refresh.isEmpty || access.isEmpty || expiresAt == null) return null;
    return _CredentialState(
      providerId: providerId,
      refreshToken: refresh,
      accessToken: access,
      expiresAt: expiresAt,
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    );
  }
}
