import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../models/team_config.dart';
import '../../storage/home_storage.dart';
import 'chat_tab.dart';
import 'chat_tab_info.dart';

/// Session runtime registry. Owns the *runtime* behind each session tab, not
/// bar presence/order (that is `WorkbenchCubit`).
///
/// Entries are stored under [ChatTabInfo.id] — the one identifier that never
/// changes. A scratch tab starts as `local-<teamId>` and later gains a session
/// row, so session-keyed lookups ([getOpenTabBySessionId]) must also match
/// [ChatTab.sessionId].
class ChatTabStore {
  ChatTabStore({required HomeStorage storage}) : _storage = storage;

  final HomeStorage _storage;

  final Map<String, ChatTab> _byTabId = {};
  String _activeWorkspaceId = '';

  String get activeWorkspaceId => _activeWorkspaceId;

  /// Switches the foreground workspace (single simple field — per-workspace
  /// buckets are gone; runtime presence is global, keyed by session id).
  void setActiveWorkspaceId(String id) => _activeWorkspaceId = id;

  ChatTab? getOpenTabBySessionId(String sessionId) {
    final key = sessionId.trim();
    final direct = _byTabId[key];
    if (direct != null) return direct;
    // Scratch tabs are registered under `local-<teamId>`; once persisted their
    // runtime is only reachable by the real session id.
    for (final tab in _byTabId.values) {
      if (tab.sessionId == key) return tab;
    }
    return null;
  }

  Iterable<ChatTab> get openTabs => _byTabId.values;

  List<ChatTab> tabsForWorkspace(String workspaceId) =>
      _byTabId.values.where((t) => t.workspaceId == workspaceId).toList();

  /// Every open session runtime, globally — not scoped to the foreground
  /// workspace (bar presence/order lives in `WorkbenchCubit`).
  List<ChatTab> get activeTabs => _byTabId.values.toList();

  bool get activeTabsIsEmpty => _byTabId.isEmpty;

  bool get hasOpenTabs => _byTabId.isNotEmpty;

  /// Register a staged session runtime (bar presence is handled by the bridge).
  void registerSession(ChatTab tab) {
    tab.workspaceId = _activeWorkspaceId;
    _byTabId[tab.info.id.trim()] = tab;
  }

  /// Remove and return the runtime for [sessionId], if any.
  ChatTab? removeSession(String sessionId) {
    final tab = getOpenTabBySessionId(sessionId);
    if (tab == null) return null;
    _byTabId.remove(tab.info.id.trim());
    return tab;
  }

  /// Session ids whose runtime belongs to [workspaceId].
  List<String> sessionsForWorkspace(String workspaceId) => [
    for (final tab in _byTabId.values)
      if (tab.workspaceId == workspaceId) tab.sessionId,
  ];

  void clear() => _byTabId.clear();

  /// Thin back-compat helper: the foreground runtime (first open), ignoring the
  /// index. Deleted with the remaining callers.
  ChatTab? activeTab(int index) =>
      _byTabId.isEmpty ? null : _byTabId.values.first;

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
    final tabId = tab.sessionId;
    if (tabId.startsWith('local-')) {
      return (_storage.cwd, const <String>[]);
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
        usesPosixPaths: _storage.usesPosixPaths,
      );
      final wd = work.workingDirectory.trim();
      final addl = work.addDirs
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (wd.isNotEmpty) {
        return (wd, addl);
      }
      return (_storage.cwd, addl);
    }
    return (_storage.cwd, const <String>[]);
  }

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final tabId = tab.sessionId;
    if (tabId.startsWith('local-')) return tab.persistedSession;
    // Prefer the in-memory snapshot (launchState, member bindings, native ids)
    // over a stale tab.persistedSession left at create/reopen time.
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return tab.persistedSession;
  }
}
