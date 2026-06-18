import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Owns the open-tab list and all pure queries/derivations over it.
/// Never emits — callers read results and update ChatState themselves.
///
/// Tabs are bucketed by `projectId`. Every query/mutation below operates on the
/// *active* project's bucket ([setActiveProject]); callers keep using the same
/// flat-list API. Per-project active-tab index is snapshotted on project switch,
/// not mirrored on every selection, so cubit call sites stay unchanged.
class ChatTabStore {
  final Map<String, List<ChatTab>> _byProject = {};
  final Map<String, int> _savedActiveIndex = {};
  String _activeProjectId = '';

  List<ChatTab> get _active => _byProject.putIfAbsent(_activeProjectId, () => []);

  /// Switches the active bucket. Pass [currentActiveIndex] (the cubit's current
  /// `ChatState.activeTabIndex`) to snapshot the outgoing project's selection.
  /// Returns the restored active-tab index for the incoming project (clamped).
  int setActiveProject(String projectId, {int? currentActiveIndex}) {
    if (currentActiveIndex != null && _activeProjectId.isNotEmpty) {
      _savedActiveIndex[_activeProjectId] = currentActiveIndex;
    }
    _activeProjectId = projectId;
    _byProject.putIfAbsent(projectId, () => []);
    final saved = _savedActiveIndex[projectId] ?? 0;
    final len = _byProject[projectId]!.length;
    if (len == 0) return 0;
    return saved.clamp(0, len - 1);
  }

  String get activeProjectId => _activeProjectId;

  List<ChatTab> get tabs => _active;
  int get length => _active.length;
  bool get isEmpty => _active.isEmpty;

  /// Clears every bucket (used on cubit close).
  void clear() {
    _byProject.clear();
    _savedActiveIndex.clear();
  }

  /// Removes and returns all tabs belonging to [projectId] (for disposal by the
  /// caller). Clears the named bucket and also removes matching tabs from the
  /// legacy empty-string bucket (tabs added before [setActiveProject] was called).
  List<ChatTab> removeProject(String projectId) {
    _savedActiveIndex.remove(projectId);
    final removed = <ChatTab>[];
    // Named bucket.
    final named = _byProject.remove(projectId);
    if (named != null) removed.addAll(named);
    // Legacy bucket: tabs whose persisted session belongs to this project.
    if (projectId.isNotEmpty) {
      final legacy = _byProject[''];
      if (legacy != null) {
        final matching =
            legacy
                .where((t) => t.persistedSession?.projectId == projectId)
                .toList();
        if (matching.isNotEmpty) {
          legacy.removeWhere((t) => t.persistedSession?.projectId == projectId);
          removed.addAll(matching);
        }
      }
    }
    return removed;
  }

  /// Session-backed (non-`local-`) tab count for [projectId], across any bucket.
  ///
  /// Checks the named bucket first. Also scans the legacy empty-string bucket
  /// by persisted-session projectId so that tabs opened before [setActiveProject]
  /// is called (e.g. the connect flow before the UI switches project context)
  /// are counted correctly.
  int sessionBackedCountForProject(String projectId) {
    int count = 0;
    // Named bucket: tabs explicitly placed here via setActiveProject.
    final named = _byProject[projectId];
    if (named != null) {
      count += named.where((t) => !t.info.id.startsWith('local-')).length;
    }
    // Legacy / no-active-project bucket: check persisted session's projectId.
    if (projectId.isNotEmpty) {
      final legacy = _byProject[''];
      if (legacy != null) {
        count += legacy.where(
          (t) =>
              !t.info.id.startsWith('local-') &&
              t.persistedSession?.projectId == projectId,
        ).length;
      }
    }
    return count;
  }

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
    tab.projectId = _activeProjectId;
    _active.add(tab);
  }

  ChatTab removeAt(int index) => _active.removeAt(index);

  String defaultMemberId(TeamIdentity team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamIdentity team) => ChatTabInfo(
    id: 'local-${team.id}',
    title: team.name,
    subtitle: 'local session',
  );

  ChatTab appendLocalTab(TeamIdentity team, {required String cliTeamName}) {
    final tab = ChatTab(
      info: localSessionInfo(team),
      cliTeamName: cliTeamName,
      selectedMemberId: defaultMemberId(team),
      projectId: _activeProjectId,
    );
    _active.add(tab);
    return tab;
  }

  (String, List<String>) workingDirectoryAndAddDirsForTab(
    ChatTab tab,
    List<AppSession> sessions,
  ) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in sessions) {
      if (s.sessionId != tabId) continue;
      final wd = s.primaryPath.trim();
      final addl = s.additionalPaths
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
    for (final bucket in _byProject.values) {
      yield* bucket;
    }
  }
}
