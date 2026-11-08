import '../../pages/home_workspace/workspace_sort.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../shared_state/hlc.dart';
import '../shared_state/shared_state_document.dart';
import '../shared_state/shared_state_identity.dart';
import '../shared_state/shared_state_store.dart';
import '../storage/home_storage.dart';
import 'home_workspace_shared_state.dart';

class WorkspaceDisplayPrefs {
  const WorkspaceDisplayPrefs({
    this.gridView = true,
    this.sort = WorkspaceSort.recentlyUpdated,
  });

  final bool gridView;
  final WorkspaceSort sort;

  WorkspaceDisplayPrefs copyWith({bool? gridView, WorkspaceSort? sort}) {
    return WorkspaceDisplayPrefs(
      gridView: gridView ?? this.gridView,
      sort: sort ?? this.sort,
    );
  }
}

/// Persists workspace grid/list layout and sort as per-key LWW registers.
class WorkspaceDisplayPrefsStore {
  WorkspaceDisplayPrefsStore({
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
                 storage.paths.homeWorkspaceWorkspaceDisplayPrefsJson,
             clock: clock ?? SharedStateIdentity.clockFor(deviceId),
             mergeRegistry: homeWorkspaceSharedStateRegistry,
           );

  final SharedStateStore _state;
  final HlcClock _clock;

  Future<WorkspaceDisplayPrefs> load() async {
    try {
      await _migrateLegacy();
      return _prefsFrom(await _state.read());
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] display prefs load failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const WorkspaceDisplayPrefs();
    }
  }

  Future<void> save(WorkspaceDisplayPrefs prefs) async {
    await _saveKey('gridView', prefs.gridView);
    await _saveKey('sort', prefs.sort.name);
  }

  Future<void> setGridView(bool gridView) => _saveKey('gridView', gridView);

  Future<void> setSort(WorkspaceSort sort) => _saveKey('sort', sort.name);

  Future<void> _saveKey(String key, Object value) async {
    try {
      await _migrateLegacy();
      await _state.update((document) {
        final next = displayPrefsOf(document).set(key, value, _clock.now());
        return document.withSection(
          homeWorkspaceDisplayPrefsSection,
          encodeDisplayPrefs(next),
        );
      });
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] display prefs save failed key=$key',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  WorkspaceDisplayPrefs _prefsFrom(SharedStateDocument document) {
    final values = displayPrefsOf(document);
    final gridView = values['gridView'];
    final sort = values['sort'];
    return WorkspaceDisplayPrefs(
      gridView: gridView is bool ? gridView : true,
      sort: WorkspaceSortLabels.parse(sort is String ? sort : null),
    );
  }

  Future<void> _migrateLegacy() async {
    final raw = await _state.readJson();
    if (raw is! Map || raw['sections'] is Map) return;
    if (!raw.containsKey('gridView') && !raw.containsKey('sort')) return;
    final gridView = raw['gridView'];
    final sort = raw['sort'];
    await _state.update((document) {
      var next = displayPrefsOf(document);
      if (gridView is bool) {
        next = next.set('gridView', gridView, legacyHlc(0));
      }
      if (sort is String && sort.trim().isNotEmpty) {
        next = next.set('sort', sort.trim(), legacyHlc(1));
      }
      return document.withSection(
        homeWorkspaceDisplayPrefsSection,
        encodeDisplayPrefs(next),
      );
    });
  }
}
