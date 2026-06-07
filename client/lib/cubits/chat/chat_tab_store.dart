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

  /// Removes and returns a project's bucket (for disposal by the caller).
  List<ChatTab> removeProject(String projectId) {
    _savedActiveIndex.remove(projectId);
    final removed = _byProject.remove(projectId) ?? const [];
    return List<ChatTab>.of(removed);
  }

  /// Session-backed (non-`local-`) tab count for [projectId], across any bucket.
  int sessionBackedCountForProject(String projectId) {
    final bucket = _byProject[projectId];
    if (bucket == null) return 0;
    return bucket.where((t) => !t.info.id.startsWith('local-')).length;
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

  String defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamConfig team) => ChatTabInfo(
    id: 'local-${team.id}',
    title: team.name,
    subtitle: 'local session',
  );

  ChatTab appendLocalTab(TeamConfig team, {required String cliTeamName}) {
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
