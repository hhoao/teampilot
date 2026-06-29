import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Owns the open-tab list and all pure queries/derivations over it.
/// Never emits — callers read results and update ChatState themselves.
///
/// Tabs are bucketed by `workspaceId`. Every query/mutation below operates on the
/// *active* workspace's bucket ([setActiveWorkspace]); callers keep using the same
/// flat-list API. Per-workspace active-tab index is snapshotted on workspace switch,
/// not mirrored on every selection, so cubit call sites stay unchanged.
class ChatTabStore {
  final Map<String, List<ChatTab>> _byWorkspace = {};
  final Map<String, int> _savedActiveIndex = {};
  String _activeWorkspaceId = '';

  List<ChatTab> get _active => _byWorkspace.putIfAbsent(_activeWorkspaceId, () => []);

  /// Switches the active bucket. Pass [currentActiveIndex] (the cubit's current
  /// `ChatState.activeTabIndex`) to snapshot the outgoing workspace's selection.
  /// Returns the restored active-tab index for the incoming workspace (clamped).
  int setActiveWorkspace(String workspaceId, {int? currentActiveIndex}) {
    if (currentActiveIndex != null && _activeWorkspaceId.isNotEmpty) {
      _savedActiveIndex[_activeWorkspaceId] = currentActiveIndex;
    }
    _activeWorkspaceId = workspaceId;
    _byWorkspace.putIfAbsent(workspaceId, () => []);
    final saved = _savedActiveIndex[workspaceId] ?? 0;
    final len = _byWorkspace[workspaceId]!.length;
    if (len == 0) return 0;
    return saved.clamp(0, len - 1);
  }

  String get activeWorkspaceId => _activeWorkspaceId;

  List<ChatTab> get tabs => _active;
  int get length => _active.length;
  bool get isEmpty => _active.isEmpty;

  /// Clears every bucket (used on cubit close).
  void clear() {
    _byWorkspace.clear();
    _savedActiveIndex.clear();
  }

  /// Removes and returns all tabs belonging to [workspaceId] (for disposal by the
  /// caller). Clears the named bucket and also removes matching tabs from the
  /// legacy empty-string bucket (tabs added before [setActiveWorkspace] was called).
  List<ChatTab> removeWorkspace(String workspaceId) {
    _savedActiveIndex.remove(workspaceId);
    final removed = <ChatTab>[];
    // Named bucket.
    final named = _byWorkspace.remove(workspaceId);
    if (named != null) removed.addAll(named);
    // Legacy bucket: tabs whose persisted session belongs to this workspace.
    if (workspaceId.isNotEmpty) {
      final legacy = _byWorkspace[''];
      if (legacy != null) {
        final matching =
            legacy
                .where((t) => t.persistedSession?.workspaceId == workspaceId)
                .toList();
        if (matching.isNotEmpty) {
          legacy.removeWhere((t) => t.persistedSession?.workspaceId == workspaceId);
          removed.addAll(matching);
        }
      }
    }
    return removed;
  }

  /// Session-backed (non-`local-`) tab count for [workspaceId], across any bucket.
  ///
  /// Checks the named bucket first. Also scans the legacy empty-string bucket
  /// by persisted-session workspaceId so that tabs opened before [setActiveWorkspace]
  /// is called (e.g. the connect flow before the UI switches workspace context)
  /// are counted correctly.
  int sessionBackedCountForWorkspace(String workspaceId) {
    int count = 0;
    // Named bucket: tabs explicitly placed here via setActiveWorkspace.
    final named = _byWorkspace[workspaceId];
    if (named != null) {
      count += named.where((t) => !t.info.id.startsWith('local-')).length;
    }
    // Legacy / no-active-workspace bucket: check persisted session's workspaceId.
    if (workspaceId.isNotEmpty) {
      final legacy = _byWorkspace[''];
      if (legacy != null) {
        count += legacy.where(
          (t) =>
              !t.info.id.startsWith('local-') &&
              t.persistedSession?.workspaceId == workspaceId,
        ).length;
      }
    }
    return count;
  }

  int savedActiveIndexFor(String workspaceTabKey) {
    final bucket = _byWorkspace[workspaceTabKey];
    if (bucket == null || bucket.isEmpty) return 0;
    return (_savedActiveIndex[workspaceTabKey] ?? 0).clamp(0, bucket.length - 1);
  }

  List<ChatTab> tabsForWorkspace(String workspaceTabKey) =>
      List.unmodifiable(_byWorkspace[workspaceTabKey] ?? const []);

  List<ChatTabInfo> tabInfosForWorkspace(String workspaceTabKey) =>
      tabsForWorkspace(workspaceTabKey).map((t) => t.info).toList();

  List<ChatTabInfo> toInfos() => _active.map((t) => t.info).toList();

  ChatTab? activeTab(int activeTabIndex) {
    if (_active.isEmpty) return null;
    final index = activeTabIndex.clamp(0, _active.length - 1);
    return _active[index];
  }

  ChatTab? bySessionId(String id) {
    for (final tab in _active) {
      if (tab.info.id == id) return tab;
    }
    return null;
  }

  int indexOfSession(String id) => _active.indexWhere((t) => t.info.id == id);

  void append(ChatTab tab) {
    tab.workspaceId = _activeWorkspaceId;
    _active.add(tab);
  }

  ChatTab removeAt(int index) => _active.removeAt(index);

  String defaultMemberId(TeamProfile team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamProfile team) => ChatTabInfo(
    id: 'local-${team.id}',
    title: team.name,
    subtitle: 'local session',
  );

  ChatTab appendLocalTab(TeamProfile team, {required String cliTeamName}) {
    final tab = ChatTab(
      info: localSessionInfo(team),
      cliTeamName: cliTeamName,
      selectedMemberId: defaultMemberId(team),
      workspaceId: _activeWorkspaceId,
    );
    _active.add(tab);
    return tab;
  }

  (String, List<String>) workingDirectoryAndAddDirsForTab(
    ChatTab tab,
    List<AppSession> sessions, {
    List<Workspace> workspaces = const [],
  }) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in sessions) {
      if (s.sessionId != tabId) continue;
      final memberId = tab.selectedMemberId.trim();
      final workspace = workspaces
          .where((w) => w.workspaceId == s.workspaceId)
          .firstOrNull;
      final folders = workspace?.folders ?? s.folders;
      final work = s.workDirsForMember(
        memberId.isEmpty ? null : memberId,
        folders: folders,
      );
      final wd = work.workingDirectory.trim();
      final addl = work.addDirs
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (wd.isNotEmpty) {
        return (wd, addl);
      }
      return (AppStorage.cwd, addl);
    }
    return (AppStorage.cwd, const <String>[]);
  }

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }

  /// Every tab across all buckets (used on cubit close to dispose sessions).
  Iterable<ChatTab> get allTabs sync* {
    for (final bucket in _byWorkspace.values) {
      yield* bucket;
    }
  }
}
