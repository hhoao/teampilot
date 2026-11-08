import '../../models/home_closed_workspace_entry.dart';
import '../../models/workspace_tab_ref.dart';
import '../shared_state/device_lane.dart';
import '../shared_state/hlc.dart';
import '../shared_state/lww_map.dart';
import '../shared_state/or_set.dart';
import '../shared_state/shared_state_document.dart';

const homeWorkspaceFavoritesSection = 'homeWorkspace.favorites';
const homeWorkspaceOpenTabsSection = 'homeWorkspace.openTabs';
const homeWorkspaceClosedWorkspacesSection = 'homeWorkspace.closedWorkspaces';
const homeWorkspaceRecentWorkspacesSection = 'homeWorkspace.recentWorkspaces';
const homeWorkspaceDisplayPrefsSection = 'homeWorkspace.displayPrefs';

/// Shared-state merge policy for every `home_workspace/` document.
final homeWorkspaceSharedStateRegistry = SharedStateMergeRegistry({
  homeWorkspaceFavoritesSection: _mergeFavorites,
  homeWorkspaceOpenTabsSection: _mergeTabLanes,
  homeWorkspaceClosedWorkspacesSection: _mergeClosedLanes,
  homeWorkspaceRecentWorkspacesSection: _mergeTabLanes,
  homeWorkspaceDisplayPrefsSection: _mergeDisplayPrefs,
});

/// Deterministic stamp for entries migrated from the pre-shared-state files.
/// Zero wall time keeps them older than any real clock stamp.
Hlc legacyHlc(int index) =>
    Hlc(wallMillis: 0, counter: index, nodeId: 'legacy');

OrSet favoritesOf(SharedStateDocument document) =>
    OrSet.fromJson(document.sections[homeWorkspaceFavoritesSection]);

DeviceLanes<WorkspaceTabRef> openTabsOf(SharedStateDocument document) =>
    DeviceLanes.fromJson<WorkspaceTabRef>(
      document.sections[homeWorkspaceOpenTabsSection],
      decode: _decodeTab,
    );

DeviceLanes<HomeClosedWorkspaceEntry> closedWorkspacesOf(
  SharedStateDocument document,
) => DeviceLanes.fromJson<HomeClosedWorkspaceEntry>(
  document.sections[homeWorkspaceClosedWorkspacesSection],
  decode: _decodeClosed,
);

DeviceLanes<WorkspaceTabRef> recentWorkspacesOf(SharedStateDocument document) =>
    DeviceLanes.fromJson<WorkspaceTabRef>(
      document.sections[homeWorkspaceRecentWorkspacesSection],
      decode: _decodeTab,
    );

LwwMap<Object?> displayPrefsOf(SharedStateDocument document) =>
    LwwMap.fromJson<Object?>(
      document.sections[homeWorkspaceDisplayPrefsSection],
      decode: (value) => value,
    );

Object? encodeTabLanes(DeviceLanes<WorkspaceTabRef> lanes) =>
    lanes.toJson((tab) => tab.toJson());

Object? encodeClosedLanes(DeviceLanes<HomeClosedWorkspaceEntry> lanes) =>
    lanes.toJson((entry) => entry.toJson());

Object? encodeDisplayPrefs(LwwMap<Object?> prefs) =>
    prefs.toJson((value) => value);

WorkspaceTabRef _decodeTab(Object? raw) {
  if (raw is! Map) throw const FormatException('tab is not an object');
  return WorkspaceTabRef.fromJson(raw.cast<String, Object?>());
}

HomeClosedWorkspaceEntry _decodeClosed(Object? raw) {
  if (raw is! Map) throw const FormatException('closed entry is not an object');
  return HomeClosedWorkspaceEntry.fromJson(raw.cast<String, Object?>());
}

Object? _mergeFavorites(Object? local, Object? remote) =>
    OrSet.fromJson(local).merge(OrSet.fromJson(remote)).toJson();

Object? _mergeTabLanes(Object? local, Object? remote) =>
    DeviceLanes.fromJson<WorkspaceTabRef>(local, decode: _decodeTab)
        .merge(
          DeviceLanes.fromJson<WorkspaceTabRef>(remote, decode: _decodeTab),
        )
        .toJson((tab) => tab.toJson());

Object? _mergeClosedLanes(Object? local, Object? remote) =>
    DeviceLanes.fromJson<HomeClosedWorkspaceEntry>(local, decode: _decodeClosed)
        .merge(
          DeviceLanes.fromJson<HomeClosedWorkspaceEntry>(
            remote,
            decode: _decodeClosed,
          ),
        )
        .toJson((entry) => entry.toJson());

Object? _mergeDisplayPrefs(Object? local, Object? remote) =>
    LwwMap.fromJson<Object?>(local, decode: (value) => value)
        .merge(LwwMap.fromJson<Object?>(remote, decode: (value) => value))
        .toJson((value) => value);
