import 'package:flutter/foundation.dart';

import '../../../storage/home_storage.dart';
import 'compose_draft.dart';
import 'compose_draft_store.dart';

/// Memory front for persisted compose input drafts.
///
/// Persistence is home-plane: the persistent methods take the caller's
/// [HomeStorage] (the app-scoped [composeDraftCache] instance has no storage
/// of its own — UI/cubit call sites thread their injected storage in).
///
/// A draft stores both its plain text and the explicit token ranges that were
/// present. Tokens are restored only when the saved text still matches each
/// token slice; if the text was edited elsewhere, only the text comes back.
class ComposeDraftCache {
  ComposeDraftCache({
    Map<String, ComposeDraft>? store,
    ComposeDraftStore? persistentStore,
  }) : _store = store ?? {},
       _persistentStoreOverride = persistentStore;

  final Map<String, ComposeDraft> _store;
  final ComposeDraftStore? _persistentStoreOverride;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  ComposeDraftStore _persistentStore(HomeStorage storage) =>
      _persistentStoreOverride ??
      ComposeDraftStore(fs: storage.fs, rootPath: storage.appDataRoot);

  // ── Landing compose (workspace "New Chat") ──────────────────────────────

  ComposeDraft? landingDraft(String workspaceId) =>
      _store[_landingPrefix + workspaceId];

  void setLandingDraft(String workspaceId, ComposeDraft draft) =>
      _set(_landingPrefix + workspaceId, draft);

  void clearLandingDraft(String workspaceId) =>
      _store.remove(_landingPrefix + workspaceId);

  Future<ComposeDraft?> hydrateLanding(
    String workspaceId, {
    required HomeStorage storage,
    bool Function()? shouldSeed,
  }) async {
    final draft = await _persistentStore(storage).loadLanding(workspaceId);
    if (draft != null && draft.isNotEmpty && (shouldSeed?.call() ?? true)) {
      setLandingDraft(workspaceId, draft);
    }
    return draft;
  }

  Future<void> saveLanding(
    String workspaceId,
    ComposeDraft draft, {
    required HomeStorage storage,
  }) async {
    setLandingDraft(workspaceId, draft);
    await _persistentStore(storage).saveLanding(workspaceId, draft);
  }

  Future<void> clearLandingPersistent(
    String workspaceId, {
    required HomeStorage storage,
  }) => _persistentStore(storage).saveLanding(
    workspaceId,
    const ComposeDraft(text: ''),
  );

  // ── Session compose (session workbench) ─────────────────────────────────

  ComposeDraft? sessionDraft(String sessionId) =>
      _store[_sessionPrefix + sessionId];

  void setSessionDraft(String sessionId, ComposeDraft draft) =>
      _set(_sessionPrefix + sessionId, draft);

  void clearSessionDraft(String sessionId) =>
      _store.remove(_sessionPrefix + sessionId);

  Future<ComposeDraft?> hydrateSession(
    String workspaceId,
    String sessionId, {
    required HomeStorage storage,
    bool Function()? shouldSeed,
  }) async {
    final draft = await _persistentStore(
      storage,
    ).loadSession(workspaceId, sessionId);
    if (draft != null && draft.isNotEmpty && (shouldSeed?.call() ?? true)) {
      setSessionDraft(sessionId, draft);
    }
    return draft;
  }

  Future<void> saveSession(
    String workspaceId,
    String sessionId,
    ComposeDraft draft, {
    required HomeStorage storage,
  }) async {
    setSessionDraft(sessionId, draft);
    await _persistentStore(storage).saveSession(workspaceId, sessionId, draft);
  }

  Future<void> clearSessionPersistent(
    String workspaceId,
    String sessionId, {
    required HomeStorage storage,
  }) => _persistentStore(storage).clearSession(workspaceId, sessionId);

  /// Writing trimmed-empty text removes the entry — a cleared input must not
  /// resurrect stale text on remount.
  void _set(String key, ComposeDraft draft) {
    if (draft.isEmpty) {
      _store.remove(key);
      return;
    }
    _store[key] = draft;
  }

  /// Test helper / app teardown.
  @visibleForTesting
  void clear() => _store.clear();
}

/// Shared app-scoped memory instance. Compose hosts restore from and sync to
/// this instance directly (passing their injected [HomeStorage] to the
/// persistent methods); tests reset it via [ComposeDraftCache.clear].
final ComposeDraftCache composeDraftCache = ComposeDraftCache();
