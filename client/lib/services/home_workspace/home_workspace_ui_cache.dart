import '../../models/workspace_tab_ref.dart';
import 'home_open_workspaces_store.dart';
import 'workspace_display_prefs_store.dart';
import 'workspace_favorites_store.dart';

/// Small JSON prefs warmed during bootstrap so home chrome is stable on entry.
class HomeWorkspaceUiCache {
  HomeWorkspaceUiCache({
    WorkspaceFavoritesStore? favoritesStore,
    WorkspaceDisplayPrefsStore? displayPrefsStore,
    HomeOpenWorkspacesStore? openWorkspacesStore,
  })  : _favoritesStore = favoritesStore ?? WorkspaceFavoritesStore(),
        _displayPrefsStore = displayPrefsStore ?? WorkspaceDisplayPrefsStore(),
        _openWorkspacesStore =
            openWorkspacesStore ?? HomeOpenWorkspacesStore();

  final WorkspaceFavoritesStore _favoritesStore;
  final WorkspaceDisplayPrefsStore _displayPrefsStore;
  final HomeOpenWorkspacesStore _openWorkspacesStore;

  Set<String> favoriteWorkspaceIds = const {};
  WorkspaceDisplayPrefs displayPrefs = const WorkspaceDisplayPrefs();
  List<WorkspaceTabRef> openWorkspaceTabs = const [];

  Future<void> warm() async {
    final results = await Future.wait<Object>([
      _favoritesStore.load(),
      _displayPrefsStore.load(),
      _openWorkspacesStore.loadOrderedTabs(),
    ]);
    favoriteWorkspaceIds = results[0] as Set<String>;
    displayPrefs = results[1] as WorkspaceDisplayPrefs;
    openWorkspaceTabs = results[2] as List<WorkspaceTabRef>;
  }
}
