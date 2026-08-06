import 'package:flutter/foundation.dart';

/// In-memory cache of compose input drafts, keyed by workspace (landing
/// compose) or session (session compose). Survives compose host unmounts so
/// switching away and back does not lose typed text. Not persisted to disk.
class ComposeDraftCache {
  ComposeDraftCache({Map<String, String>? store}) : _store = store ?? {};

  final Map<String, String> _store;

  static const _landingPrefix = 'landing:';
  static const _sessionPrefix = 'session:';

  // ── Landing compose (workspace "New Chat") ──────────────────────────────

  String? landingDraft(String workspaceId) =>
      _store[_landingPrefix + workspaceId];

  void setLandingDraft(String workspaceId, String text) =>
      _set(_landingPrefix + workspaceId, text);

  void clearLandingDraft(String workspaceId) =>
      _store.remove(_landingPrefix + workspaceId);

  // ── Session compose (session workbench) ─────────────────────────────────

  String? sessionDraft(String sessionId) => _store[_sessionPrefix + sessionId];

  void setSessionDraft(String sessionId, String text) =>
      _set(_sessionPrefix + sessionId, text);

  void clearSessionDraft(String sessionId) =>
      _store.remove(_sessionPrefix + sessionId);

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
