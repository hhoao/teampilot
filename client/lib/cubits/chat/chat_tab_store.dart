import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Session runtime registry. Owns the *runtime* behind each session tab, not
/// bar presence/order (that is `WorkbenchCubit`). Keyed by session id.
class ChatTabStore {
  final Map<String, ChatTab> _bySessionId = {};
  String _activeWorkspaceId = '';

  String get activeWorkspaceId => _activeWorkspaceId;

  /// Switches the foreground workspace (single simple field — per-workspace
  /// buckets are gone; runtime presence is global, keyed by session id).
  void setActiveWorkspaceId(String id) => _activeWorkspaceId = id;

  ChatTab? openTabBySessionId(String sessionId) =>
      _bySessionId[sessionId.trim()];

  Iterable<ChatTab> get openTabs => _bySessionId.values;

  List<ChatTab> tabsForWorkspace(String workspaceId) =>
      _bySessionId.values.where((t) => t.workspaceId == workspaceId).toList();

  /// Every open session runtime, globally — not scoped to the foreground
  /// workspace (bar presence/order lives in `WorkbenchCubit`).
  List<ChatTab> get activeTabs => _bySessionId.values.toList();

  bool get activeTabsIsEmpty => _bySessionId.isEmpty;

  bool get hasOpenTabs => _bySessionId.isNotEmpty;

  /// Register a staged session runtime (bar presence is handled by the bridge).
  void registerSession(ChatTab tab) {
    tab.workspaceId = _activeWorkspaceId;
    _bySessionId[tab.info.id.trim()] = tab;
  }

  /// Remove and return the runtime for [sessionId], if any.
  ChatTab? removeSession(String sessionId) =>
      _bySessionId.remove(sessionId.trim());

  /// Session ids whose runtime belongs to [workspaceId].
  List<String> sessionsForWorkspace(String workspaceId) =>
      [for (final tab in _bySessionId.values)
        if (tab.workspaceId == workspaceId) tab.info.id];

  void clear() => _bySessionId.clear();

  /// Thin back-compat helper: the foreground runtime (first open), ignoring the
  /// index. Deleted with the remaining callers.
  ChatTab? activeTab(int index) =>
      _bySessionId.isEmpty ? null : _bySessionId.values.first;

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
    registerSession(tab);
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
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return tab.persistedSession;
    // Prefer the in-memory snapshot (launchState, member bindings, native ids)
    // over a stale tab.persistedSession left at create/reopen time.
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return tab.persistedSession;
  }
}
