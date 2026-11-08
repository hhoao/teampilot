import '../../models/home_closed_workspace_entry.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../shared_state/device_lane.dart';
import '../shared_state/hlc.dart';
import '../shared_state/shared_state_identity.dart';
import '../shared_state/shared_state_store.dart';
import '../storage/home_storage.dart';
import 'home_workspace_shared_state.dart';

/// Persists this device's recently closed title-bar workspace tabs.
class HomeClosedWorkspacesStore {
  HomeClosedWorkspacesStore({
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
                 storage.paths.homeWorkspaceClosedWorkspacesJson,
             clock: clock ?? SharedStateIdentity.clockFor(deviceId),
             mergeRegistry: homeWorkspaceSharedStateRegistry,
           );

  static const maxEntries = 20;

  final SharedStateStore _state;
  final HlcClock _clock;
  final String _deviceId;

  Future<List<HomeClosedWorkspaceEntry>> load() async {
    try {
      await _migrateLegacy();
      final document = await _state.read();
      final entries = closedWorkspacesOf(document).itemsFor(_deviceId);
      return [...entries]..sort((a, b) => b.closedAt.compareTo(a.closedAt));
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] closed workspaces load failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Future<void> recordClosed(HomeClosedWorkspaceEntry entry) async {
    final workspaceId = entry.workspaceId.trim();
    if (workspaceId.isEmpty) return;
    try {
      await _migrateLegacy();
      await _state.update((document) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final stamped = HomeClosedWorkspaceEntry(
          workspaceId: workspaceId,
          displayName: entry.displayName,
          primaryPath: entry.primaryPath,
          closedAt: now,
          topology: entry.topology,
        );
        final current = closedWorkspacesOf(document).itemsFor(_deviceId);
        final next = [
          stamped,
          for (final existing in current)
            if (existing.tabKey != stamped.tabKey) existing,
        ].take(maxEntries).toList();
        final lanes = closedWorkspacesOf(document).put(
          _deviceId,
          DeviceLane<HomeClosedWorkspaceEntry>(
            items: next,
            stamp: _clock.now(),
          ),
        );
        return document.withSection(
          homeWorkspaceClosedWorkspacesSection,
          encodeClosedLanes(lanes),
        );
      });
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] closed workspaces record failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> remove(String tabKey) async {
    final trimmed = tabKey.trim();
    if (trimmed.isEmpty) return;
    try {
      await _migrateLegacy();
      await _state.update((document) {
        final current = closedWorkspacesOf(document).itemsFor(_deviceId);
        final next = [
          for (final entry in current)
            if (entry.tabKey != trimmed) entry,
        ];
        final lanes = closedWorkspacesOf(document).put(
          _deviceId,
          DeviceLane<HomeClosedWorkspaceEntry>(
            items: next,
            stamp: _clock.now(),
          ),
        );
        return document.withSection(
          homeWorkspaceClosedWorkspacesSection,
          encodeClosedLanes(lanes),
        );
      });
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[shared-state] closed workspaces remove failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _migrateLegacy() async {
    final raw = await _state.readJson();
    if (raw is! Map || raw['sections'] is Map) return;
    final entriesRaw = raw['entries'];
    if (entriesRaw is! List) return;
    final entries = <HomeClosedWorkspaceEntry>[];
    for (final rawEntry in entriesRaw) {
      if (rawEntry is! Map) continue;
      try {
        entries.add(
          HomeClosedWorkspaceEntry.fromJson(rawEntry.cast<String, Object?>()),
        );
      } on Object {
        continue;
      }
    }
    entries.sort((a, b) => b.closedAt.compareTo(a.closedAt));
    await _state.update((document) {
      final lanes = closedWorkspacesOf(document);
      if (lanes.byDevice.containsKey(_deviceId)) return document;
      final next = lanes.put(
        _deviceId,
        DeviceLane<HomeClosedWorkspaceEntry>(
          items: entries.take(maxEntries).toList(),
          stamp: legacyHlc(0),
        ),
      );
      return document.withSection(
        homeWorkspaceClosedWorkspacesSection,
        encodeClosedLanes(next),
      );
    });
  }
}

String _device(String? deviceId) {
  final trimmed = deviceId?.trim() ?? '';
  return trimmed.isEmpty ? SharedStateIdentity.deviceId : trimmed;
}
