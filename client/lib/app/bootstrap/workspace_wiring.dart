import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/config_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/session_groups_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../models/runtime_target.dart';
import '../../repositories/extension_repository.dart';
import '../../repositories/layout_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/chat/session/session_lifecycle_service.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/floating_workspace/floating_workspace_persistence.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/run/workspace_run_platform_factory.dart';
import '../../services/search/workspace_search_indexes.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/storage/home_storage.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/workspace/workspace_run_registry.dart';
import '../../services/workspace/workspace_session_groups_registry.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';
import '../../services/workspace/workspace_worktree_registry.dart';

/// Workspace registries, stores and the layout/config cubits bound to one home
/// plane.
typedef WorkspaceWiring = ({
  LayoutCubit layoutCubit,
  FloatingWorkspaceCubit floatingWorkspaceCubit,
  FloatingWorkspacePersistence floatingWorkspacePersistence,
  WorkspaceToolsCubit workspaceToolsCubit,
  WorkspaceTerminalRegistry workspaceTerminalRegistry,
  GitRepoStore gitRepoStore,
  WorkspaceFileTreeStore workspaceFileTreeStore,
  WorkspaceSearchIndexes workspaceSearchIndexes,
  WorkspaceWorktreeRegistry workspaceWorktreeRegistry,
  WorkspaceSessionGroupsRegistry workspaceSessionGroupsRegistry,
  WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry,
  WorkspaceRunRegistry workspaceRunRegistry,
  ConfigCubit configCubit,
});

/// Builds the layout/config cubits and the workspace registries for the home
/// plane behind [storage].
///
/// [homeTarget] is the shell's home-target resolver, and [chatCubit] is a
/// getter because the session-groups factory closure reads the shell's
/// `late final` chat cubit lazily, long after this wiring has returned.
WorkspaceWiring wireWorkspaces({
  required SharedPreferences preferences,
  required HomeStorage storage,
  required ExtensionRepository extensionRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required SessionLifecycleService Function() sessionLifecycleService,
  required SshProfileRepository sshProfiles,
  required SshClientFactory sshClientFactory,
  required RuntimeTarget Function() homeTarget,
  required ChatCubit Function() chatCubit,
}) {
  final lifecycle = sessionLifecycleService();
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final floatingWorkspaceCubit = FloatingWorkspaceCubit();
  final floatingWorkspacePersistence = FloatingWorkspacePersistence(
    layout: layoutCubit,
    floating: floatingWorkspaceCubit,
  );
  final workspaceToolsCubit = WorkspaceToolsCubit(
    persist: (set) {
      unawaited(layoutCubit.setRightToolOpenSet(set));
    },
  );
  final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
  final gitRepoStore = GitRepoStore(storage: storage);
  final workspaceFileTreeStore = WorkspaceFileTreeStore();
  final workspaceSearchIndexes = WorkspaceSearchIndexes(storage: storage);
  final workspaceWorktreeRegistry = WorkspaceWorktreeRegistry(
    storage: storage,
    gitMutationSignals: gitRepoStore.headChanged,
  );
  final workspaceSessionGroupsRegistry = WorkspaceSessionGroupsRegistry(
    storage: storage,
    cubitFactory: () => SessionGroupsCubit(
      storage: storage,
      knownSessionIds: () => {
        for (final s in chatCubit().state.sessions) s.sessionId,
      },
    ),
  );
  final workspaceToolsScopeRegistry = WorkspaceToolsScopeRegistry();
  final workspaceRunRegistry = WorkspaceRunRegistry(
    storage: storage,
    platformFactory: WorkspaceRunPlatformFactory(
      storage: storage,
      extensionRepository: extensionRepository,
      projectConfigRepository: workspaceConfig,
      resolveWorkContext: lifecycle.resolveWorkContextForTargetId,
      sshProfileRepository: sshProfiles,
      sshClientFactory: sshClientFactory,
      homeTarget: homeTarget,
    ),
  );
  final configCubit = ConfigCubit();

  return (
    layoutCubit: layoutCubit,
    floatingWorkspaceCubit: floatingWorkspaceCubit,
    floatingWorkspacePersistence: floatingWorkspacePersistence,
    workspaceToolsCubit: workspaceToolsCubit,
    workspaceTerminalRegistry: workspaceTerminalRegistry,
    gitRepoStore: gitRepoStore,
    workspaceFileTreeStore: workspaceFileTreeStore,
    workspaceSearchIndexes: workspaceSearchIndexes,
    workspaceWorktreeRegistry: workspaceWorktreeRegistry,
    workspaceSessionGroupsRegistry: workspaceSessionGroupsRegistry,
    workspaceToolsScopeRegistry: workspaceToolsScopeRegistry,
    workspaceRunRegistry: workspaceRunRegistry,
    configCubit: configCubit,
  );
}
