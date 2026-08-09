import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../cubits/app_bootstrap_cubit.dart';
import 'app_data_bootstrap.dart';
import '../cubits/app_provider_cubit.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/remote_download_catalog_cubit.dart';
import '../cubits/automation_cubit.dart';
import '../cubits/agent_attention_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../services/agent_status/agent_status_http_handler.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/agent_status/ask_user_answer_pending_store.dart';
import '../services/agent_status/ask_user_question_hook_gate.dart';
import '../services/agent_status/exit_plan_mode_hook_gate.dart';
import '../services/terminal/ask_user_question_answer_service.dart';
import '../services/terminal/exit_plan_mode_approval_service.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/remote/local_credential_exporter.dart';
import '../services/remote/remote_cli_readiness.dart';
import '../widgets/app_toast/app_toast.dart';
import '../services/editor_platform/editor_platform.dart';
import '../services/launch/launch_factory.dart';
import '../cubits/board_cubit.dart';
import '../utils/session/workspace_tab_session_scope.dart';
import '../cubits/mailbox_cubit.dart';
import '../cubits/member_presence_cubit.dart';
import '../cubits/notification_cubit.dart';
import '../cubits/progress_activity_cubit.dart';
import '../services/app/app_update_service.dart';
import '../services/progress_activity/app_update_activity_adapter.dart';
import '../services/progress_activity/hub_clone_activity_adapter.dart';
import '../services/remote_download/remote_download_http.dart';
import '../services/remote_download/remote_download_resolver.dart';
import '../services/remote_download/remote_downloader.dart';
import '../services/progress_activity/pack_acquire_activity_adapter.dart';
import '../services/progress_activity/cli_provision_activity_adapter.dart';
import '../cubits/ai_history_cubit.dart';
import '../cubits/shortcut_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workbench/workbench_shell_launcher.dart';
import '../services/workbench/workbench_strip_navigator.dart';
import '../services/editor/markdown_view_mode_store.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/session_history_context_builder.dart';
import '../cubits/ai_feature_settings_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../models/layout_preferences.dart';
import '../cubits/workspace_tools_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../models/session_preferences.dart';
import '../cubits/extension_cubit.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../repositories/launch_profile_repository.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../cubits/cli_presets_cubit.dart';
import '../repositories/cli_presets_repository.dart';
import '../cubits/skill_cubit.dart';
import '../repositories/mcp_repository.dart';
import '../services/mcp/profile_mcp_linker_service.dart';
import '../cubits/ssh_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/termux_cubit.dart';
import '../cubits/github_account_cubit.dart';
import '../config/github_oauth_config.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/team_hub_cubit.dart';
import '../cubits/expert_hub_cubit.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../services/app/boot_splash.dart';
import '../utils/ui/yield_ui_frame.dart';
import '../l10n/app_localizations.dart';
import '../pages/system/app_bootstrap_loading_page.dart';
import '../pages/system/bootstrap_startup_error_page.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/layout_repository.dart';
import '../repositories/session_preferences_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/automation_repository.dart';
import '../repositories/plugin_repository.dart';
import '../repositories/skill_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/extension_repository.dart';
import '../repositories/workspace_project_config_repository.dart';
import '../router/app_router.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/device_local_control_plane.dart';
import '../services/perf/live_perf_driver.dart';
import '../services/storage/workspace_layout.dart';
import '../services/automation/automation_bus_gateway.dart';
import '../services/automation/automation_dispatcher.dart';
import '../services/automation/automation_schedule_calculator.dart';
import '../services/automation/automation_scheduler.dart';
import '../services/launch/session_runtime_plan_builder.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/team/team_clone_service.dart';
import '../services/team_hub/composite_team_hub_source.dart';
import '../services/team_hub/git_registry_team_hub_source.dart';
import '../services/team_hub/team_hub_favorites_store.dart';
import '../services/expert_hub/composite_expert_hub_source.dart';
import '../services/expert_hub/expert_capability_resolver.dart';
import '../services/expert_hub/expert_clone_service.dart';
import '../services/expert_hub/local_expert_store.dart';
import '../services/expert_hub/expert_hub_favorites_store.dart';
import '../services/expert_hub/git_registry_expert_hub_source.dart';
import '../services/expert_hub/member_roster_service.dart';
import '../services/cli/cli_executable_discovery.dart';
import '../services/cli/toolchain_executable_discovery.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/layout_command_registrar.dart';
import '../services/commands/run_command_registrar.dart';
import '../services/commands/session_command_registrar.dart';
import '../services/commands/shortcuts_ui_commands.dart';
import '../services/commands/workspace_search_command_registrar.dart';
import '../services/floating_workspace/floating_maximize_insets.dart';
import '../services/floating_workspace/floating_surface_registry.dart';
import '../services/floating_workspace/floating_workspace_commands.dart';
import '../services/floating_workspace/floating_workspace_open_file.dart';
import '../services/floating_workspace/floating_workspace_persistence.dart';
import '../services/floating_workspace/migrate_legacy_workbench_tabs.dart';
import '../services/floating_workspace/surfaces/diff_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/file_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/run_floating_surface.dart';
import '../services/floating_workspace/surfaces/terminal_floating_surface.dart';
import '../pages/home_workspace/workspace_chrome_commands.dart';
import '../services/cli/registry/cli_bootstrap.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/cli/claude/claude_bootstrap_entry.dart';
import '../services/cli/codex/codex_bootstrap_entry.dart';
import '../services/cli/cursor/cursor_bootstrap_entry.dart';
import '../services/cli/opencode/opencode_bootstrap_entry.dart';
import '../services/host/host_one_shot_runner_for_context.dart';
import '../services/host/host_process_starter_for_context.dart';
import '../services/cli/claude/provider/claude_provider_credentials_service.dart';
import '../services/cli/codex/provider/codex_provider_credentials_service.dart';
import '../services/cli/opencode/provider/opencode_provider_credentials_service.dart';
import '../services/cli/opencode/provider/opencode_models_service.dart';
import '../services/cli/cursor/provider/cursor_agent_models_service.dart';
import '../services/cli/cursor/provider/cursor_provider_credentials_service.dart';
import '../services/provider/provider_credential_host_runner.dart';
import '../services/app/connection_mode_service.dart';
import '../services/cli/remote_cli_locator.dart';
import '../services/storage/runtime_context_resolver.dart';
import '../services/storage/runtime_context_registry.dart';
import '../services/storage/home_storage_invalidator.dart';
import '../services/storage/home_target_controller.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../services/storage/home_target_store.dart';
import '../services/storage/runtime_target_registry.dart';
import '../services/termux/termux_config.dart';
import '../services/termux/termux_transport_profile.dart';
import '../services/termux/termux_work_ops_message.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/notification/notification_recorder.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/skill/skill_acquisition_engine.dart';
import '../services/skill/skill_fetch_service.dart';
import '../services/plugin/marketplace_shared_store.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/skill/skill_install_service.dart';
import '../services/skill/skill_manifest_service.dart';
import '../services/skill/skill_repo_disk_cache_service.dart';
import '../services/skill/skill_repo_git_service.dart';
import '../services/skill/skill_repo_service.dart';
import '../services/storage/runtime_context.dart';
import '../services/github/github_credentials_store.dart';
import '../services/github/github_device_flow_auth.dart';
import '../services/hub_publish/http_github_api_client.dart';
import '../services/ssh/ssh_client_factory.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ssh/ssh_connection_events.dart';
import '../widgets/ssh/ssh_host_key_prompt_dialog.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/ssh/ssh_transport_close.dart';
import '../services/ssh/android_ssh_connect_home.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_command_runner.dart';
import '../services/git/git_repo_store.dart';
import '../services/workspace/workspace_tools_scope_registry.dart';
import '../services/workspace/workspace_run_registry.dart';
import '../services/run/workspace_run_platform_factory.dart';
import '../services/search/workspace_search_indexes.dart';
import '../services/workspace/workspace_worktree_registry.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/terminal/workspace_terminal_connect_coordinator.dart';
import '../services/terminal/workspace_terminal_run_service.dart';
import '../services/terminal/workspace_terminal_session_ops.dart';
import 'package:logger/logger.dart';
import '../utils/logging/logger.dart';
import 'ui_zoom_baseline.dart';

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.homeTargetController,
    required this.directoryPicker,
    required this.chatCubit,
    required this.memberPresenceCubit,
    required this.agentAttentionCubit,
    required this.agentStatusSeatLookup,
    required this.mailboxCubit,
    required this.boardCubit,
    required this.aiHistoryCubit,
    required this.notificationCubit,
    required this.progressActivityCubit,
    required this.editorCubit,
    required this.workbenchCubit,
    required this.workbenchEditorOpener,
    required this.workbenchShellLauncher,
    required this.floatingWorkspaceCubit,
    required this.floatingSurfaceRegistry,
    required this.floatingMaximizeInsets,
    required this.sessionRepo,
    required this.workspaceProjectConfigRepository,
    required this.sshProfileRepo,
    required this.sshCredentialStore,
    required this.sshKnownHostRepo,
    required this.transportFactory,
    required this.workspaceTerminalRegistry,
    required this.workspaceShellConnector,
    required this.workspaceTerminalSessionOps,
    required this.workspaceTerminalRunService,
    required this.gitRepoStore,
    required this.workspaceFileTreeStore,
    required this.workspaceSearchIndexes,
    required this.workspaceWorktreeRegistry,
    required this.workspaceToolsScopeRegistry,
    required this.workspaceRunRegistry,
    required this.sshClientFactory,
    required this.sshProfileConnectionCoordinator,
    required this.connectionModeService,
    required this.identityRepository,
    required this.teamCubit,
    required this.configCubit,
    required this.appProviderCubit,
    required this.llmConfigCubit,
    required this.layoutCubit,
    required this.workspaceToolsCubit,
    required this.sessionPreferencesCubit,
    required this.pluginCubit,
    required this.cliPresetsCubit,
    required this.skillCubit,
    required this.mcpCubit,
    required this.teamHubCubit,
    required this.expertHubCubit,
    required this.expertCapabilityResolver,
    required this.extensionCubit,
    required this.appUpdateCubit,
    required this.remoteDownloadCatalogCubit,
    required this.sshProfileCubit,
    required this.termuxCubit,
    required this.homeStorageInvalidator,
    required this.sshConnectionCubit,
    required this.githubCredentialsStore,
    required this.githubAccountCubit,
    required this.appSettings,
    required this.aiFeatureSettingsCubit,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.cliToolRegistry,
    required this.homeWorkspaceUiCache,
    required this.automationCubit,
    required this.automationScheduler,
    required this.commandBus,
    required this.shortcutCubit,
    required this.workspaceChromeCommands,
    required this.runCommandHost,
    required this.workspaceSearchHost,
    required this.uiZoomBaseline,
  });

  final CliToolRegistry cliToolRegistry;
  final HomeWorkspaceUiCache homeWorkspaceUiCache;
  final HomeTargetController homeTargetController;
  final WorkspaceDirectoryPicker directoryPicker;
  final ChatCubit chatCubit;
  final MemberPresenceCubit memberPresenceCubit;
  final AgentAttentionCubit agentAttentionCubit;
  final AgentStatusSeatLookup agentStatusSeatLookup;
  final MailboxCubit mailboxCubit;
  final BoardCubit boardCubit;
  final AiHistoryCubit aiHistoryCubit;
  final NotificationCubit notificationCubit;
  final ProgressActivityCubit progressActivityCubit;
  final EditorCubit editorCubit;
  final WorkbenchCubit workbenchCubit;
  final WorkbenchEditorOpener workbenchEditorOpener;
  final WorkbenchShellLauncher workbenchShellLauncher;
  final FloatingWorkspaceCubit floatingWorkspaceCubit;
  final FloatingSurfaceRegistry floatingSurfaceRegistry;
  final FloatingMaximizeInsets floatingMaximizeInsets;
  final SessionRepository sessionRepo;
  final WorkspaceProjectConfigRepository workspaceProjectConfigRepository;
  final SshProfileRepository sshProfileRepo;
  final SshCredentialStore sshCredentialStore;
  final SshKnownHostRepository sshKnownHostRepo;
  final TerminalTransportFactory transportFactory;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final WorkspaceShellConnector workspaceShellConnector;
  final WorkspaceTerminalSessionOps workspaceTerminalSessionOps;
  final WorkspaceTerminalRunService workspaceTerminalRunService;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceSearchIndexes workspaceSearchIndexes;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final WorkspaceRunRegistry workspaceRunRegistry;
  final SshClientFactory sshClientFactory;
  final SshProfileConnectionCoordinator sshProfileConnectionCoordinator;
  final ConnectionModeService connectionModeService;
  final LaunchProfileRepository identityRepository;
  final LaunchProfileCubit teamCubit;
  final ConfigCubit configCubit;
  final AppProviderCubit appProviderCubit;
  final LlmConfigCubit llmConfigCubit;
  final LayoutCubit layoutCubit;
  final WorkspaceToolsCubit workspaceToolsCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final PluginCubit pluginCubit;
  final CliPresetsCubit cliPresetsCubit;
  final SkillCubit skillCubit;
  final McpCubit mcpCubit;
  final TeamHubCubit teamHubCubit;
  final ExpertHubCubit expertHubCubit;
  final ExpertCapabilityResolver expertCapabilityResolver;
  final ExtensionCubit extensionCubit;
  final AppUpdateCubit appUpdateCubit;
  final RemoteDownloadCatalogCubit remoteDownloadCatalogCubit;
  final SshProfileCubit sshProfileCubit;
  final TermuxCubit termuxCubit;
  final HomeStorageInvalidator homeStorageInvalidator;
  final SshConnectionCubit sshConnectionCubit;
  final GithubCredentialsStore githubCredentialsStore;
  final GithubAccountCubit githubAccountCubit;
  final AppSettingsRepository appSettings;
  final AiFeatureSettingsCubit aiFeatureSettingsCubit;
  final Future<void> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;
  final AutomationCubit automationCubit;
  final AutomationScheduler automationScheduler;
  final CommandBus commandBus;
  final ShortcutCubit shortcutCubit;
  final WorkspaceChromeCommands workspaceChromeCommands;
  final RunCommandHost runCommandHost;
  final WorkspaceSearchHost workspaceSearchHost;
  final UiZoomBaseline uiZoomBaseline;
}

Future<AppShell> buildAppShell({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
  Future<String>? defaultWorkspaceDirectoryFuture,
  Future<void>? homeIndexPrefetchFuture,
  AppBootstrapCubit? bootstrapCubit,
}) async {
  final bootSw = Stopwatch()..start();
  void boot(String phase) =>
      appLogger.i('[boot] +${bootSw.elapsedMilliseconds}ms $phase');

  boot('start');
  final documentsFuture =
      defaultWorkspaceDirectoryFuture ??
      DefaultWorkspaceDirectory.resolve(preferences: preferences);
  final cliToolRegistry = CliToolRegistry.builtIn();
  final cliExecutableDiscovery = CliExecutableDiscovery(
    registry: cliToolRegistry,
  );

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final aiFeatureSettingsCubit = AiFeatureSettingsCubit(
    repository: appSettings,
  );
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    cliToolRegistry: cliToolRegistry,
  );
  if (!Platform.isAndroid) {
    boot('scheduling CLI tool discovery (background)');
    unawaited(() async {
      final cliPaths = await cliExecutableDiscovery.locateLocal();
      final toolchainPaths = await ToolchainExecutableDiscovery().locateLocal();
      sessionPreferencesCubit.mergeLocatedExecutables(cliPaths);
      sessionPreferencesCubit.mergeLocatedToolchains(toolchainPaths);
      appLogger.i(
        '[boot] CLI/toolchain discovery complete '
        '(${cliPaths.length} CLI, ${toolchainPaths.length} toolchain, background)',
      );
    }());
  }
  boot('loading session preferences and workspace directory');
  final parallel = await Future.wait<Object?>([
    sessionPreferencesCubit.load(),
    documentsFuture,
  ]);
  final defaultWorkspaceDirectory = parallel[1]! as String;
  boot('session preferences and workspace directory ready');

  configuredGitExecutable = () {
    final path = sessionPreferencesCubit.toolchainPath(
      SessionPreferences.toolchainGit,
    );
    return path.isEmpty ? null : path;
  };

  final sshCredentialStore = const SecureSshCredentialStore(
    FlutterSecureKeyValueStore(),
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshConnectionEvents = SshConnectionEvents();
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    events: sshConnectionEvents,
    onHostKeyPrompt: showSshHostKeyPrompt,
  );

  // P1: the home target (the machine the control plane runs on) is the single
  // authority, stored device-local in HomeTargetStore. distro/profile are
  // encoded in the id; there is no connectionMode/windowsStorageBackend knob.
  final homeTargetStore = HomeTargetStore(preferences);
  RuntimeTarget homeTargetFromId(String id) => switch (runtimeKindOfId(id)) {
    RuntimeKind.ssh => RuntimeTarget.ssh(
      sshProfileIdOfId(id) ?? '',
      label: 'SSH',
    ),
    RuntimeKind.termux => RuntimeTarget.termux(),
    RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(id) ?? ''),
    RuntimeKind.local => RuntimeTarget.local(),
  };
  // Stored id wins; otherwise platform default. Desktop home is always local
  // (Windows can pick wsl in the picker); Android with no stored ssh home falls
  // to local and is held at the create-profile gate until a home is chosen.
  var homeTarget = homeTargetFromId(homeTargetStore.load());
  RuntimeTarget defaultTargetResolver() => homeTarget;

  // SSH catalog + targets.json are device-local control plane: they must not
  // follow AppStorage home (Android Connect rebinds home onto SSH and would
  // otherwise reload an empty remote catalog → disconnect → gate again).
  final sshProfileRepo = deviceLocalSshProfileRepository(nativeAppDataPath);
  Future<Map<CliTool, String>> locateRemoteClis(SshProfile profile) async {
    try {
      final client = await sshClientFactory.clientForStorage(profile);
      return cliExecutableDiscovery.locateRemote(
        run: RemoteCliLocator.runnerForClient(client),
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[remote-cli] locate failed for ${profile.hostIdentifier}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }

  late final LlmConfigCubit llmConfigCubit;
  late final AppProviderCubit appProviderCubit;
  late final LaunchProfileCubit teamCubit;
  late final PluginCubit pluginCubit;
  late final LaunchProfileRepository identityRepository;
  late final LaunchProfileProvisioner identityProvisioner;
  late final CliPresetsCubit cliPresetsCubit;
  late final SkillCubit skillCubit;
  late final McpCubit mcpCubit;
  late final TeamHubCubit teamHubCubit;
  late final ExpertHubCubit expertHubCubit;
  late final ExtensionCubit extensionCubit;
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  late final MemberPresenceCubit memberPresenceCubit;
  late final AutomationCubit automationCubit;
  late final AutomationScheduler automationScheduler;
  late final EditorCubit editorCubit;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<void> Function() reinstallStorageContext;

  late final Future<void> Function({bool reinstallSshHome}) reloadAllAppData;

  late final SshProfileCubit sshProfileCubit;
  late final HomeTargetController homeTargetController;
  final homeWorkspaceUiCache = HomeWorkspaceUiCache();
  sshProfileCubit = SshProfileCubit(
    profileRepository: sshProfileRepo,
    credentialStore: sshCredentialStore,
    locateRemoteCliPaths: locateRemoteClis,
    onRemoteCliLocated: (cli, path) =>
        sessionPreferencesCubit.setCliExecutablePathFor(cli, path),
    invalidateProfileConnection: (id) => sshClientFactory.disconnectProfile(
      id,
      reason: SshTransportCloseReason.profileInvalidated,
    ),
    enableRemoteCliDiscovery: () =>
        Platform.isAndroid && defaultTargetResolver().kind == RuntimeKind.ssh,
  );

  final githubCredentialsStore = GithubCredentialsStore(
    kv: const FlutterSecureKeyValueStore(),
  );
  final githubDeviceFlow = githubDeviceFlowAvailable
      ? GithubDeviceFlowAuth(clientId: githubOauthClientId)
      : null;
  final githubAccountCubit = GithubAccountCubit(
    store: githubCredentialsStore,
    deviceFlow: githubDeviceFlow,
    openUrl: (uri) async {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('Could not launch $uri');
    },
    fetchLogin: (token) async {
      final user = await HttpGithubApiClient().getAuthenticatedUser(
        token: token,
      );
      return user.login;
    },
    deviceFlowAvailable: githubDeviceFlowAvailable,
  );
  unawaited(githubAccountCubit.hydrate());

  // P1: targets.json is a pure target catalog (no default/migrate); the home
  // target authority is the device-local homeTargetStore read above. The
  // registry is used by the picker UI to list selectable targets.
  final targetsRepo = deviceLocalTargetsRepository(nativeAppDataPath);
  final termuxConfigStore = deviceLocalTermuxConfigStore(nativeAppDataPath);
  final remoteDownloadSettingsStore =
      deviceLocalRemoteDownloadSettingsStore(nativeAppDataPath);
  final remoteDownloadCatalogCubit = RemoteDownloadCatalogCubit(
    store: remoteDownloadSettingsStore,
  );
  unawaited(remoteDownloadCatalogCubit.load());
  var termuxConfigCache = await termuxConfigStore.load();
  TermuxCubit? termuxGateCubit;
  SshProfile? homeSshProfileCache;
  if (homeTarget.kind == RuntimeKind.ssh) {
    final pid = homeTarget.sshProfileId;
    if (pid != null && pid.isNotEmpty) {
      homeSshProfileCache = await sshProfileRepo.findById(pid);
    }
  }
  SshProfile? sshProfileById(String id) {
    if (id == 'termux') {
      final cfg = termuxConfigCache;
      return cfg == null ? null : termuxTransportProfile(cfg);
    }
    final fromCubit = sshProfileCubit.state.profiles
        .where((p) => p.id == id)
        .firstOrNull;
    if (fromCubit != null) return fromCubit;
    final cached = homeSshProfileCache;
    if (cached != null && cached.id == id) {
      return cached;
    }
    return null;
  }
  final remoteCliReadiness = RemoteCliReadinessService(
    registry: cliToolRegistry,
    sshClientFactory: sshClientFactory,
    profileById: sshProfileById,
    cliPathOverride: targetsRepo.cliPathOverride,
    setCliPathOverride: targetsRepo.setCliPathOverride,
  );
  final runtimeTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
    hasTermuxConfig: () => termuxConfigCache != null,
  );

  // P2: de-singleton. One resolver + a per-target context registry. The home
  // context (control plane) is materialized once and pushed onto AppStorage;
  // work-plane contexts are resolved lazily per workspace target id.
  final runtimeContextResolver = RuntimeContextResolver(
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  // Late holder: registry is created before AiHistoryLoader; onEvict clears
  // history memory cache when a work-plane target is disposed.
  AiHistoryLoader? aiHistoryLoaderRef;
  final runtimeContextRegistry = RuntimeContextRegistry(
    resolver: runtimeContextResolver,
    homeTarget: defaultTargetResolver(),
    sshProfileById: sshProfileById,
    termuxPathCache: () {
      final cfg = termuxConfigCache;
      if (cfg == null) {
        return (home: null, appDataRoot: null);
      }
      return (home: cfg.lastHome, appDataRoot: cfg.lastAppDataRoot);
    },
    onEvict: (targetId) async {
      final pid =
          homeTargetFromId(targetId).sshProfileId ??
          sshProfileIdOfId(targetId);
      if (pid != null) {
        sshClientFactory.disconnectProfile(
          pid,
          reason: SshTransportCloseReason.runtimeContextEvicted,
        );
      }
      // v1: clear all history memory cache on work-plane drop.
      aiHistoryLoaderRef?.clearCache();
    },
  );
  boot('installing home runtime context');
  final ensureHomeSw = Stopwatch()..start();
  await runtimeContextRegistry.ensureHome();
  boot('home runtime context ensured +${ensureHomeSw.elapsedMilliseconds}ms');
  final homeCtx = runtimeContextRegistry.home();
  final cfg = termuxConfigCache;
  if (homeTarget.kind == RuntimeKind.termux &&
      cfg != null &&
      !homeCtx.pathsFromCache) {
    final updated = cfg.copyWith(
      lastHome: homeCtx.home,
      lastAppDataRoot: homeCtx.appDataRoot,
    );
    termuxConfigCache = updated;
    await termuxConfigStore.save(updated);
  }
  AppStorage.bindHome(homeCtx);
  boot(
    'home context installed '
    '(${AppStorage.context.mode}, home=${homeTarget.id}, '
    'root=${AppStorage.appDataRoot})',
  );

  Future<void> persistSshHomePathCacheIfLive() async {
    final home = defaultTargetResolver();
    if (home.kind != RuntimeKind.ssh) return;
    final pid = home.sshProfileId;
    if (pid == null || pid.isEmpty) return;
    final ctx = runtimeContextRegistry.home();
    if (ctx.pathsFromCache) return;
    if (!sshProfileCubit.state.profiles.any((p) => p.id == pid)) {
      await sshProfileCubit.load();
    }
    await sshProfileCubit.updatePathCache(
      pid,
      home: ctx.home,
      appDataRoot: ctx.appDataRoot,
    );
  }

  // Persists the chosen home id, rebinds the registry home, and republishes it
  // on AppStorage.
  Future<void> setHomeTarget(String id) async {
    await homeTargetStore.save(id);
    homeTarget = homeTargetFromId(id);
    await runtimeContextRegistry.dispose(id);
    await runtimeContextRegistry.rebindHome(homeTarget);
    AppStorage.bindHome(runtimeContextRegistry.home());
    await persistSshHomePathCacheIfLive();
  }

  connectionModeService = ConnectionModeService(
    defaultTargetResolver: defaultTargetResolver,
    hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
  );

  // Re-resolve the home context (e.g. after an ssh profile's details change):
  // drop the cached wrapper and rebuild it, but keep the live SSH storage pool.
  reinstallStorageContext = () async {
    await runtimeContextRegistry.dispose(
      defaultTargetResolver().id,
      notifyEvict: false,
    );
    await runtimeContextRegistry.rebindHome(defaultTargetResolver());
    AppStorage.bindHome(runtimeContextRegistry.home());
    await persistSshHomePathCacheIfLive();
  };

  Future<void> openCredentialLoginUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void onCredentialLoginHint(String message) {
    AppToast.showGlobal(message: message);
  }

  final credentialHostRunner = ProviderCredentialHostRunner(
    oneShot: () => hostOneShotRunnerForContext(AppStorage.context),
    streaming: () => hostProcessStarterForContext(AppStorage.context),
    openUrl: openCredentialLoginUrl,
    onLoginHint: onCredentialLoginHint,
  );

  final claudeCredentialsService = ClaudeProviderCredentialsService(
    fs: AppStorage.fs,
    basePath: AppStorage.paths.basePath,
    resolveClaudeExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.claude),
    hostRunner: credentialHostRunner,
  );
  final cursorCredentialsService = CursorProviderCredentialsService(
    fs: AppStorage.fs,
    basePath: AppStorage.paths.basePath,
    resolveCursorExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.cursor),
    hostRunner: credentialHostRunner,
  );
  final codexCredentialsService = CodexProviderCredentialsService(
    fs: AppStorage.fs,
    basePath: AppStorage.paths.basePath,
    resolveCodexExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.codex),
    hostRunner: credentialHostRunner,
  );
  final opencodeCredentialsService = OpencodeProviderCredentialsService(
    fs: AppStorage.fs,
    basePath: AppStorage.paths.basePath,
    resolveOpencodeExecutable: () =>
        sessionPreferencesCubit.resolveExecutable(CliTool.opencode),
    hostRunner: credentialHostRunner,
  );

  cliToolRegistry.configure(
    CliBootstrap({
      CliTool.claude: ClaudeBootstrapEntry(
        credentialsService: claudeCredentialsService,
      ),
      CliTool.cursor: CursorBootstrapEntry(
        credentialsService: cursorCredentialsService,
        agentModelsService: CursorAgentModelsService(),
      ),
      CliTool.codex: CodexBootstrapEntry(
        credentialsService: codexCredentialsService,
      ),
      CliTool.opencode: OpencodeBootstrapEntry(
        credentialsService: opencodeCredentialsService,
        modelsService: OpencodeModelsService(),
      ),
    }),
  );

  final skillManifest = SkillManifestService();
  final skillGit = SkillRepoGitService();
  final skillFetch = SkillFetchService(git: skillGit);
  final skillRepoCache = SkillRepoDiskCacheService(fetch: skillFetch);
  final skillInstallService = SkillInstallService(
    manifest: skillManifest,
    fetch: skillFetch,
    repoCache: skillRepoCache,
  );
  final skillRepo = SkillRepository(
    manifest: skillManifest,
    fetch: skillFetch,
    repoCache: skillRepoCache,
    install: skillInstallService,
    repos: SkillRepoService(),
  );
  final skillAcquisitionEngine = SkillAcquisitionEngine(
    installGitDir: (d, {bool overwrite = false, String? idOverride}) =>
        skillInstallService.installFromDiscovery(
          d,
          overwrite: overwrite,
          idOverride: idOverride,
        ),
    registerDirectory: ({required String id, required String directory}) =>
        skillInstallService.registerInstalledDirectory(
          id: id,
          directory: directory,
        ),
    isLocalAcquireSupported: () =>
        AppStorage.context.mode == StorageBackendMode.native,
    repoCache: skillRepoCache,
  );

  appProviderCubit = AppProviderCubit(
    flashskyaiExecutablePath: sessionPreferencesCubit.resolveExecutable,
  );

  llmConfigCubit = LlmConfigCubit(
    appSettings: appSettings,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    isSshMode: () => connectionModeService.isSshMode,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshClientFactory: sshClientFactory,
    sshWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
  );

  String? llmConfigPathOverrideForLaunch() {
    final s = llmConfigCubit.state;
    final path = s.effectiveConfigPath.trim();
    if (path.isEmpty) return null;
    if (connectionModeService.isSshMode) return path;
    return s.isUsingCustomPath ? path : null;
  }

  final extensionRepository = ExtensionRepository(
    fs: AppStorage.fs,
    stateFilePath: AppStorage.paths.extensionsStateJson,
    manifests: builtInExtensionManifests(),
  );
  final workspaceProjectConfigRepository = WorkspaceProjectConfigRepository(
    fs: AppStorage.fs,
  );

  identityRepository = LaunchProfileRepository();

  final cliPresetsRepo = CliPresetsRepository(
    fs: AppStorage.fs,
    presetsPath: AppStorage.paths.cliPresetsJson,
  );
  sessionLifecycleService = SessionLifecycleService(
    storageRootsResolver: () async => AppStorage.context,
    catalogContextResolver: () async => runtimeContextRegistry.home(),
    homeTarget: defaultTargetResolver,
    // P2: launch resolves the work-plane on the workspace's target machine.
    workContextResolver: runtimeContextRegistry.forTarget,
    loadEnabledExtensionIds: ({teamId, workspaceId}) async {
      final trimmedTeamId = teamId?.trim() ?? '';
      if (trimmedTeamId.isNotEmpty) {
        return extensionRepository.effectiveEnabledIds(trimmedTeamId);
      }
      final trimmedWorkspaceId = workspaceId?.trim() ?? '';
      if (trimmedWorkspaceId.isNotEmpty) {
        final config = await workspaceProjectConfigRepository.load(
          trimmedWorkspaceId,
        );
        final global = (await extensionRepository.load()).globalEnabled;
        return {
          for (final manifest in builtInExtensionManifests())
            if (config.effectiveExtensionEnabled(
              extensionId: manifest.id,
              globalEnabled: global,
            ))
              manifest.id,
        };
      }
      return (await extensionRepository.load(forceReload: true)).globalEnabled;
    },
    cliToolRegistry: cliToolRegistry,
    identityRepository: identityRepository,
    loadInstalledSkills: () => skillRepo.loadInstalled(),
    cliPresetsRepository: cliPresetsRepo,
    loadPresets: () => cliPresetsCubit.state.presets,
    projectConfigRepository: workspaceProjectConfigRepository,
  );
  sessionRepo = SessionRepository(lifecycleService: sessionLifecycleService);
  boot('prefetching home index snapshots');
  bootstrapCubit?.beginHomeIndex();
  Future<void> prefetchHomeIndex() async {
    try {
      await Future.wait([
        sessionRepo.loadWorkspacesIndex(),
        identityRepository.loadAll(),
      ]);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[boot] home index prefetch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  final homeIndexPrefetch =
      homeIndexPrefetchFuture ??
      (connectionModeService.isRemoteWorkPlane
          ? prefetchHomeIndex()
          : Future.wait([
              sessionRepo.loadWorkspacesIndex(),
              identityRepository.loadAll(),
            ]));
  final pluginRepository = PluginRepository();
  final mcpRepository = McpRepository();
  identityProvisioner = LaunchProfileProvisioner(
    repository: identityRepository,
  );
  teamCubit = LaunchProfileCubit(
    repository: identityRepository,
    sessionRepository: sessionRepo,
    identityProvisioner: identityProvisioner,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    storageRootsResolver: () async => AppStorage.context,
    lifecycleService: sessionLifecycleService,
    pluginRepository: pluginRepository,
    installedPluginsLoader: () => pluginRepository.loadAll(),
    mcpLinker: ProfileMcpLinkerService(),
    mcpRepository: mcpRepository,
    installedMcpLoader: () => mcpRepository.loadAll(),
    extensionMcpContributor: (teamId) async {
      final enabled = await extensionRepository.effectiveEnabledIds(teamId);
      final provisioner = ExtensionProvisioner(
        manifests: builtInExtensionManifests(),
        isEnabled: (id) async => enabled.contains(id),
      );
      return provisioner.collectMcpContributions();
    },
  );

  final notificationCubit = NotificationCubit();
  final notificationBootstrap = notificationCubit.load();
  NotificationRecorder.install(notificationCubit);
  final progressActivityCubit = ProgressActivityCubit(
    historyRecorder: notificationCubit,
  );
  final hubCloneActivityAdapter = HubCloneActivityAdapter(
    cubit: progressActivityCubit,
  );
  final packAcquireActivityAdapter = PackAcquireActivityAdapter(
    cubit: progressActivityCubit,
  );
  final cliProvisionActivityAdapter = CliProvisionActivityAdapter(
    cubit: progressActivityCubit,
  );

  skillCubit = SkillCubit(
    skillRepo,
    acquisitionEngine: skillAcquisitionEngine,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
    packAcquireActivity: packAcquireActivityAdapter,
  );
  pluginCubit = PluginCubit(
    repository: pluginRepository,
    installService: pluginRepository.install,
    repoService: pluginRepository.repos,
    diskCache: PluginRepoDiskCacheService(),
    onPluginUninstalled: teamCubit.removePluginFromAllTeams,
    onPluginUpdated: teamCubit.syncTeamsUsingPlugin,
    packAcquireActivity: packAcquireActivityAdapter,
  );
  extensionCubit = ExtensionCubit(
    extensionRepository,
    ExtensionAcquisitionEngine(),
    packAcquireActivity: packAcquireActivityAdapter,
  );
  cliPresetsCubit = CliPresetsCubit(repository: cliPresetsRepo);
  mcpCubit = McpCubit(
    mcpRepository,
    onMcpDeleted: teamCubit.removeMcpFromAllTeams,
  );

  final teamHubSource = CompositeTeamHubSource.withDefaults(
    GitRegistryTeamHubSource(),
  );
  final teamHubFavorites = TeamHubFavoritesStore();
  final localExpertStore = LocalExpertStore();
  await localExpertStore.migrateLegacyLayout();
  await localExpertStore.ensureIndexLoaded();
  final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
    registry: GitRegistryExpertHubSource(),
    teamIndex: teamHubSource.fetchTeams,
    localStore: localExpertStore,
  );
  final expertCloneService = ExpertCloneService(
    source: compositeExpertHubSource,
    store: localExpertStore,
  );
  final teamCloneService = TeamCloneService(
    installSkill: skillCubit.installTeamDependency,
    installPlugin: pluginCubit.installTeamDependency,
    installMcp: mcpCubit.installTeamDependency,
    expertCloner: expertCloneService.clone,
    createTeam:
        ({
          required name,
          required cli,
          required teamMode,
          required roster,
          required skillIds,
          required pluginIds,
          required mcpServerIds,
          required description,
          required extraArgs,
          hubSourceKey,
        }) => teamCubit.addClonedTeam(
          name: name,
          cli: cli,
          teamMode: teamMode,
          roster: roster,
          skillIds: skillIds,
          pluginIds: pluginIds,
          mcpServerIds: mcpServerIds,
          description: description,
          extraArgs: extraArgs,
          hubSourceKey: hubSourceKey,
        ),
  );
  teamHubCubit = TeamHubCubit(
    source: teamHubSource,
    loadFavorites: teamHubFavorites.load,
    saveFavoriteToggle: teamHubFavorites.toggle,
    cloneTeam: (team, {teamMode, cli}) => hubCloneActivityAdapter.runTracked(
      title: 'Clone ${team.name}',
      historyMessageFor: (result) => result.hasFailures
          ? 'Cloned ${team.name} with ${result.failedDeps.length} dependency failures'
          : 'Cloned ${team.name}',
      run: (onProgress) => teamCloneService.clone(
        team,
        teamMode: teamMode,
        cli: cli,
        onProgress: onProgress,
      ),
    ),
    loadInstalledDepIds: () async {
      final skills = await skillRepo.loadInstalled();
      final plugins = await pluginRepository.loadAll();
      final mcps = await mcpRepository.loadAll();
      return <String>{
        ...skills.map((s) => s.id),
        ...plugins.map((p) => p.id),
        ...mcps.map((m) => m.id),
      };
    },
  );

  final expertHubFavorites = ExpertHubFavoritesStore();
  teamCubit.attachExpertHubSource(compositeExpertHubSource);
  final expertCapabilityResolver = ExpertCapabilityResolver(
    installSkill: skillCubit.installTeamDependency,
    installPlugin: pluginCubit.installTeamDependency,
    installMcp: mcpCubit.installTeamDependency,
    source: compositeExpertHubSource,
  );
  final memberRosterService = MemberRosterService(
    resolver: expertCapabilityResolver,
  );
  expertHubCubit = ExpertHubCubit(
    source: compositeExpertHubSource,
    loadFavorites: expertHubFavorites.load,
    saveFavoriteToggle: expertHubFavorites.toggle,
    memberRosterService: memberRosterService,
    launchProfiles: () => teamCubit,
    hubCloneActivity: hubCloneActivityAdapter,
    loadInstalledDepIds: () async {
      final skills = await skillRepo.loadInstalled();
      return skills.map((s) => s.id).toSet();
    },
  );
  expertCapabilityResolver.attachHubCubit(expertHubCubit);
  final sessionRuntimePlanBuilder = SessionRuntimePlanBuilder(
    expertResolver: expertCapabilityResolver,
    workspaceProjectConfig: workspaceProjectConfigRepository,
  );
  sessionLifecycleService.attachRuntimePlanBuilder(sessionRuntimePlanBuilder);

  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final floatingWorkspaceCubit = FloatingWorkspaceCubit();
  final floatingWorkspacePersistence = FloatingWorkspacePersistence(
    layout: layoutCubit,
    floating: floatingWorkspaceCubit,
  );
  final workspaceToolsCubit = WorkspaceToolsCubit();
  final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
  final gitRepoStore = GitRepoStore();
  final workspaceFileTreeStore = WorkspaceFileTreeStore();
  final workspaceSearchIndexes = WorkspaceSearchIndexes();
  final workspaceWorktreeRegistry = WorkspaceWorktreeRegistry();
  final workspaceToolsScopeRegistry = WorkspaceToolsScopeRegistry();
  final workspaceRunRegistry = WorkspaceRunRegistry(
    platformFactory: WorkspaceRunPlatformFactory(
      extensionRepository: extensionRepository,
      projectConfigRepository: workspaceProjectConfigRepository,
      resolveWorkContext: sessionLifecycleService.resolveWorkContextForTargetId,
      sshProfileRepository: sshProfileRepo,
      sshClientFactory: sshClientFactory,
      homeTarget: defaultTargetResolver,
    ),
  );
  final configCubit = ConfigCubit();
  final commandBus = CommandBus();
  final shortcutCubit = ShortcutCubit();
  final workspaceChromeCommands = WorkspaceChromeCommands();
  final runCommandHost = RunCommandHost();
  final workspaceSearchHost = WorkspaceSearchHost();
  final uiZoomBaseline = UiZoomBaseline();
  registerShortcutsUiCommands(commandBus);
  registerRunCommands(commandBus, runCommandHost);
  registerWorkspaceSearchCommands(commandBus, workspaceSearchHost);

  final transportFactory = TerminalTransportFactory(
    sshProfileRepository: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepository: sshKnownHostRepo,
    sshClientFactory: sshClientFactory,
  );

  final workspaceShellConnector = WorkspaceShellConnector(
    transportFactory: transportFactory,
    sshProfileRepository: sshProfileRepo,
    sshUseLoginShell: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    homeTarget: defaultTargetResolver,
    profileById: sshProfileById,
  );
  // Terminal inject deps after connector: registry was created earlier.
  final workspaceTerminalSessionOps = WorkspaceTerminalSessionOps();
  final workspaceTerminalRunService = WorkspaceTerminalRunService();
  workspaceRunRegistry.setTerminalRunDeps(
    TerminalRunDeps(
      registry: workspaceTerminalRegistry,
      connector: workspaceShellConnector,
      ops: workspaceTerminalSessionOps,
      runService: workspaceTerminalRunService,
      connectCoordinatorFactory: (connector) =>
          WorkspaceTerminalConnectCoordinator.termuxAware(
            connector: connector,
            termuxConnected: () => termuxGateCubit?.state.connected ?? true,
            termuxWorkOpsBlockedMessage: TermuxWorkOpsMessage.disconnectedBlocked,
          ),
    ),
  );

  final automationRepo = AutomationRepository(
    fs: AppStorage.fs,
    layout: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath),
  );
  final teammateBusMcpGateway = TeammateBusMcpGateway();
  await teammateBusMcpGateway.ensureStarted();

  // Shared AskUserAnswerPendingStore singleton (lives in buildAppShell):
  // gateway GET /ask-user-answer + ChatCubit answer facade must reuse
  // this instance — do not construct a second store.
  final askUserAnswerPendingStore = AskUserAnswerPendingStore();
  teammateBusMcpGateway.attachAskUserAnswerStore(askUserAnswerPendingStore);
  final askUserQuestionHookGate = AskUserQuestionHookGate();
  final askUserQuestionAnswerService = AskUserQuestionAnswerService(
    store: askUserAnswerPendingStore,
    hookGate: askUserQuestionHookGate,
  );
  final exitPlanModeHookGate = ExitPlanModeHookGate();
  final exitPlanModeApprovalService = ExitPlanModeApprovalService(
    hookGate: exitPlanModeHookGate,
  );

  final agentAttentionCubit = AgentAttentionCubit();
  final agentStatusSeatLookup = AgentStatusSeatLookup();
  teammateBusMcpGateway.attachAgentStatusHandler(
    AgentStatusHttpHandler(
      attention: agentAttentionCubit,
      resolveCli: agentStatusSeatLookup.resolveCli,
      resolveSkipPermissions: agentStatusSeatLookup.resolveSkipPermissions,
      askUserHookGate: askUserQuestionHookGate,
      exitPlanModeHookGate: exitPlanModeHookGate,
    ),
  );

  chatCubit = ChatCubit(
    teammateBusMcpGateway: teammateBusMcpGateway,
    agentStatusSeatLookup: agentStatusSeatLookup,
    agentAttentionCubit: agentAttentionCubit,
    askUserAnswerPendingStore: askUserAnswerPendingStore,
    askUserQuestionAnswerService: askUserQuestionAnswerService,
    exitPlanApprovalService: exitPlanModeApprovalService,
    sessionRepository: sessionRepo,
    lifecycleService: sessionLifecycleService,
    automationRepository: automationRepo,
    layoutCubit: layoutCubit,
    autoLaunchAllMembersOnConnect: () =>
        sessionPreferencesCubit.state.preferences.autoLaunchAllMembersOnConnect,
    reclaimIdleTerminalsEnabled: () =>
        sessionPreferencesCubit.state.preferences.reclaimIdleTerminals,
    reclaimIdleTerminalAfterSeconds: () =>
        sessionPreferencesCubit.state.preferences.reclaimIdleTerminalAfterSeconds,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    transportFactory: transportFactory,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    sshProfileById: sshProfileById,
    teamById: (teamId) async {
      for (final team in await identityRepository.loadTeamProfiles()) {
        if (team.id == teamId) return team;
      }
      return null;
    },
    sshDefaultWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
    sshUseLoginShellResolver: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    defaultTargetResolver: defaultTargetResolver,
    terminalScrollbackLinesResolver: () =>
        sessionPreferencesCubit.state.preferences.terminalScrollbackLines,
    // P3b (#1): connect remote (ssh) mixed-team members back to the in-process
    // bus over a reverse tunnel. Local members resolve to null (unchanged).
    remoteBusResolver: RemoteBusBindingResolver(registry: cliToolRegistry),
    sessionConnect: buildSessionConnectOrchestrator(
      lifecycle: sessionLifecycleService,
      registry: cliToolRegistry,
      sshClientFactory: sshClientFactory,
      profileById: sshProfileById,
      contextForTarget: runtimeContextRegistry.forTarget,
      homeContext: runtimeContextRegistry.home,
      homeTarget: defaultTargetResolver,
      isCredentialOptIn: targetsRepo.isCredentialOptIn,
      cliPathOverride: targetsRepo.cliPathOverride,
      setCliPathOverride: targetsRepo.setCliPathOverride,
      loadLocalCredentials: (cli) => LocalCredentialExporter().export(cli),
      localCliPath: (cli) async =>
          sessionPreferencesCubit.resolveExecutable(cli),
      runtimePlanBuilder: sessionRuntimePlanBuilder,
    ),
    remoteCliReadiness: remoteCliReadiness,
    cliProvisionActivity: cliProvisionActivityAdapter,
    termuxConnectedResolver: () => termuxGateCubit?.state.connected ?? true,
    termuxDisconnectedWorkOpsMessageResolver:
        TermuxWorkOpsMessage.disconnectedBlocked,
    termuxGateHomeResolver: defaultTargetResolver,
  );

  // Bound after [WorkbenchCubit] exists; togglePanel aliases new-terminal UX
  // into the floating shell (Task 6 redirects the launcher to floating tabs).
  WorkbenchShellLauncher? workbenchShellLauncher;
  WorkbenchEditorOpener? workbenchEditorOpenerRef;
  Future<void> focusOrCreateDefaultShell() async {
    await workbenchShellLauncher?.focusOrCreateDefaultShell();
  }

  Future<void> openFloatingNewTerminal() async {
    floatingWorkspaceCubit.ensureOpen();
    await focusOrCreateDefaultShell();
  }

  Future<void> openFloatingFilePicker() async {
    final opener = workbenchEditorOpenerRef;
    if (opener == null) return;
    await pickAndOpenFloatingWorkspaceFile(
      floating: floatingWorkspaceCubit,
      opener: opener,
      workspaces: chatCubit.state.workspaces,
    );
  }

  registerFloatingWorkspaceCommands(
    commandBus,
    floatingWorkspaceCubit,
    onNewTerminal: focusOrCreateDefaultShell,
    onOpenFile: openFloatingFilePicker,
  );
  registerLayoutCommands(
    commandBus,
    layoutCubit,
    uiZoomBaseline: () => uiZoomBaseline.value,
    composeLanding: () => chatCubit.state.newChatActive,
    onTogglePanel: openFloatingNewTerminal,
  );

  memberPresenceCubit = MemberPresenceCubit();
  chatCubit.bindPresenceCubit(memberPresenceCubit);

  final sshProfileConnectionCoordinator = SshProfileConnectionCoordinator(
    factory: sshClientFactory,
    events: sshConnectionEvents,
    profileResolver: sshProfileById,
    onDisconnect: (profileId, error, stackTrace) {
      final profile = sshProfileById(profileId);
      final label = profile == null
          ? profileId
          : () {
              final name = profile.name.trim();
              return name.isEmpty
                  ? '${profile.username}@${profile.host}'
                  : '$name (${profile.username}@${profile.host})';
            }();
      if (error is SshTransportClosed) {
        final cause = error.cause;
        final message =
            '[ssh] profile $profileId ($label) transport closed: '
            'reason=${error.reason.name} plane=${error.plane.name}'
            '${cause != null ? ' cause=$cause' : ''}';
        if (isExpectedLocalSshTransportClose(error)) {
          appLogger.i(message);
        } else {
          appLogger.w(
            message,
            error: cause,
            stackTrace: cause != null ? stackTrace : null,
          );
        }
        return;
      }
      appLogger.w(
        '[ssh] profile $profileId ($label) transport closed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    },
    onReconnectSessionPlane: chatCubit.reconnectSshProfile,
  );

  final sshConnectionCubit = SshConnectionCubit(
    factory: sshClientFactory,
    coordinator: sshProfileConnectionCoordinator,
    selectProfileOnConnect: Platform.isAndroid
        ? (id) => applyAndroidSshConnectHome(
            profileId: id,
            selectHome: homeTargetController.select,
            selectProfile: sshProfileCubit.selectProfile,
          )
        : null,
  );

  final scheduleCalculator = AutomationScheduleCalculator();
  final automationDispatcher = AutomationDispatcher(
    repository: automationRepo,
    scheduleCalculator: scheduleCalculator,
    sessionRepository: sessionRepo,
    busGateway: TabTeamBusGateway(
      memberMaterializer: chatCubit.memberMaterializer,
      sessionRuntime: chatCubit.sessionRuntime,
    ),
    requestOpenSession: chatCubit.requestOpenSession,
    requestCreateAndOpenSession: chatCubit.requestCreateAndOpenSession,
    workspaceById: (workspaceId) => chatCubit.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull,
    teamById: (teamId) {
      final profile = teamCubit.state.byId(teamId);
      return profile is TeamProfile ? profile : null;
    },
    resolveCliPreset: (presetId) => cliPresetsCubit.state.presets
        .where((preset) => preset.id == presetId.trim())
        .firstOrNull,
    sessionById: (sessionId, workspaceId) => chatCubit.state.sessions
        .where((s) => s.sessionId == sessionId && s.workspaceId == workspaceId)
        .firstOrNull,
  );
  automationScheduler = AutomationScheduler(
    repository: automationRepo,
    dispatcher: automationDispatcher,
    scheduleCalculator: scheduleCalculator,
  );
  automationCubit = AutomationCubit(
    repository: automationRepo,
    scheduler: automationScheduler,
    scheduleCalculator: scheduleCalculator,
  );
  chatCubit.bindAutomationsChangeNotifier(() {
    if (!automationCubit.isClosed) {
      unawaited(automationCubit.reloadPreservingScope());
    }
  });

  final mailboxCubit = MailboxCubit(
    busForScope: (scope) => scopedTeamBus(chatCubit, scope),
  );

  final boardCubit = BoardCubit(
    busForScope: (scope) => scopedTeamBus(chatCubit, scope),
  );

  final aiHistoryLoader = AiHistoryLoader(
    contextBuilder: const SessionHistoryContextBuilder(),
    resolveWorkContext: (launchCtx, {String? memberId}) =>
        sessionLifecycleService.launchWorkContext(
          launchCtx,
          memberId: memberId,
        ),
    registry: cliToolRegistry,
    globalPresets: () => cliPresetsCubit.state.presets,
  );
  aiHistoryLoaderRef = aiHistoryLoader;
  // Pods own a per-session HistoryStore once the loader exists (ChatCubit is
  // constructed earlier); SessionChatView binds seats through the pod.
  chatCubit.historyLoader = aiHistoryLoader;
  final aiHistoryCubit = AiHistoryCubit(
    loader: aiHistoryLoader,
    loadMailboxRecords: (sessionId, memberId) async {
      final bus = chatCubit.tabStore.openTabBySessionId(sessionId)?.teamBus;
      if (bus == null) return const [];
      return bus.memberMailRecords(memberId);
    },
  );
  chatCubit.onSessionHistoryStale = (sessionId) {
    unawaited(aiHistoryCubit.softReloadIfSession(sessionId));
  };
  chatCubit.onHistorySeatsDispose = aiHistoryCubit.disposeSeatsForSession;
  // Landing seed routing: pods own the store; these sinks are the fallback.
  chatCubit.onSeedHistoryPending = (sid, mid, text) => aiHistoryCubit
      .seedPendingUser(sessionId: sid, memberId: mid, text: text);
  chatCubit.onCancelSeedHistoryPending = (sid, text) =>
      aiHistoryCubit.cancelSeedPendingUser(sessionId: sid, text: text);

  final appUpdateResolver = RemoteDownloadResolver.withProvider(
    () => remoteDownloadCatalogCubit.state.catalog,
  );
  final appUpdateHttpClient = http.Client();
  final appUpdateService = AppUpdateService(
    httpClient: appUpdateHttpClient,
    resolver: appUpdateResolver,
    downloadHttp: RemoteDownloadHttp(
      client: appUpdateHttpClient,
      resolver: appUpdateResolver,
    ),
    downloader: RemoteDownloader(
      client: appUpdateHttpClient,
      resolver: appUpdateResolver,
    ),
  );
  final appUpdateCubit = AppUpdateCubit(
    service: appUpdateService,
    settings: appSettings,
    activityAdapter: AppUpdateActivityAdapter(cubit: progressActivityCubit),
  );

  boot('loading layout');
  await layoutCubit.load();
  floatingWorkspacePersistence.hydrateFromLayout();
  floatingWorkspacePersistence.bind();
  await shortcutCubit.load();
  unawaited(notificationBootstrap);
  boot('layout ready (home index prefetched in background)');
  applyWorkspaceEntryMode(
    layoutCubit.state.preferences.workspaceEntryMode,
    lastOpenedWorkspaceId: layoutCubit.state.preferences.lastOpenedWorkspaceId,
  );
  boot('buildAppShell complete');
  bootstrapCubit?.markShellReady();
  boot('buildAppShell shell ready');

  reloadAllAppData = ({bool reinstallSshHome = true}) async {
    await AppDataBootstrap.reloadAll(
      boot: boot,
      sshProfileCubit: sshProfileCubit,
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      extensionCubit: extensionCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
      isSshMode: connectionModeService.isRemoteWorkPlane,
      homeSshProfileId: defaultTargetResolver().sshProfileId,
      sshProfileExists: (id) => sshProfileById(id) != null,
      reinstallStorageContext: reinstallStorageContext,
      home: defaultTargetResolver(),
      reinstallSshHome: reinstallSshHome,
    );
    await persistSshHomePathCacheIfLive();
  };

  Future<void> reconnectHomeSshIfNeeded() async {
    final home = defaultTargetResolver();
    final pid = home.sshProfileId;
    if (home.kind != RuntimeKind.ssh || pid == null || pid.isEmpty) return;
    await sshConnectionCubit.syncProfiles(sshProfileCubit.state.profiles);
    unawaited(sshConnectionCubit.connect(pid));
  }

  /// Background one-time migration: replace stale per-session marketplace
  /// clones with a symlink to the shared flavor dir (see
  /// [MarketplaceSharedStore]). Skips currently-open sessions; non-fatal.
  Future<void> _sweepStaleMarketplaceClones() async {
    try {
      await MarketplaceSharedStore(
        fs: AppStorage.fs,
        teampilotRoot: AppStorage.paths.basePath,
      ).sweepAll(
        workspaceIds: [
          for (final workspace in chatCubit.state.workspaces)
            workspace.workspaceId,
        ],
        activeSessionKeys: {
          for (final tab in chatCubit.state.tabs) tab.id,
        },
      );
    } on Object catch (e, st) {
      appLogger.w('[boot] marketplaceCloneSweep failed: $e\n$st');
    }
  }

  Future<void> bootstrapAppData() async {
    await notificationBootstrap;
    final indexReady = bootstrapCubit?.state.homeIndexReady ?? false;
    if (!indexReady) {
      bootstrapCubit?.beginHomeIndex();
    }
    boot('bootstrapAppData start');
    if (!indexReady) {
      if (connectionModeService.isRemoteWorkPlane) {
        boot('awaiting remote home index snapshots');
        try {
          await homeIndexPrefetch;
          await AppDataBootstrap.bootstrapHomeIndex(
            boot: boot,
            sshProfileCubit: sshProfileCubit,
            teamCubit: teamCubit,
            chatCubit: chatCubit,
            sessionRepo: sessionRepo,
            layoutCubit: layoutCubit,
            isSshMode: connectionModeService.isRemoteWorkPlane,
            homeSshProfileId: defaultTargetResolver().sshProfileId,
            sshProfileExists: (id) => sshProfileById(id) != null,
            reinstallStorageContext: reinstallStorageContext,
            home: defaultTargetResolver(),
          );
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[boot] remote home index bootstrap failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
        await persistSshHomePathCacheIfLive();
      } else {
        boot('awaiting home index snapshots');
        await homeIndexPrefetch;
        await AppDataBootstrap.hydrateNativeHomeIndex(
          boot: boot,
          teamCubit: teamCubit,
          chatCubit: chatCubit,
          sessionRepo: sessionRepo,
          layoutCubit: layoutCubit,
          home: defaultTargetResolver(),
        );
      }
      bootstrapCubit?.markHomeIndexReady();
    }
    await reconnectHomeSshIfNeeded();
    await yieldUiFrame();
    boot(
      'bootstrapAppData index ready '
      'workspaces=${chatCubit.state.workspaces.length} '
      '(sessions load on demand)',
    );
    unawaited(_sweepStaleMarketplaceClones());
    bootstrapCubit?.beginWarmAuxiliary();
    await AppDataBootstrap.warmAuxiliaryData(
      boot: boot,
      llmConfigCubit: llmConfigCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      extensionCubit: extensionCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    );
    final showOnboarding = await AppDataBootstrap.prepareInteractiveShell(
      boot: boot,
      appSettings: appSettings,
      sshProfileCubit: sshProfileCubit,
      cliPresetsCubit: cliPresetsCubit,
      aiFeatureSettingsCubit: aiFeatureSettingsCubit,
      homeWorkspaceUiCache: homeWorkspaceUiCache,
      workspaces: chatCubit.state.workspaces,
    );
    bootstrapCubit?.markAppReady(showOnboardingWizard: showOnboarding);
    LivePerfDriver.instance?.markAppReady();
    boot('bootstrapAppData complete');
    automationScheduler.start();
  }

  editorCubit = EditorCubit();
  // Fire-and-forget: warm the common tree-sitter grammars so the first file
  // open paints colored instead of cold. Never blocks app start.
  unawaited(EditorPlatform.bootstrap());
  final workbenchCubit = WorkbenchCubit();
  final markdownViewModes = MarkdownViewModeStore();
  final workbenchEditorOpener = WorkbenchEditorOpener(
    editor: editorCubit,
    workbench: workbenchCubit,
    floating: floatingWorkspaceCubit,
    chat: chatCubit,
    markdownViewModes: markdownViewModes,
    readMarkdownOpenMode: () =>
        layoutCubit.state.preferences.markdownOpenMode,
    readFilePreviewInFloating: () =>
        layoutCubit.state.preferences.filePreviewHost ==
        FilePreviewHost.floating,
  );
  workbenchEditorOpenerRef = workbenchEditorOpener;
  // One-shot: move leftover center shell tabs (and file tabs when floating
  // preview is preferred) into floating buckets.
  migrateLegacyWorkbenchTabsToFloating(
    workbench: workbenchCubit,
    floating: floatingWorkspaceCubit,
    migrateFiles: layoutCubit.state.preferences.filePreviewHost ==
        FilePreviewHost.floating,
  );
  final resolvedShellLauncher = WorkbenchShellLauncher(
    floating: floatingWorkspaceCubit,
    chat: chatCubit,
    registry: workspaceTerminalRegistry,
    connector: workspaceShellConnector,
    layout: layoutCubit,
    sessionOps: workspaceTerminalSessionOps,
    homeTarget: defaultTargetResolver,
    termuxConnected: () => termuxGateCubit?.state.connected ?? true,
    termuxWorkOpsBlockedMessage: TermuxWorkOpsMessage.disconnectedBlocked,
  );
  workbenchShellLauncher = resolvedShellLauncher;
  final floatingSurfaceRegistry = FloatingSurfaceRegistry.withDefaults(
    file: FilePreviewFloatingSurface(
      editor: editorCubit,
      floating: floatingWorkspaceCubit,
    ),
    terminal: TerminalFloatingSurface(
      floating: floatingWorkspaceCubit,
      registry: workspaceTerminalRegistry,
      runService: workspaceTerminalRunService,
    ),
    diff: DiffPreviewFloatingSurface(
      editor: editorCubit,
      floating: floatingWorkspaceCubit,
    ),
    run: RunFloatingSurface(
      floating: floatingWorkspaceCubit,
      resolveCubit: (tabScopeId) {
        final workspace = chatCubit.state.workspaces
            .where((w) => w.workspaceId == tabScopeId)
            .firstOrNull;
        if (workspace == null) return null;
        return workspaceRunRegistry.cubitFor(
          tabScopeId: tabScopeId,
          workspaceId: workspace.workspaceId,
          folders: workspace.folders,
        );
      },
      resolveTitle: (sessionId) {
        final tabScopeId = floatingWorkspaceCubit.state.activeWorkspaceId;
        if (tabScopeId.isEmpty) return null;
        final workspace = chatCubit.state.workspaces
            .where((w) => w.workspaceId == tabScopeId)
            .firstOrNull;
        if (workspace == null) return null;
        final cubit = workspaceRunRegistry.cubitFor(
          tabScopeId: tabScopeId,
          workspaceId: workspace.workspaceId,
          folders: workspace.folders,
        );
        for (final session in cubit.state.sessions) {
          if (session.id == sessionId) {
            return session.owned.configuration.name;
          }
        }
        return null;
      },
    ),
  );
  final floatingMaximizeInsets = FloatingMaximizeInsets();
  registerSessionCommands(
    commandBus,
    chatCubit,
    WorkbenchStripNavigator(workbench: workbenchCubit, chat: chatCubit),
  );

  // P1: switching the home target persists the id, rebinds the home context,
  // then reinstalls + reloads all remote-backed app data (same chain the old
  // backend/profile switches used).
  Future<void> switchHomeTarget(String id) async {
    await setHomeTarget(id); // persists + rebinds home + republishes AppStorage
    // Home already rebound — skip a second dispose/rebind that would tear down
    // the Connect storage pool (runtimeContextEvicted WARN).
    await reloadAllAppData(reinstallSshHome: false);
  }

  final homeStorageInvalidator = HomeStorageInvalidator(
    homeTargetId: () => defaultTargetResolver().id,
    reinstallAndReload: () async {
      await reinstallStorageContext();
      await reloadAllAppData();
    },
    switchHome: switchHomeTarget,
  );

  homeTargetController = HomeTargetController(
    registry: runtimeTargetRegistry,
    current: defaultTargetResolver,
    switchTo: switchHomeTarget,
  );

  void refreshTermuxConfigCache(TermuxConfig? config) {
    termuxConfigCache = config;
  }

  final termuxConnectionTester = SshProfileConnectionTester(
    clientFactory: sshClientFactory,
  );
  final termuxCubit = TermuxCubit(
    store: termuxConfigStore,
    credentials: sshCredentialStore,
    nativeAppDataPath: nativeAppDataPath,
    selectHome: homeTargetController.select,
    initialConfig: termuxConfigCache,
    onConfigChanged: refreshTermuxConfigCache,
    resolvePathsAfterHomeSelect: () async {
      final homeCtx = runtimeContextRegistry.home();
      if (homeCtx.pathsFromCache) {
        return (home: null, appDataRoot: null);
      }
      return (home: homeCtx.home, appDataRoot: homeCtx.appDataRoot);
    },
    testConnect: (profile) async {
      try {
        await termuxConnectionTester.test(profile);
        return (ok: true, message: '');
      } on Object catch (error) {
        return (ok: false, message: error.toString());
      }
    },
    disconnectTransport: () async {
      sshClientFactory.disconnectProfile(
        'termux',
        reason: SshTransportCloseReason.userDisconnect,
      );
    },
  );
  if (homeTarget.kind == RuntimeKind.termux) {
    unawaited(termuxCubit.reconnect());
  }
  termuxGateCubit = termuxCubit;

  // Target-aware directory picker for workspace dialogs: resolves the chosen
  // target's filesystem (real SSH connect for ssh targets) and lists targets.
  final directoryPicker = WorkspaceDirectoryPicker(
    resolveContext: runtimeContextRegistry.forTarget,
    listTargets: () => runtimeTargetRegistry.listTargets(),
  );

  return AppShell(
    cliToolRegistry: cliToolRegistry,
    homeTargetController: homeTargetController,
    directoryPicker: directoryPicker,
    chatCubit: chatCubit,
    memberPresenceCubit: memberPresenceCubit,
    agentAttentionCubit: agentAttentionCubit,
    agentStatusSeatLookup: agentStatusSeatLookup,
    mailboxCubit: mailboxCubit,
    boardCubit: boardCubit,
    aiHistoryCubit: aiHistoryCubit,
    notificationCubit: notificationCubit,
    progressActivityCubit: progressActivityCubit,
    editorCubit: editorCubit,
    workbenchCubit: workbenchCubit,
    workbenchEditorOpener: workbenchEditorOpener,
    workbenchShellLauncher: resolvedShellLauncher,
    floatingWorkspaceCubit: floatingWorkspaceCubit,
    floatingSurfaceRegistry: floatingSurfaceRegistry,
    floatingMaximizeInsets: floatingMaximizeInsets,
    sessionRepo: sessionRepo,
    workspaceProjectConfigRepository: workspaceProjectConfigRepository,
    sshProfileRepo: sshProfileRepo,
    sshCredentialStore: sshCredentialStore,
    sshKnownHostRepo: sshKnownHostRepo,
    transportFactory: transportFactory,
    workspaceTerminalRegistry: workspaceTerminalRegistry,
    workspaceShellConnector: workspaceShellConnector,
    workspaceTerminalSessionOps: workspaceTerminalSessionOps,
    workspaceTerminalRunService: workspaceTerminalRunService,
    gitRepoStore: gitRepoStore,
    workspaceFileTreeStore: workspaceFileTreeStore,
    workspaceSearchIndexes: workspaceSearchIndexes,
    workspaceWorktreeRegistry: workspaceWorktreeRegistry,
    workspaceToolsScopeRegistry: workspaceToolsScopeRegistry,
    workspaceRunRegistry: workspaceRunRegistry,
    sshClientFactory: sshClientFactory,
    sshProfileConnectionCoordinator: sshProfileConnectionCoordinator,
    connectionModeService: connectionModeService,
    identityRepository: identityRepository,
    teamCubit: teamCubit,
    configCubit: configCubit,
    appProviderCubit: appProviderCubit,
    llmConfigCubit: llmConfigCubit,
    layoutCubit: layoutCubit,
    workspaceToolsCubit: workspaceToolsCubit,
    sessionPreferencesCubit: sessionPreferencesCubit,
    pluginCubit: pluginCubit,
    cliPresetsCubit: cliPresetsCubit,
    skillCubit: skillCubit,
    mcpCubit: mcpCubit,
    teamHubCubit: teamHubCubit,
    expertHubCubit: expertHubCubit,
    expertCapabilityResolver: expertCapabilityResolver,
    extensionCubit: extensionCubit,
    appUpdateCubit: appUpdateCubit,
    remoteDownloadCatalogCubit: remoteDownloadCatalogCubit,
    sshProfileCubit: sshProfileCubit,
    termuxCubit: termuxCubit,
    homeStorageInvalidator: homeStorageInvalidator,
    sshConnectionCubit: sshConnectionCubit,
    githubCredentialsStore: githubCredentialsStore,
    githubAccountCubit: githubAccountCubit,
    appSettings: appSettings,
    aiFeatureSettingsCubit: aiFeatureSettingsCubit,
    reinstallStorageContext: reinstallStorageContext,
    bootstrapAppData: bootstrapAppData,
    homeWorkspaceUiCache: homeWorkspaceUiCache,
    automationCubit: automationCubit,
    automationScheduler: automationScheduler,
    commandBus: commandBus,
    shortcutCubit: shortcutCubit,
    workspaceChromeCommands: workspaceChromeCommands,
    runCommandHost: runCommandHost,
    workspaceSearchHost: workspaceSearchHost,
    uiZoomBaseline: uiZoomBaseline,
  );
}

class TeamPilotBootstrap extends StatefulWidget {
  const TeamPilotBootstrap({
    super.key,
    required this.preferences,
    required this.nativeAppDataPath,
    required this.defaultWorkspaceDirectoryFuture,
    required this.homeIndexPrefetchFuture,
    required this.bootstrapCubit,
    required this.childBuilder,
  });

  final SharedPreferences preferences;
  final String nativeAppDataPath;
  final Future<String> defaultWorkspaceDirectoryFuture;
  final Future<void> homeIndexPrefetchFuture;
  final AppBootstrapCubit bootstrapCubit;
  final Widget Function(AppShell shell) childBuilder;

  @override
  State<TeamPilotBootstrap> createState() => _TeamPilotBootstrapState();
}

class _TeamPilotBootstrapState extends State<TeamPilotBootstrap> {
  AppShell? _shell;
  Object? _error;
  var _retrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    final bootSw = Stopwatch()..start();
    try {
      appLogger.i('[boot] +0ms TeamPilotBootstrap starting buildAppShell');
      final shell = await buildAppShell(
        preferences: widget.preferences,
        nativeAppDataPath: widget.nativeAppDataPath,
        defaultWorkspaceDirectoryFuture: widget.defaultWorkspaceDirectoryFuture,
        homeIndexPrefetchFuture: widget.homeIndexPrefetchFuture,
        bootstrapCubit: widget.bootstrapCubit,
      );
      if (!mounted) return;
      await yieldUiFrame();
      await shell.bootstrapAppData();
      if (!mounted) return;
      appLogger.i(
        '[boot] +${bootSw.elapsedMilliseconds}ms bootstrap complete '
        'workspaces=${shell.chatCubit.state.workspaces.length}',
      );
      // Build the app UI first so it paints underneath the splash overlay.
      // Yield across SplashDeferredShell mount before fading the splash away.
      setState(() {
        _shell = shell;
        _error = null;
        _retrying = false;
      });
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      await yieldUiFrame();
      if (!mounted) return;
      await completeBootSplashTransition();
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[boot] buildAppShell failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      await completeBootSplashTransition();
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  Future<void> _retryBootstrap() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _start();
  }

  Future<void> _chooseWorkEnvironmentAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  Future<void> _switchToNativeStorageAndRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Home target failed to install (e.g. WSL unavailable) — fall back to the
    // local device as home and retry bootstrap.
    await HomeTargetStore(widget.preferences).save(RuntimeTarget.localId);
    await _start();
  }

  bool get _canFallbackToNativeStorage {
    if (!Platform.isWindows || _error == null) return false;
    return runtimeKindOfId(HomeTargetStore(widget.preferences).load()) ==
        RuntimeKind.wsl;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BootstrapStartupErrorPage(
          error: _error!,
          showChooseWorkEnvironment: Platform.isAndroid,
          showNativeStorageFallback: _canFallbackToNativeStorage,
          retrying: _retrying,
          onRetry: _retryBootstrap,
          onChooseWorkEnvironment: _chooseWorkEnvironmentAndRetry,
          onNativeStorageFallback: _switchToNativeStorageAndRetry,
        ),
      );
    }
    final shell = _shell;
    if (shell == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppBootstrapLoadingPage(),
      );
    }
    return widget.childBuilder(shell);
  }
}
