import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../shared_state/hlc.dart';
import '../shared_state/or_set.dart';
import '../shared_state/shared_state_identity.dart';
import '../shared_state/shared_state_store.dart';
import '../storage/home_storage.dart';
import 'home_workspace_shared_state.dart';

/// Persists favourited workspace ids as a merged OR-Set in the home plane.
class WorkspaceFavoritesStore {
  WorkspaceFavoritesStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
    SharedStateStore? stateStore,
    String? deviceId,
    HlcClock? clock,
  }) : _clock = clock ?? SharedStateIdentity.clockFor(deviceId),
       _state =
           stateStore ??
           SharedStateStore(
             fs: fs ?? storage.fs,
             path:
                 pathOverride ??
                 storage.paths.homeWorkspaceWorkspaceFavoritesJson,
             clock: clock ?? SharedStateIdentity.clockFor(deviceId),
             mergeRegistry: homeWorkspaceSharedStateRegistry,
           );

  final SharedStateStore _state;
  final HlcClock _clock;

  Future<Set<String>> load() async {
    try {
      await _migrateLegacy();
      return favoritesOf(await _state.read()).values;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] favourites load failed',
        error: error,
        stackTrace: stackTrace,
      );
      return <String>{};
    }
  }

  Future<bool> toggle(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return false;
    try {
      await _migrateLegacy();
      final written = await _state.update((document) {
        final current = favoritesOf(document);
        final next = current.contains(id)
            ? current.remove(id)
            : current.add(id, _clock.now());
        return document.withSection(
          homeWorkspaceFavoritesSection,
          next.toJson(),
        );
      });
      return favoritesOf(written).contains(id);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] favourites toggle failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _migrateLegacy() async {
    final raw = await _state.readJson();
    if (raw is! Map || raw['sections'] is Map) return;
    final ids = raw['workspaceIds'];
    if (ids is! List) return;
    var legacy = const OrSet();
    var index = 0;
    for (final rawId in ids) {
      if (rawId is String && rawId.trim().isNotEmpty) {
        legacy = legacy.add(rawId.trim(), legacyHlc(index++));
      }
    }
    await _state.update(
      (document) => document.withSection(
        homeWorkspaceFavoritesSection,
        favoritesOf(document).merge(legacy).toJson(),
      ),
    );
  }
}
