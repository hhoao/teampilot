import 'package:flutter/foundation.dart';

import '../storage/app_storage.dart';
import 'compose_draft_store.dart';

/// Memory front for persisted compose input drafts.
class ComposeDraftCache {
  ComposeDraftCache({Map<String, String>? store}) : _store = store ?? {};

  final Map<String, String> _store;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  ComposeDraftStore get _persistentStore =>
      ComposeDraftStore(fs: AppStorage.fs, rootPath: AppStorage.appDataRoot);

  // ── Landing compose (workspace "New Chat") ──────────────────────────────

  String? landingDraft(String workspaceId) =>
      _store[_landingPrefix + workspaceId];

  void setLandingDraft(String workspaceId, String text) =>
      _set(_landingPrefix + workspaceId, text);

  void clearLandingDraft(String workspaceId) =>
      _store.remove(_landingPrefix + workspaceId);

  Future<String?> hydrateLanding(String workspaceId) async {
    final text = await _persistentStore.loadLanding(workspaceId);
    if (text != null && text.isNotEmpty) {
      setLandingDraft(workspaceId, text);
    }
    return text;
  }

  Future<void> saveLanding(String workspaceId, String text) async {
    setLandingDraft(workspaceId, text);
    await _persistentStore.saveLanding(workspaceId, text);
  }

  Future<void> clearLandingPersistent(String workspaceId) =>
      _persistentStore.saveLanding(workspaceId, '');

  // ── Session compose (session workbench) ─────────────────────────────────

  String? sessionDraft(String sessionId) => _store[_sessionPrefix + sessionId];

  void setSessionDraft(String sessionId, String text) =>
      _set(_sessionPrefix + sessionId, text);

  void clearSessionDraft(String sessionId) =>
      _store.remove(_sessionPrefix + sessionId);

  Future<String?> hydrateSession(String workspaceId, String sessionId) async {
    final text = await _persistentStore.loadSession(workspaceId, sessionId);
    if (text != null && text.isNotEmpty) {
      setSessionDraft(sessionId, text);
    }
    return text;
  }

  Future<void> saveSession(
    String workspaceId,
    String sessionId,
    String text,
  ) async {
    setSessionDraft(sessionId, text);
    await _persistentStore.saveSession(workspaceId, sessionId, text);
  }

  Future<void> clearSessionPersistent(String workspaceId, String sessionId) =>
      _persistentStore.clearSession(workspaceId, sessionId);

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

/// Shared app-scoped instance. Compose hosts restore from and sync to this
/// instance directly; tests reset it via [ComposeDraftCache.clear].
final ComposeDraftCache composeDraftCache = ComposeDraftCache();
