import '../../models/workspace_tab_ref.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../shared_state/device_lane.dart';
import '../shared_state/hlc.dart';
import '../shared_state/shared_state_identity.dart';
import '../shared_state/shared_state_store.dart';
import '../storage/home_storage.dart';
import 'home_workspace_shared_state.dart';

/// Persists this device's recently visited workspace tabs.
class HomeRecentWorkspacesStore {
  HomeRecentWorkspacesStore({
    required HomeStorage storage,
    Filesystem? fs,
    String? pathOverride,
    SharedStateStore? stateStore,
    String? deviceId,
    HlcClock? clock,
  }) : _deviceId = _device(deviceId),
       _clock = clock ?? SharedStateIdentity.clockFor(deviceId),
       _state =
           stateStore ??
           SharedStateStore(
             fs: fs ?? storage.fs,
             path:
                 pathOverride ??
                 storage.paths.homeWorkspaceRecentWorkspacesJson,
             clock: clock ?? SharedStateIdentity.clockFor(deviceId),
             mergeRegistry: homeWorkspaceSharedStateRegistry,
           );

  static const maxEntries = 30;

  final SharedStateStore _state;
  final HlcClock _clock;
  final String _deviceId;

  Future<List<WorkspaceTabRef>> loadOrderedTabs() async {
    try {
      await _migrateLegacy();
      final document = await _state.read();
      return recentWorkspacesOf(document).itemsFor(_deviceId);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] recent workspaces load failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Future<void> recordVisit(WorkspaceTabRef tab) async {
    if (tab.workspaceId.trim().isEmpty) return;
    try {
      await _migrateLegacy();
      await _state.update((document) {
        final current = recentWorkspacesOf(document).itemsFor(_deviceId);
        final next = [
          tab,
          for (final entry in current)
            if (entry.tabKey != tab.tabKey) entry,
        ].take(maxEntries).toList();
        final lanes = recentWorkspacesOf(document).put(
          _deviceId,
          DeviceLane<WorkspaceTabRef>(
            items: next,
            active: next.first.workspaceId,
            stamp: _clock.now(),
          ),
        );
        return document.withSection(
          homeWorkspaceRecentWorkspacesSection,
          encodeTabLanes(lanes),
        );
      });
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] recent workspaces record failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _migrateLegacy() async {
    final raw = await _state.readJson();
    if (raw is! Map || raw['sections'] is Map) return;
    final tabsRaw = raw['tabs'];
    if (tabsRaw is! List) return;
    final tabs = <WorkspaceTabRef>[];
    for (final entry in tabsRaw) {
      if (entry is! Map) continue;
      try {
        tabs.add(WorkspaceTabRef.fromJson(entry.cast<String, Object?>()));
      } on Object {
        continue;
      }
    }
    await _state.update((document) {
      final lanes = recentWorkspacesOf(document);
      if (lanes.byDevice.containsKey(_deviceId)) return document;
      final next = lanes.put(
        _deviceId,
        DeviceLane<WorkspaceTabRef>(
          items: tabs.take(maxEntries).toList(),
          active: tabs.isEmpty ? null : tabs.first.workspaceId,
          stamp: legacyHlc(0),
        ),
      );
      return document.withSection(
        homeWorkspaceRecentWorkspacesSection,
        encodeTabLanes(next),
      );
    });
  }
}

String _device(String? deviceId) {
  final trimmed = deviceId?.trim() ?? '';
  return trimmed.isEmpty ? SharedStateIdentity.deviceId : trimmed;
}
