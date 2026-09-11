import 'package:flutter/foundation.dart';

import '../storage/home_storage.dart';
import 'compose_draft_store.dart';

/// Memory front for persisted compose input drafts.
///
/// Persistence is home-plane: the persistent methods take the caller's
/// [HomeStorage] (the app-scoped [composeDraftCache] instance has no storage
/// of its own — UI/cubit call sites thread their injected storage in).
class ComposeDraftCache {
  ComposeDraftCache({
    Map<String, String>? store,
    ComposeDraftStore? persistentStore,
  }) : _store = store ?? {},
       _persistentStoreOverride = persistentStore;

  final Map<String, String> _store;
  final ComposeDraftStore? _persistentStoreOverride;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  ComposeDraftStore _persistentStore(HomeStorage storage) =>
      _persistentStoreOverride ??
      ComposeDraftStore(fs: storage.fs, rootPath: storage.appDataRoot);

  // ── Landing compose (workspace "New Chat") ──────────────────────────────

  String? landingDraft(String workspaceId) =>
      _store[_landingPrefix + workspaceId];

  void setLandingDraft(String workspaceId, String text) =>
      _set(_landingPrefix + workspaceId, text);

  void clearLandingDraft(String workspaceId) =>
      _store.remove(_landingPrefix + workspaceId);

  Future<String?> hydrateLanding(
    String workspaceId, {
    required HomeStorage storage,
    bool Function()? shouldSeed,
  }) async {
    final text = await _persistentStore(storage).loadLanding(workspaceId);
    if (text != null && text.isNotEmpty && (shouldSeed?.call() ?? true)) {
      setLandingDraft(workspaceId, text);
    }
    return text;
  }

  Future<void> saveLanding(
    String workspaceId,
    String text, {
    required HomeStorage storage,
  }) async {
    setLandingDraft(workspaceId, text);
    await _persistentStore(storage).saveLanding(workspaceId, text);
  }

  Future<void> clearLandingPersistent(
    String workspaceId, {
    required HomeStorage storage,
  }) => _persistentStore(storage).saveLanding(workspaceId, '');

  // ── Session compose (session workbench) ─────────────────────────────────

  String? sessionDraft(String sessionId) => _store[_sessionPrefix + sessionId];

  void setSessionDraft(String sessionId, String text) =>
      _set(_sessionPrefix + sessionId, text);

  void clearSessionDraft(String sessionId) =>
      _store.remove(_sessionPrefix + sessionId);

  Future<String?> hydrateSession(
    String workspaceId,
    String sessionId, {
    required HomeStorage storage,
    bool Function()? shouldSeed,
  }) async {
    final text = await _persistentStore(storage).loadSession(
      workspaceId,
      sessionId,
    );
    if (text != null && text.isNotEmpty && (shouldSeed?.call() ?? true)) {
      setSessionDraft(sessionId, text);
    }
    return text;
  }

  Future<void> saveSession(
    String workspaceId,
    String sessionId,
    String text, {
    required HomeStorage storage,
  }) async {
    setSessionDraft(sessionId, text);
    await _persistentStore(storage).saveSession(workspaceId, sessionId, text);
  }

  Future<void> clearSessionPersistent(
    String workspaceId,
    String sessionId, {
    required HomeStorage storage,
  }) => _persistentStore(storage).clearSession(workspaceId, sessionId);

  /// Writing trimmed-empty text removes the entry — a cleared input must not
  /// resurrect stale text on remount.
  void _set(String key, String text) {
    if (text.trim().isEmpty) {
      _store.remove(key);
      return;
    }
    _store[key] = text;
  }

  /// Test helper / app teardown.
  @visibleForTesting
  void clear() => _store.clear();
}

/// Shared app-scoped memory instance. Compose hosts restore from and sync to
/// this instance directly (passing their injected [HomeStorage] to the
/// persistent methods); tests reset it via [ComposeDraftCache.clear].
final ComposeDraftCache composeDraftCache = ComposeDraftCache();
