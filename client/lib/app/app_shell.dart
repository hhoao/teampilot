import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cubits/app_bootstrap_cubit.dart';
import 'app_data_bootstrap.dart';
import 'bootstrap/agent_runtime_wiring.dart';
import 'bootstrap/app_settings_wiring.dart';
import 'bootstrap/managed_provider_control_plane.dart';
import 'bootstrap/managed_provider_wiring.dart';
import 'bootstrap/catalog_runtime_wiring.dart';
import 'bootstrap/catalog_wiring.dart';
import 'bootstrap/chat_session_wiring.dart';
import 'bootstrap/cli_bootstrap_wiring.dart';
import 'bootstrap/home_plane_switch.dart';
import 'bootstrap/home_plane_wiring.dart';
import 'bootstrap/hub_wiring.dart';
import 'bootstrap/install_wiring.dart';
import 'bootstrap/platform_wiring.dart';
import 'bootstrap/session_runtime_wiring.dart';
import 'bootstrap/session_state_wiring.dart';
import 'bootstrap/session_usage_wiring.dart';
import 'bootstrap/shell_boot.dart';
import 'bootstrap/ssh_plane_wiring.dart';
import 'bootstrap/vault_wiring.dart';
import 'bootstrap/workspace_wiring.dart';
import 'bootstrap/connect_wiring.dart';
import 'bootstrap/command_wiring.dart';
import 'bootstrap/automation_wiring.dart';
import 'team_generation_graph.dart';
import '../cubits/app_provider_cubit.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/remote_download_catalog_cubit.dart';
import '../cubits/automation_cubit.dart';
import '../cubits/agent_attention_cubit.dart';
import '../cubits/seat_lease_cubit.dart';
import '../cubits/session_remote_activity_cubit.dart';
import '../services/event/dispatcher.dart' as event_bus;
import '../services/event/session_lifecycle_event.dart';
import '../services/attention/attention_event.dart';
import '../services/attention/attention_inbox.dart';
import '../services/session_protocol/session_authority.dart';
import '../services/session_sync/chat_session_activity_source.dart';
import '../services/session_sync/session_content_invalidation_bus.dart';
import '../services/session_sync/session_content_stream_bus.dart';
import '../services/session_sync/session_protocol_controller.dart';
import 'session_protocol_home.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/session_usage_cubit.dart';
import '../services/cursor_usage/cursor_usage_api_client.dart';
import '../services/agent_runtime/agent_runtime.dart';
import '../services/event/agent_presence_projection.dart';
import '../services/event/agent_presence_sink.dart';
import '../services/event/event_transport_controller.dart';
import '../services/event/presence_event_bridge.dart';
import 'event_transport_home.dart';
import '../services/chat/conversation/prompt_delivery/prompt_delivery_coordinator.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/chat/team_generation/mcp/team_composer_mcp_handler.dart';
import '../models/app_session.dart';
import '../models/session_list_entry.dart';
import '../services/catalog/catalog_runtime.dart';
import '../services/catalog/catalog_mutation_bus.dart';
import '../services/remote/remote_cli_readiness.dart';
import '../services/editor_platform/editor_platform.dart';
import '../services/launch_profile/team/launch_profile_selectors.dart';
import '../cubits/board_cubit.dart';
import '../cubits/mailbox_cubit.dart';
import '../cubits/member_presence_cubit.dart';
import '../cubits/notification_cubit.dart';
import '../cubits/progress_activity_cubit.dart';
import '../cubits/repo_clone_cubit.dart';
import '../services/install/install_job_registry.dart';
import '../services/install/runners/app_update_install_job_runner.dart';
import '../cubits/ai_history_cubit.dart';
import '../cubits/shortcut_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../cubits/workbench/workbench_tab.dart';
import '../services/workbench/workbench_chat_bridge.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workbench/workbench_layout_persistence.dart';
import '../services/workbench/workbench_shell_launcher.dart';
import '../services/workbench/workbench_strip_navigator.dart';
import '../services/editor/markdown_view_mode_store.dart';
import '../services/chat/conversation/history/ai_history_loader.dart';
import '../cubits/ai_feature_settings_cubit.dart';
import '../cubits/discovery_settings_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/connect_cubit.dart';
import '../services/connect/endpoint_dial_planner.dart';
import '../services/connect/paired_device_store.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../models/layout_preferences.dart';
import '../models/right_tool_open_set.dart';
import '../cubits/workspace_tools_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/managed_provider_cubit.dart';
import '../cubits/managed_provider_usage_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../models/session_preferences.dart';
import '../cubits/extension_cubit.dart';
import '../cubits/hook_cubit.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../cubits/workspace_project_config_cubit.dart';
import '../repositories/launch_profile_repository.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../cubits/cli_presets_cubit.dart';
import '../models/cli_preset.dart';
import '../cubits/skill_cubit.dart';
import '../services/hook/hook_repository.dart';
import '../services/hook/import/hook_import_service.dart';
import '../services/mcp/profile_mcp_linker_service.dart';
import '../cubits/ssh_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/ssh_workload_profile_cubit.dart';
import '../cubits/vault_cubit.dart';
import '../cubits/termux_cubit.dart';
import '../cubits/github_account_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/team_hub_cubit.dart';
import '../cubits/expert_hub_cubit.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../l10n/l10n_extensions.dart';
import '../services/acp/acp_chat_strings.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/combined_ssh_profile_repository.dart';
import '../repositories/plane_ssh_profile_repository.dart';
import '../repositories/ssh_server_profile_repository.dart';
import '../repositories/workspace_project_config_repository.dart';
import '../repositories/managed_provider_repository.dart';
import '../repositories/managed_provider_usage_repository.dart';
import '../router/app_router.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/storage/app_paths.dart';
import '../services/storage/device_local_control_plane.dart';
import '../services/storage/remote_target_migration.dart';
import '../services/vault/credential_capture.dart';
import '../services/vault/home_vault_service.dart';
import '../services/vault/legacy_import.dart';
import '../services/vault/vault_split_migration.dart';
import '../services/vault/vault_service.dart';
import '../services/vault/vault_unlock_gate.dart';
import '../services/io/local_filesystem.dart';
import '../services/connect/connect_ssh_backend.dart';
import '../services/automation/automation_schedule_calculator.dart';
import '../services/automation/automation_scheduler.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/expert_hub/expert_capability_resolver.dart';
import '../services/expert_hub/expert_hub_catalog.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/layout_command_registrar.dart';
import '../services/commands/run_command_registrar.dart';
import '../services/commands/session_command_registrar.dart';
import '../services/commands/split_command_registrar.dart';
import '../services/commands/workspace_search_command_registrar.dart';
import '../services/commands/workspace_content_search_command_registrar.dart';
import '../services/floating_workspace/floating_maximize_insets.dart';
import '../services/floating_workspace/floating_surface_registry.dart';
import '../services/floating_workspace/floating_workspace_commands.dart';
import '../services/floating_workspace/floating_workspace_open_file.dart';
import '../services/floating_workspace/surfaces/diff_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/file_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/git_compare_floating_surface.dart';
import '../services/floating_workspace/surfaces/git_graph_floating_surface.dart';
import '../services/floating_workspace/surfaces/html_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/run_floating_surface.dart';
import '../services/floating_workspace/surfaces/terminal_floating_surface.dart';
import '../pages/home_workspace/workspace_chrome_commands.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/cli/grok/grok_bootstrap_entry.dart';
import '../services/host/host_shell_path_resolver.dart';
import '../services/provider_usage/managed_provider_secret_store.dart';
import '../services/provider_usage/managed_provider_usage_adapter.dart';
import '../services/provider_usage/managed_provider_usage_coordinator.dart';
import '../services/provider_usage/managed_provider_usage_registry.dart';
import '../services/provider_usage/cli_credential_source.dart';
import '../services/app/connection_mode_service.dart';
import '../services/cli/remote_cli_locator.dart';
import '../cubits/home_connection_cubit.dart';
import '../services/storage/home_connect_attempt.dart';
import '../services/storage/home_invalidation_service.dart';
import '../services/storage/home_storage_invalidator.dart';
import '../services/storage/home_target_controller.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/workspace_directory_picker.dart';
import '../services/storage/home_target_store.dart';
import '../services/storage/runtime_target_registry.dart';
import '../services/termux/termux_config.dart';
import '../services/termux/termux_transport_profile.dart';
import '../services/termux/termux_work_ops_message.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/chat/session/session_lifecycle_service.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/skill/registry/skill_registry_factory.dart';
import '../services/storage/runtime_context.dart';
import '../services/github/github_credentials_store.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/ssh/ssh_connection_gate.dart';
import '../services/ssh/ssh_home_connectivity_supervisor.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/ssh/mcp/session_ssh_mcp_executor.dart';
import '../services/ssh/mcp/session_ssh_mcp_http.dart';
import '../services/ssh/mcp/session_ssh_mcp_operations.dart';
import '../services/ssh/mcp/session_ssh_mcp_resolver.dart';
import '../services/ssh/combined_ssh_profile_resolver.dart';
import '../services/ssh/plane_ssh_profile_resolver.dart';
import '../services/ssh/ssh_transport_close.dart';
import '../services/ssh/android_ssh_connect_home.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_command_runner.dart';
import '../services/git/git_repo_store.dart';
import '../services/workspace/workspace_tools_scope_registry.dart';
import '../services/workspace/workspace_run_registry.dart';
import '../services/search/workspace_search_indexes.dart';
import '../services/workspace/workspace_worktree_registry.dart';
import '../services/workspace/workspace_session_groups_registry.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/terminal/workspace_terminal_connect_coordinator.dart';
import '../services/terminal/workspace_terminal_run_service.dart';
import '../services/terminal/workspace_terminal_session_ops.dart';
import '../utils/logging/logger.dart';
import 'ui_zoom_baseline.dart';

/// Fully wired app dependencies produced after async bootstrap.
class AppShell {
  AppShell({
    required this.homeTargetController,
    required this.directoryPicker,
    required this.chatCubit,
    required this.remoteCliReadiness,
    this.teamGenerationGraph,
    required this.memberPresenceCubit,
    required this.sessionRemoteActivityCubit,
    required this.sessionProtocolController,
    required this.sessionActivitySource,
    required this.sessionAuthority,
    this.sessionLifecycleHandler,
    required this.agentAttentionCubit,
    required this.seatLeaseCubit,
    required this.agentStatusSeatLookup,
    required this.agentRuntime,
    required this.mailboxCubit,
    required this.boardCubit,
    required this.aiHistoryCubit,
    required this.notificationCubit,
    required this.progressActivityCubit,
    required this.repoCloneCubit,
    required this.installJobRegistry,
    required this.editorCubit,
    required this.workbenchCubit,
    required this.workbenchLayoutPersistence,
    required this.workbenchEditorOpener,
    required this.workbenchShellLauncher,
    required this.floatingWorkspaceCubit,
    required this.floatingSurfaceRegistry,
    required this.floatingMaximizeInsets,
    required this.sessionRepo,
    required this.workspaceProjectConfigRepository,
    required this.sshProfileRepo,
    required this.combinedSshProfileRepo,
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
    required this.workspaceSessionGroupsRegistry,
    required this.workspaceToolsScopeRegistry,
    required this.workspaceRunRegistry,
    required this.sshClientFactory,
    required this.sshProfileConnectionCoordinator,
    required this.connectionModeService,
    required this.identityRepository,
    required this.teamCubit,
    required this.sessionUsageCubit,
    required this.cursorUsageApiClient,
    required this.configCubit,
    required this.connectCubit,
    required this.embeddedSshServer,
    this.systemSshdBackend,
    required this.connectDeviceStore,
    required this.appProviderCubit,
    required this.managedProviderControlPlane,
    required this.managedProviderRepository,
    required this.managedProviderUsageRepository,
    required this.managedProviderSecretStore,
    required this.managedProviderUsageRegistry,
    required this.managedProviderUsageCoordinator,
    required this.managedProviderCubit,
    required this.managedProviderUsageCubit,
    required this.llmConfigCubit,
    required this.layoutCubit,
    required this.workspaceToolsCubit,
    required this.sessionPreferencesCubit,
    required this.pluginCubit,
    required this.cliPresetsCubit,
    required this.skillCubit,
    required this.mcpCubit,
    required this.hookCubit,
    required this.hookRepository,
    required this.hookImportParser,
    required this.hookImportService,
    required this.teamHubCubit,
    required this.expertHubCubit,
    required this.expertHubCatalog,
    required this.expertCapabilityResolver,
    required this.extensionCubit,
    required this.appUpdateCubit,
    required this.remoteDownloadCatalogCubit,
    required this.sshProfileCubit,
    required this.sshWorkloadProfileCubit,
    required this.vaultService,
    required this.homeVaultScope,
    required this.vaultCubit,
    required this.vaultCredentialCapture,
    required this.vaultUnlockGate,
    required this.termuxCubit,
    required this.homeStorageInvalidator,
    required this.homeInvalidationService,
    required this.homeStorage,
    required this.homeConnectionCubit,
    required this.sshConnectionCubit,
    required this.githubCredentialsStore,
    required this.githubAccountCubit,
    required this.appSettings,
    required this.aiFeatureSettingsCubit,
    required this.discoverySettingsCubit,
    required this.reinstallStorageContext,
    required this.bootstrapAppData,
    required this.warmStartupCaches,
    this.catalogRuntime,
    required this.cliToolRegistry,
    required this.homeWorkspaceUiCache,
    required this.automationCubit,
    required this.automationScheduler,
    required this.commandBus,
    required this.shortcutCubit,
    required this.workspaceChromeCommands,
    required this.runCommandHost,
    required this.workspaceSearchHost,
    required this.workspaceContentSearchHost,
    required this.uiZoomBaseline,
  });

  final CliToolRegistry cliToolRegistry;
  final HomeWorkspaceUiCache homeWorkspaceUiCache;
  final HomeTargetController homeTargetController;
  final WorkspaceDirectoryPicker directoryPicker;
  final ChatCubit chatCubit;
  final RemoteCliReadinessService remoteCliReadiness;
  final TeamGenerationGraph? teamGenerationGraph;
  final MemberPresenceCubit memberPresenceCubit;
  final SessionRemoteActivityCubit sessionRemoteActivityCubit;
  final SessionProtocolController sessionProtocolController;
  final ChatSessionActivitySource sessionActivitySource;
  final SessionAuthority sessionAuthority;
  final event_bus.EventHandler<SessionLifecycleEvent>? sessionLifecycleHandler;
  final AgentAttentionCubit agentAttentionCubit;
  final SeatLeaseCubit seatLeaseCubit;
  final AgentStatusSeatLookup agentStatusSeatLookup;
  final AgentRuntime agentRuntime;
  final MailboxCubit mailboxCubit;
  final BoardCubit boardCubit;
  final AiHistoryCubit aiHistoryCubit;
  final NotificationCubit notificationCubit;
  final ProgressActivityCubit progressActivityCubit;
  final RepoCloneCubit repoCloneCubit;
  final InstallJobRegistry installJobRegistry;
  final EditorCubit editorCubit;
  final WorkbenchCubit workbenchCubit;
  final WorkbenchLayoutPersistence workbenchLayoutPersistence;
  final WorkbenchEditorOpener workbenchEditorOpener;
  final WorkbenchShellLauncher workbenchShellLauncher;
  final FloatingWorkspaceCubit floatingWorkspaceCubit;
  final FloatingSurfaceRegistry floatingSurfaceRegistry;
  final FloatingMaximizeInsets floatingMaximizeInsets;
  final SessionRepository sessionRepo;
  final WorkspaceProjectConfigRepository workspaceProjectConfigRepository;
  final SshProfileRepository sshProfileRepo;
  /// Combined B-first + A-fallback point-lookup repository for work-plane
  /// execution chains (workspace terminals, folder liveness). Provided to the
  /// widget tree under its own type so workspace consumers get B hosts while
  /// the [SshProfileRepository] provider stays device-local A source for
  /// Remote Connections / onboarding / pairing.
  final CombinedSshProfileRepository combinedSshProfileRepo;
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
  final WorkspaceSessionGroupsRegistry workspaceSessionGroupsRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final WorkspaceRunRegistry workspaceRunRegistry;
  final SshClientFactory sshClientFactory;
  final SshProfileConnectionCoordinator sshProfileConnectionCoordinator;
  final ConnectionModeService connectionModeService;
  final LaunchProfileRepository identityRepository;
  final LaunchProfileCubit teamCubit;
  final SessionUsageCubit sessionUsageCubit;

  /// Owned by the shell so its HTTP client is closed with the shell.
  final CursorUsageApiClient cursorUsageApiClient;
  final ConfigCubit configCubit;
  final ConnectCubit? connectCubit;

  /// The desktop's embedded SSH server; `null` on Android (no Connect host).
  final ConnectSshBackend? embeddedSshServer;

  /// Linux/macOS system OpenSSH backend; `null` on Android and Windows.
  final ConnectSshBackend? systemSshdBackend;

  /// The device registry shared by the embedded server, pairing agent, and
  /// Connect UI; `null` on Android.
  final PairedDeviceStore? connectDeviceStore;

  final AppProviderCubit appProviderCubit;
  final ManagedProviderControlPlane managedProviderControlPlane;
  final ManagedProviderRepository managedProviderRepository;
  final ManagedProviderUsageRepository managedProviderUsageRepository;
  final ManagedProviderSecretStore managedProviderSecretStore;
  final ManagedProviderUsageRegistry managedProviderUsageRegistry;
  final ManagedProviderUsageCoordinator managedProviderUsageCoordinator;
  final ManagedProviderCubit managedProviderCubit;
  final ManagedProviderUsageCubit managedProviderUsageCubit;
  final LlmConfigCubit llmConfigCubit;
  final LayoutCubit layoutCubit;
  final WorkspaceToolsCubit workspaceToolsCubit;
  final SessionPreferencesCubit sessionPreferencesCubit;
  final PluginCubit pluginCubit;
  final CliPresetsCubit cliPresetsCubit;
  final SkillCubit skillCubit;
  final McpCubit mcpCubit;
  final HookCubit hookCubit;
  final HookRepository hookRepository;
  final HookImportParser hookImportParser;
  final HookImportService hookImportService;
  final TeamHubCubit teamHubCubit;
  final ExpertHubCubit expertHubCubit;
  final ExpertHubCatalog expertHubCatalog;
  final ExpertCapabilityResolver expertCapabilityResolver;
  final ExtensionCubit extensionCubit;
  final AppUpdateCubit appUpdateCubit;
  final RemoteDownloadCatalogCubit remoteDownloadCatalogCubit;
  final SshProfileCubit sshProfileCubit;
  final SshWorkloadProfileCubit sshWorkloadProfileCubit;
  final VaultService vaultService;
  final HomeVaultScope homeVaultScope;
  final VaultCubit vaultCubit;
  final VaultCredentialCapture vaultCredentialCapture;
  final VaultUnlockGate vaultUnlockGate;
  final TermuxCubit termuxCubit;
  final HomeStorageInvalidator homeStorageInvalidator;
  final HomeInvalidationService homeInvalidationService;
  final HomeStorage homeStorage;
  final HomeConnectionCubit homeConnectionCubit;
  final SshConnectionCubit sshConnectionCubit;
  final GithubCredentialsStore githubCredentialsStore;
  final GithubAccountCubit githubAccountCubit;
  final AppSettingsRepository appSettings;
  final AiFeatureSettingsCubit aiFeatureSettingsCubit;
  final DiscoverySettingsCubit discoverySettingsCubit;
  final Future<void> Function() reinstallStorageContext;
  final Future<void> Function() bootstrapAppData;

  /// Cache warm-ups that must not compete with the first frame. Started after
  /// the splash transition; swallows its own failures.
  final Future<void> Function() warmStartupCaches;

  /// Retried-bootstrap teardown seam: the assembled catalog runtime, exposed so
  /// a bootstrap failure after [buildAppShell] succeeded can close its
  /// mutation bus (unregistering the relay from the app-lifetime central
  /// dispatcher) before a retry constructs a new shell. Null only when
  /// construction failed before [CatalogRuntime.assemble] ran.
  final CatalogRuntime? catalogRuntime;
  final AutomationCubit automationCubit;
  final AutomationScheduler automationScheduler;

  /// Refreshes the Automations page after catalog-driven writes; owned by the
  /// shell so bootstrap teardown can cancel it.
  StreamSubscription<CatalogMutationEvent>? _automationCatalogSub;

  /// Re-arms the home connection after the current SSH profile's identity is
  /// edited; owned by the shell so teardown can cancel it.
  StreamSubscription<SshProfileState>? _homeProfileWatchSub;

  /// Projects the connectivity supervisor onto the home connection page.
  StreamSubscription<SshHomeConnectivityState>? _homeConnectivitySub;

  /// Re-syncs the business vault after a home-plane switch; owned by the shell
  /// so teardown can cancel it.
  StreamSubscription<StoragePlaneChange>? _vaultPlaneSyncSub;
  StreamSubscription<SessionRemoteActivityState>? _sessionRemoteRefreshSub;
  StreamSubscription<SessionContentInvalidation>? _contentInvalidationSub;
  StreamSubscription<SessionContentStreamChunk>? _contentStreamSub;
  StreamSubscription<AttentionEvent>? _attentionSub;
  AttentionInbox? _attentionInbox;

  /// Cancels the subscriptions [buildAppShell] attached to this shell.
  ///
  /// The bootstrap widget owns the shell's lifetime; it calls this when the
  /// shell is discarded. Each cancel stays fire-and-forget, as it was inline,
  /// because `dispose` is synchronous.
  void cancelShellSubscriptions() {
    _automationCatalogSub?.cancel();
    _homeProfileWatchSub?.cancel();
    _homeConnectivitySub?.cancel();
    _vaultPlaneSyncSub?.cancel();
    unawaited(_sessionRemoteRefreshSub?.cancel());
    unawaited(_contentInvalidationSub?.cancel());
    unawaited(_contentStreamSub?.cancel());
    unawaited(_attentionSub?.cancel());
    unawaited(_attentionInbox?.dispose());
    // The workload catalog owns a HomeStorage.changes subscription; closing it
    // here keeps that subscription tied to the shell lifetime.
    unawaited(sshWorkloadProfileCubit.close());
  }

  final CommandBus commandBus;
  final ShortcutCubit shortcutCubit;
  final WorkspaceChromeCommands workspaceChromeCommands;
  final RunCommandHost runCommandHost;
  final WorkspaceSearchHost workspaceSearchHost;
  final WorkspaceContentSearchHost workspaceContentSearchHost;
  final UiZoomBaseline uiZoomBaseline;
}

Future<AppShell> buildAppShell({
  required SharedPreferences preferences,
  required String nativeAppDataPath,
  event_bus.Dispatcher? eventDispatcher,
  Future<String>? defaultWorkspaceDirectoryFuture,
  Future<void>? homeIndexPrefetchFuture,
  AppBootstrapCubit? bootstrapCubit,
  ManagedProviderRepository? managedProviderRepository,
  ManagedProviderUsageRepository? managedProviderUsageRepository,
  ManagedProviderSecretStore? managedProviderSecretStore,
  ManagedProviderUsageRegistry? managedProviderUsageRegistry,
  ManagedProviderUsageCoordinator? managedProviderUsageCoordinator,
  ManagedProviderCubit? managedProviderCubit,
  ManagedProviderUsageCubit? managedProviderUsageCubit,
  ProviderUsageHttpClient? managedProviderUsageHttpClient,
  CliCredentialSourceResolver? managedProviderCliCredentials,
  // Pushed presence events: the app-lifetime projection (registered on the
  // bootstrap state's dispatcher) and a narrow sink onto that same dispatcher.
  // Null keeps the cubit on the legacy poll-derived path (tests, early boot).
  AgentPresenceProjection? presenceProjection,
  AgentPresenceSink? presenceSink,
  EventTransportController? eventTransportController,
  void Function(HomeStorage home)? bindEventTransportHome,
}) async {
  final bootSw = Stopwatch()..start();
  void boot(String phase) =>
      appLogger.i('[boot] +${bootSw.elapsedMilliseconds}ms $phase');

  boot('start');
  // Capture the user's real login-shell PATH early (POSIX desktops) so local
  // PTY children see Homebrew/nvm/~/.local/bin despite sparse GUI PATH.
  unawaited(HostShellPathResolver.warmup());
  final settings = await wireAppSettings(
    preferences: preferences,
    defaultWorkspaceDirectoryFuture: defaultWorkspaceDirectoryFuture,
    boot: boot,
  );
  final appSettings = settings.appSettings;
  final aiFeatureSettingsCubit = settings.aiFeatureSettingsCubit;
  final discoverySettingsCubit = settings.discoverySettingsCubit;
  final sessionPreferencesCubit = settings.sessionPreferencesCubit;
  final defaultWorkspaceDirectory = settings.defaultWorkspaceDirectory;
  final cliExecutableDiscovery = settings.cliExecutableDiscovery;
  final cliToolRegistry = settings.cliToolRegistry;

  configuredGitExecutable = () {
    final path = sessionPreferencesCubit.toolchainPath(
      SessionPreferences.toolchainGit,
    );
    return path.isEmpty ? null : path;
  };

  // Business credentials live on the current home plane (the remote host);
  // SSH login credentials stay on the device vault so reconnection works while
  // the host is down. The scope is assigned once `homeStorage` exists below;
  // the resolver keeps routing correct across home-plane swaps.
  HomeVaultScope? homeVaultScope;
  final vaultCore = await wireVaultCore(
    nativeAppDataPath: nativeAppDataPath,
    homeVaultScope: () => homeVaultScope,
  );
  final sshCredentialStore = vaultCore.sshCredentialStore;
  final vaultService = vaultCore.service;
  final vaultAccess = vaultCore.access;
  final vaultCredentialCapture = vaultCore.credentialCapture;
  final vaultUnlockGate = vaultCore.unlockGate;
  final sshTransport = wireSshTransport(
    sshCredentialStore: sshCredentialStore,
    preferences: preferences,
    vaultAccess: vaultAccess,
    vaultCredentialCapture: vaultCredentialCapture,
  );
  final pairedRelayTunnels = sshTransport.pairedRelayTunnels;
  final sshKnownHostRepo = sshTransport.sshKnownHosts;
  final sshConnectionEvents = sshTransport.sshConnectionEvents;
  final sshClientFactory = sshTransport.sshClientFactory;
  final sshConnectivityGate = sshTransport.connectivityGate;
  final waitForSshProfileRecovery = sshTransport.waitForSshProfileRecovery;

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
  // follow the home context (Android Connect rebinds home onto SSH and would
  // otherwise reload an empty remote catalog → disconnect → gate again).
  final sshProfileRepo = deviceLocalSshProfileRepository(nativeAppDataPath);
  // One-shot move of legacy `ssh_profiles/profiles.json` into the device-local
  // remote-target catalog. Must finish before SshProfileCubit's first load()
  // so the facade sees migrated targets on first render. This is a convenience
  // migration: it must never gate startup. The marker is written only on
  // success, so a failed attempt retries on the next launch.
  try {
    await migrateSshProfiles(
      nativeAppDataPath: nativeAppDataPath,
      localFs: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
      ),
      targetRepo: deviceLocalRemoteTargetRepository(nativeAppDataPath),
    );
  } on Object {
    // Content-free: never the caught error, no file bytes, no rethrow.
    appLogger.w(
      '[boot] ssh profile migration failed; continuing with current targets',
    );
  }
  Future<Map<CliTool, String>> locateRemoteClis(SshProfile profile) async {
    try {
      await sshClientFactory.ensureStorageConnected(profile);
      return await cliExecutableDiscovery.locateRemote(
        run: RemoteCliLocator.runnerForStorage(sshClientFactory, profile),
      );
    } on Object catch (error, stackTrace) {
      if (isSshProfileDown(error)) {
        appLogger.d(
          '[remote-cli] locate waiting for home transport '
          'for ${profile.hostIdentifier}',
          error: error,
          stackTrace: stackTrace,
        );
        return const {};
      }
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
  late final HookCubit hookCubit;
  late final HookRepository hookRepository;
  late final HookImportParser hookImportParser;
  late final HookImportService hookImportService;
  late final TeamHubCubit teamHubCubit;
  late final ExpertHubCubit expertHubCubit;
  late final ExtensionCubit extensionCubit;
  late final SessionRepository sessionRepo;
  late final ChatCubit chatCubit;
  // Nullable so the construction-failure catch can close it: it subscribes to
  // the app-lifetime presence projection, and a discarded shell must not leave
  // that subscription (or its bridge) behind.
  MemberPresenceCubit? memberPresenceCubit;
  late final AutomationCubit automationCubit;
  late final AutomationScheduler automationScheduler;
  late final EditorCubit editorCubit;
  late final SessionLifecycleService sessionLifecycleService;
  late final ConnectionModeService connectionModeService;
  late final Future<void> Function() reinstallStorageContext;

  late final Future<void> Function({bool reinstallSshHome, ReloadLevel level})
  reloadAllAppData;

  late final SshProfileCubit sshProfileCubit;
  late final VaultCubit vaultCubit;
  late final HomeTargetController homeTargetController;
  late final HomePlaneSwitchController homePlaneSwitch;
  late final ShellBootController shellBoot;
  late final HomeWorkspaceUiCache homeWorkspaceUiCache;
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
    remoteCliPathCache: deviceLocalRemoteCliPathCache(nativeAppDataPath),
    vaultCapture: vaultCredentialCapture,
  );

  final platform = await wirePlatformServices(
    nativeAppDataPath: nativeAppDataPath,
    vaultService: vaultService,
    vaultCredentialCapture: vaultCredentialCapture,
    vaultUnlockGate: vaultUnlockGate,
  );
  final githubCredentialsStore = platform.githubCredentials;
  final githubAccountCubit = platform.githubAccountCubit;
  final targetsRepo = platform.targetsRepo;
  final termuxConfigStore = platform.termuxConfigStore;
  final remoteDownloadCatalogCubit = platform.remoteDownloadCatalogCubit;
  final remoteDownloader = platform.remoteDownloader;
  final appUpdateService = platform.appUpdateService;
  final workspaceImportService = platform.workspaceImportService;
  var termuxConfigCache = platform.termuxConfigCache;
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

  // Work-plane point resolver (combined B-first + A-fallback) for every
  // execution chain that resolves a `ssh:<id>` machine: terminals, run/clone
  // spawners, CLI readiness, and work-plane runtime contexts. The B-source
  // workload cubit is only built after wireHomePlane produces homeStorage, so
  // the real combined resolver is installed into this ref below. Consumers
  // created before that point (RemoteCliReadinessService, wireHomePlane's
  // RuntimeContextRegistry) hold this stable forward closure; all lookups are
  // lazy (runtime), long after the ref is set. Until then it falls back to the
  // A-source home resolver — correct for home binding and never consulted for
  // B-only workload hosts at bootstrap.
  SshProfile? Function(String id)? workPlaneResolverRef;
  SshProfile? Function(String id) combinedProfileById =
      (id) => (workPlaneResolverRef ?? sshProfileById)(id);

  /// Identity fields that decide how an SSH home is reached. Deliberately
  /// excludes `updatedAt` and the persisted path cache: a successful connect
  /// writes those back and must not look like a user edit.
  String sshProfileConnectivityKey(SshProfile profile) =>
      '${profile.host}|${profile.port}|${profile.username}|'
      '${profile.authType.name}|${profile.vaultEntryId ?? ''}';

  final remoteCliReadiness = RemoteCliReadinessService(
    registry: cliToolRegistry,
    sshClientFactory: sshClientFactory,
    // Work-plane machines are B-source workload hosts; the combined resolver
    // (installed below) resolves them, with an A fallback for SSH homes.
    profileById: combinedProfileById,
    cliPathOverride: targetsRepo.cliPathOverride,
    setCliPathOverride: targetsRepo.setCliPathOverride,
    acpAdapterPathOverride: targetsRepo.acpAdapterPathOverride,
    setAcpAdapterPathOverride: targetsRepo.setAcpAdapterPathOverride,
  );
  // Late holder: registry is created before AiHistoryLoader; onEvict clears
  // history memory cache when a work-plane target is disposed.
  AiHistoryLoader? aiHistoryLoaderRef;
  final homePlane = await wireHomePlane(
    sshProfileRepo: sshProfileRepo,
    sshProfileById: sshProfileById,
    // Work-plane runtime contexts resolve `ssh:<id>` workload hosts via the
    // combined resolver; home binding stays on the A-source sshProfileById.
    workProfileById: combinedProfileById,
    homeTargetFromId: homeTargetFromId,
    homeTarget: defaultTargetResolver,
    termuxConfigStore: termuxConfigStore,
    termuxConfig: () => termuxConfigCache,
    setTermuxConfig: (config) => termuxConfigCache = config,
    sshClientFactory: sshClientFactory,
    historyLoader: () => aiHistoryLoaderRef,
    nativeAppDataPath: nativeAppDataPath,
    defaultWorkspaceDirectory: defaultWorkspaceDirectory,
    boot: boot,
  );
  // Home-target palette (A source, read-only): used only by the home-target
  // picker. The workspace machine lists use [workspaceTargetRegistry] below.
  final homeTargetRegistry = homePlane.homeTargetRegistry;
  final runtimeContextRegistry = homePlane.runtimeContextRegistry;
  final homeAttempt = homePlane.homeAttempt;
  final initialHome = homePlane.initialHome;
  final deferHomePlaneLoads = homePlane.deferHomePlaneLoads;
  final homeProfileId = homePlane.homeProfileId;
  final isSshHome = homePlane.isSshHome;
  final homeSshProfile = homePlane.homeSshProfile;
  final homeStorage = homePlane.homeStorage;
  // Global B-source workload catalog. Bound to the app-scoped [homeStorage]
  // (not the device-local facade): a home-plane swap re-reads the new plane's
  // server catalog through the cubit's own changes subscription. The device
  // targets only lend vault references — they are never written to the plane.
  final sshWorkloadProfileCubit = SshWorkloadProfileCubit(
    storage: homeStorage,
    deviceTargets: sshProfileRepo.targetRepo,
  );
  unawaited(sshWorkloadProfileCubit.load());
  // One B-source repository instance for resolving workload hosts. Its `_fs` /
  // `_root` are lazy getters over [homeStorage], so a home-plane swap needs no
  // rebuild. [deviceTargets] only lends device vault references to plane rows
  // (via `_deviceVaultRefs`, required for the subsequent connect); it is read
  // only and never written to the plane.
  final planeSshProfileRepo = PlaneSshProfileRepository(
    storage: homeStorage,
    servers: SshServerProfileRepository(storage: homeStorage),
    deviceTargets: sshProfileRepo.targetRepo,
  );
  // Live B-source resolver threaded to every `profileOf` consumer. Reads the
  // catalog cubit's state on each call, so an unreachable plane (empty emit)
  // resolves to null with no error and never falls back to the A source.
  final planeProfileById = planeSshProfileResolver(
    () => sshWorkloadProfileCubit.state.profiles,
  );
  // Combined id resolver for the remote-session / provisioning chain
  // (wireChatSession -> ChatCubit.sshProfileById and
  // buildSessionConnectOrchestrator(profileById:)). B source first (so a
  // B-only workload host can run a remote session), then the device-local A
  // source home profile on a miss. This is a point lookup, NOT the
  // assembleSshHostProfiles list assembler. The A fallback preserves SSH home
  // mode / offline home binding, and ChatSessionShellFactory._profileFor keeps
  // its selected-profile fallback as the last resort (no B-only replacement).
  final sessionProfileById = combinedSshProfileResolver(
    workloadById: planeProfileById,
    homeById: sshProfileById,
  );
  // Install the real combined resolver into the forward ref declared above the
  // home plane. From here on, combinedProfileById (held by RemoteCliReadiness
  // and the work-plane runtime-context registry) resolves B-first + A-fallback.
  // Kept as one resolver with the remote-session chain (sessionProfileById).
  workPlaneResolverRef = sessionProfileById;
  // Read-oriented point-lookup repository for work-plane execution chains
  // (terminals, run/clone SSH spawners, folder liveness). findById checks the
  // B workload catalog first, then the A home-binding catalog; loadAll is
  // B-only so machine lists never merge the two independent catalogs. Machine
  // enumeration stays with workspaceTargetRegistry (B, targets.json).
  final combinedSshProfileRepo = CombinedSshProfileRepository(
    storage: homeStorage,
    workload: planeSshProfileRepo,
    home: sshProfileRepo,
  );
  // Workspace machine catalog (B source). All workspace/mixed-workspace
  // machine pickers, the directory picker, and the team-generation target
  // probe resolve through this registry, so they list the home-plane workload
  // hosts (SSH 服务器页) — never the device-local home-binding profiles
  // (远程连接页). It reconciles the persisted `targets.json` (CLI path /
  // ACP adapter overrides live there) against the B catalog. The home-target
  // picker deliberately does NOT use it; that palette is [homeTargetRegistry].
  final workspaceTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: planeSshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
    hasTermuxConfig: () => termuxConfigCache != null,
  );
  final scope = homePlane.scope;
  homeWorkspaceUiCache = homePlane.homeWorkspaceUiCache;
  // The live home identity. [homeProfileId] is the boot-time snapshot; every
  // connection hook below reads this mutable value so a home switch inside the
  // running shell retargets the cubit/coordinator instead of retrying the
  // abandoned profile until the next restart.
  var activeHomeProfileId = isSshHome ? homeProfileId : null;
  homeVaultScope = scope;
  await scope.prepare();
  // Copy this device's business entries onto the plane it belongs to — also
  // when the plane is local: a desktop acting as the home for a phone must
  // publish them as `<home>/vault/business.json`, or the phone can never see
  // them (its own keychain is not readable remotely). SSH login credentials
  // are skipped by the migration and stay device-local.
  unawaited(
    migrateBusinessVaultEntries(device: vaultService, home: scope.service),
  );

  // Declared before the VaultCubit closure that captures it: the closure only
  // runs on a later unlock/encrypt, after the importer is assigned below.
  late final VaultLegacyImportService legacyImporter;
  vaultCubit = wireVaultCubit(
    homeStorage: homeStorage,
    sshProfileRepo: sshProfileRepo,
    githubAccountCubit: githubAccountCubit,
    vaultService: vaultService,
    legacyImporter: () => legacyImporter,
  );

  // Managed Providers belong to the home/control plane. Construct this graph
  // once after the home context is installed; workspace tabs only consume the Cubits
  // exposed by AppShell and never create provider-specific state.
  final managedProv = wireManagedProviders(
    storage: homeStorage,
    vaultCubit: () => vaultCubit,
    vaultAccess: vaultAccess,
    vaultService: vaultService,
    vaultCredentialCapture: vaultCredentialCapture,
    vaultUnlockGate: vaultUnlockGate,
    sshProfiles: sshProfileRepo,
    githubCredentials: githubCredentialsStore,
    sessionPreferences: sessionPreferencesCubit,
    boot: boot,
    repositoryOverride: managedProviderRepository,
    usageRepositoryOverride: managedProviderUsageRepository,
    secretStoreOverride: managedProviderSecretStore,
    usageRegistryOverride: managedProviderUsageRegistry,
    usageCoordinatorOverride: managedProviderUsageCoordinator,
    cubitOverride: managedProviderCubit,
    usageCubitOverride: managedProviderUsageCubit,
    httpClientOverride: managedProviderUsageHttpClient,
    cliCredentialsOverride: managedProviderCliCredentials,
  );
  appProviderCubit = managedProv.appProviderCubit;
  final managedProviderControlPlane = managedProv.controlPlane;
  final managedProviderControlPlaneLease = managedProv.controlPlaneLease;
  final resolvedManagedProviderCubit = managedProv.providerCubit;
  final resolvedManagedProviderUsageCubit = managedProv.usageCubit;
  final hydrateManagedProviderData = managedProv.hydrate;
  final openCredentialLoginUrl = managedProv.openCredentialLoginUrl;
  // The control plane exposes the graph instances it owns; alias the names the
  // rest of the shell (and the lease teardown) reads. Same identities as the
  // ones constructed above.
  final resolvedManagedProviderRepository =
      managedProviderControlPlane.providerRepository;
  final resolvedManagedProviderUsageRepository =
      managedProviderControlPlane.usageRepository;
  final resolvedManagedProviderSecretStore =
      managedProviderControlPlane.secretStore;
  final resolvedManagedProviderUsageRegistry =
      managedProviderControlPlane.usageRegistry;
  final resolvedManagedProviderUsageCoordinator =
      managedProviderControlPlane.usageCoordinator;

  final vaultState = wireVaultState(
    homeStorage: homeStorage,
    sshProfileRepo: sshProfileRepo,
    githubAccountCubit: githubAccountCubit,
    githubCredentialsStore: githubCredentialsStore,
    vaultService: vaultService,
    sshCredentialStore: sshCredentialStore,
    vaultCredentialCapture: vaultCredentialCapture,
    nativeAppDataPath: nativeAppDataPath,
    resolvedManagedProviderRepository: resolvedManagedProviderRepository,
    resolvedManagedProviderSecretStore: resolvedManagedProviderSecretStore,
    vaultCubit: vaultCubit,
    homeVaultScope: () => homeVaultScope,
  );
  legacyImporter = vaultState.importer;
  final vaultPlaneSyncSub = vaultState.planeSyncSubscription;

  // Retried-bootstrap teardown seam: when wiring below fails after the
  // catalog runtime is assembled, its mutation bus must unregister its relay
  // from the app-lifetime central dispatcher, so a retried bootstrap's
  // events never reach this (dead) shell's listeners.
  CatalogRuntime? catalogRuntime;
  // Created after the bounded home attempt and seeded synchronously; declared
  // here so the wiring-failure path can close a discarded instance.
  HomeConnectionCubit? homeConnectionCubit;
  // Watches the current home profile for identity edits so saving a fixed
  // host/port re-arms the connection instead of leaving the page dead.
  StreamSubscription<SshProfileState>? homeProfileWatchSub;
  StreamSubscription<SshHomeConnectivityState>? homeConnectivitySub;
  String? watchedHomeProfileConnectivityKey;
  // Declared outside the try so the wiring-failure path can tear down the
  // subscriptions/inbox/authority of a discarded shell.
  StreamSubscription<AttentionEvent>? attentionSub;
  AttentionInbox? attentionInbox;
  SessionAuthority? sessionAuthority;

  try {
    connectionModeService = ConnectionModeService(
      defaultTargetResolver: defaultTargetResolver,
      hasSshProfiles: () => sshProfileCubit.state.hasProfiles,
    );

    // Re-resolve the home context (e.g. after an ssh profile's details change):
    // drop the cached wrapper and rebuild it, but keep the live SSH storage pool.
    reinstallStorageContext = () async {
      await managedProviderControlPlane.invalidateForStorageContextChange();
      await runtimeContextRegistry.rebindHome(defaultTargetResolver());
      // Fresh wrapper for the same target: swap publishes it and retires the
      // stale wrapper, but the retire is a no-op in the registry (the cached
      // instance is already the fresh one) so the SSH pool stays connected.
      await homeStorage.swap(runtimeContextRegistry.home());
      await homePlaneSwitch.persistSshHomePathCacheIfLive();
    };

    wireCliBootstrap(
      cliToolRegistry: cliToolRegistry,
      homeStorage: homeStorage,
      appProviderCubit: appProviderCubit,
      sessionPreferencesCubit: sessionPreferencesCubit,
      remoteDownloader: remoteDownloader,
      openCredentialLoginUrl: openCredentialLoginUrl,
    );

    final skillCatalog = wireSkillCatalog(storage: homeStorage);
    final skillRepo = skillCatalog.skillRepository;
    final skillInstallService = skillCatalog.skillInstallService;
    final skillAcquisitionEngine = skillCatalog.skillAcquisitionEngine;

    final llmConfig = wireLlmConfig(
      appSettings: appSettings,
      storage: homeStorage,
      sessionPreferences: sessionPreferencesCubit,
      connectionMode: () => connectionModeService,
      sshProfiles: () => sshProfileCubit,
      sshClientFactory: sshClientFactory,
    );
    llmConfigCubit = llmConfig.cubit;
    final llmConfigPathOverrideForLaunch = llmConfig.pathOverrideForLaunch;

    final extensionCatalog = wireExtensionCatalog(storage: homeStorage);
    final extensionRepository = extensionCatalog.extensionRepository;
    final workspaceProjectConfigRepository =
        extensionCatalog.workspaceProjectConfigRepository;

    final identityWiring = wireIdentityRepository(storage: homeStorage);
    identityRepository = identityWiring.identityRepository;

    final cliPresetsRepo = wireCliPresets(storage: homeStorage)
        .cliPresetsRepository;

    final sessionState = wireSessionState(
      storage: homeStorage,
      runtimeContexts: runtimeContextRegistry,
      homeTarget: defaultTargetResolver,
      extensionRepository: extensionRepository,
      workspaceConfig: workspaceProjectConfigRepository,
      cliPresets: cliPresetsRepo,
      cliToolRegistry: cliToolRegistry,
      skillRepository: skillRepo,
      sessionPreferences: sessionPreferencesCubit,
      cliPresetsCubit: () => cliPresetsCubit,
      // Workspace MCP / remote-session `profileOf` resolves from the home
      // plane (B source). The device-local A source stays for home binding.
      sshProfileById: planeProfileById,
      identityRepository: () => identityRepository,
    );
    sessionLifecycleService = sessionState.sessionLifecycleService;
    sessionRepo = sessionState.sessionRepo;
    final homeIndex = wireHomeIndexPrefetch(
      bootstrapCubit: bootstrapCubit,
      connectionMode: () => connectionModeService,
      nativePrefetch: homeIndexPrefetchFuture,
      sessions: () => sessionRepo,
      identities: () => identityRepository,
      boot: boot,
    );
    final homeIndexPrefetch = homeIndex.homeIndexPrefetch;
    final pluginMcp = wirePluginMcp(storage: homeStorage);
    final pluginRepository = pluginMcp.pluginRepository;
    final mcpRepository = pluginMcp.mcpRepository;
    hookRepository = HookRepository(
      fs: homeStorage.fs,
      teampilotRoot: homeStorage.paths.basePath,
    );
    hookImportParser = HookImportParser(
      fs: homeStorage.fs,
      teampilotRoot: homeStorage.paths.basePath,
      homeDir: Platform.environment['HOME'],
    );
    hookImportService = HookImportService(repository: hookRepository);
    identityProvisioner = LaunchProfileProvisioner(
      repository: identityRepository,
    );
    teamCubit = LaunchProfileCubit(
      repository: identityRepository,
      sessionRepository: sessionRepo,
      identityProvisioner: identityProvisioner,
      storage: homeStorage,
      executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
      llmConfigPathOverride: llmConfigPathOverrideForLaunch,
      storageRootsResolver: () async => homeStorage.context,
      lifecycleService: sessionLifecycleService,
      pluginRepository: pluginRepository,
      installedPluginsLoader: () => pluginRepository.loadAll(),
      mcpLinker: ProfileMcpLinkerService(storage: homeStorage),
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

    final sessionUsage = wireSessionUsage(
      storage: homeStorage,
      registry: cliToolRegistry,
      sessions: sessionRepo,
      teams: identityRepository,
    );
    final cursorUsageApiClient = sessionUsage.cursorUsageApiClient;
    final sessionUsageCubit = sessionUsage.sessionUsageCubit;
    final warmStartupCaches = sessionUsage.warmStartupCaches;
    final notificationCubit = sessionUsage.notificationCubit;
    final notificationBootstrap = sessionUsage.notificationBootstrap;
    final progressActivityCubit = sessionUsage.progressActivityCubit;

    final installWiring = await wireInstallJobs(
      storage: homeStorage,
      // Repo clone / CLI install run on work-plane `ssh:<id>` targets (B
      // source). findById resolves the B workload host first, with the A home
      // binding as fallback; loadAll stays B-only.
      sshProfiles: combinedSshProfileRepo,
      sshClientFactory: sshClientFactory,
      runtimeContexts: runtimeContextRegistry,
      homeTarget: defaultTargetResolver,
      progressActivity: progressActivityCubit,
      cliToolRegistry: cliToolRegistry,
      sessionPreferences: sessionPreferencesCubit,
      importService: workspaceImportService,
      appUpdateService: appUpdateService,
      appSettings: appSettings,
      deferHomePlaneLoads: deferHomePlaneLoads,
      appLogRoot: nativeAppDataPath,
      // CLI install jobs probe/install binaries on work-plane hosts.
      sshProfileById: combinedProfileById,
    );
    final repoCloneSshSpawner = installWiring.repoCloneSshSpawner;
    final repoCloneCubit = installWiring.repoCloneCubit;
    final installJobRegistry = installWiring.installJobRegistry;
    final skillRegistryConfigService = installWiring.skillRegistryConfigService;
    final skillRegistryConfig = installWiring.skillRegistryConfig;
    skillCubit = SkillCubit(
      skillRepo,
      storage: homeStorage,
      registryConfigService: skillRegistryConfigService,
      initialSources: SkillRegistryFactory.build(
        skillRegistryConfig,
        repository: skillRepo,
      ),
      rebuildSources: (config) =>
          SkillRegistryFactory.build(config, repository: skillRepo),
      acquisitionEngine: skillAcquisitionEngine,
      onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
      installJobRegistry: installJobRegistry,
      discoverySettings: discoverySettingsCubit,
    );
    pluginCubit = PluginCubit(
      repository: pluginRepository,
      storage: homeStorage,
      installService: pluginRepository.install,
      repoService: pluginRepository.repos,
      diskCache: PluginRepoDiskCacheService(
        filesystem: homeStorage.fs,
        teampilotRoot: homeStorage.paths.basePath,
      ),
      onPluginUninstalled: teamCubit.removePluginFromAllTeams,
      onPluginUpdated: teamCubit.syncTeamsUsingPlugin,
      installJobRegistry: installJobRegistry,
      discoverySettings: discoverySettingsCubit,
    );
    extensionCubit = ExtensionCubit(
      extensionRepository,
      ExtensionAcquisitionEngine(),
      installJobRegistry: installJobRegistry,
    );
    cliPresetsCubit = CliPresetsCubit(repository: cliPresetsRepo);
    final hubs = await wireHubs(
      nativeAppDataPath: nativeAppDataPath,
      storage: homeStorage,
      teamCubit: teamCubit,
      workspaceConfig: workspaceProjectConfigRepository,
      mcpRepository: mcpRepository,
      hookRepository: hookRepository,
      skillCubit: skillCubit,
      pluginCubit: pluginCubit,
      skillRepository: skillRepo,
      pluginRepository: pluginRepository,
      installJobRegistry: installJobRegistry,
      deferHomePlaneLoads: deferHomePlaneLoads,
    );
    mcpCubit = hubs.mcpCubit;
    hookCubit = hubs.hookCubit;
    teamHubCubit = hubs.teamHubCubit;
    expertHubCubit = hubs.expertHubCubit;
    final expertHubCatalog = hubs.expertHubCatalog;
    final expertCapabilityResolver = hubs.expertCapabilityResolver;
    final localExpertStore = hubs.localExpertStore;
    final sessionRuntimePlanBuilder = hubs.sessionRuntimePlanBuilder;
    sessionLifecycleService.attachRuntimePlanBuilder(sessionRuntimePlanBuilder);

    final workspaces = wireWorkspaces(
      preferences: preferences,
      storage: homeStorage,
      extensionRepository: extensionRepository,
      workspaceConfig: workspaceProjectConfigRepository,
      sessionLifecycleService: () => sessionLifecycleService,
      // Workspace run targets are `ssh:<id>` workload hosts (B source).
      sshProfiles: combinedSshProfileRepo,
      sshClientFactory: sshClientFactory,
      homeTarget: defaultTargetResolver,
      chatCubit: () => chatCubit,
    );
    final layoutCubit = workspaces.layoutCubit;
    final floatingWorkspaceCubit = workspaces.floatingWorkspaceCubit;
    final floatingWorkspacePersistence =
        workspaces.floatingWorkspacePersistence;
    final workspaceToolsCubit = workspaces.workspaceToolsCubit;
    final workspaceTerminalRegistry = workspaces.workspaceTerminalRegistry;
    final gitRepoStore = workspaces.gitRepoStore;
    final workspaceFileTreeStore = workspaces.workspaceFileTreeStore;
    final workspaceSearchIndexes = workspaces.workspaceSearchIndexes;
    final workspaceWorktreeRegistry = workspaces.workspaceWorktreeRegistry;
    final workspaceSessionGroupsRegistry =
        workspaces.workspaceSessionGroupsRegistry;
    final workspaceToolsScopeRegistry = workspaces.workspaceToolsScopeRegistry;
    final workspaceRunRegistry = workspaces.workspaceRunRegistry;
    final configCubit = workspaces.configCubit;
    final connect = await wireConnectBackend(
      nativeAppDataPath: nativeAppDataPath,
    );
    ConnectCubit? connectCubit = connect.connectCubit;
    ConnectSshBackend? embeddedSshServer = connect.embeddedSshServer;
    ConnectSshBackend? systemSshdBackend = connect.systemSshdBackend;
    PairedDeviceStore? connectDeviceStore = connect.connectDeviceStore;
    final commands = wireCommands(
      storage: homeStorage,
      // Workspace terminal transports / shells connect to work-plane `ssh:<id>`
      // workload hosts (B source), with the A home binding as fallback.
      sshProfileRepo: combinedSshProfileRepo,
      sshCredentialStore: sshCredentialStore,
      sshKnownHostRepo: sshKnownHostRepo,
      sshClientFactory: sshClientFactory,
      sessionPreferencesCubit: sessionPreferencesCubit,
      homeTarget: defaultTargetResolver,
      sshProfileById: combinedProfileById,
    );
    final commandBus = commands.commandBus;
    final shortcutCubit = commands.shortcutCubit;
    final workspaceChromeCommands = commands.workspaceChromeCommands;
    final runCommandHost = commands.runCommandHost;
    final workspaceSearchHost = commands.workspaceSearchHost;
    final workspaceContentSearchHost = commands.workspaceContentSearchHost;
    final uiZoomBaseline = commands.uiZoomBaseline;
    final transportFactory = commands.transportFactory;
    final workspaceShellConnector = commands.workspaceShellConnector;
    final workspaceTerminalSessionOps = commands.workspaceTerminalSessionOps;
    final workspaceTerminalRunService = commands.workspaceTerminalRunService;
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
              termuxWorkOpsBlockedMessage:
                  TermuxWorkOpsMessage.disconnectedBlocked,
            ),
      ),
    );

    final automationRepo = buildAutomationRepository(storage: homeStorage);
    final agentEventPlane = await wireAgentEventPlane(storage: homeStorage);
    final teammateBusMcpGateway = agentEventPlane.teammateBusMcpGateway;
    final askUserAnswerPendingStore = agentEventPlane.askUserAnswerPendingStore;
    final askUserQuestionAnswerService =
        agentEventPlane.askUserQuestionAnswerService;
    final generalPermissionRequestGate =
        agentEventPlane.generalPermissionRequestGate;
    final exitPlanModeApprovalService =
        agentEventPlane.exitPlanModeApprovalService;
    final agentAttentionCubit = agentEventPlane.agentAttentionCubit;
    final seatLeaseCubit = agentEventPlane.seatLeaseCubit;
    final agentStatusSeatLookup = agentEventPlane.agentStatusSeatLookup;

    catalogRuntime = wireCatalogRuntime(
      storage: homeStorage,
      sessions: () => sessionRepo,
      runtimeContexts: runtimeContextRegistry,
      skillRepository: skillRepo,
      skillInstall: skillInstallService,
      skillEngine: skillAcquisitionEngine,
      pluginRepository: pluginRepository,
      mcpRepository: mcpRepository,
      workspaceConfig: workspaceProjectConfigRepository,
      skillRegistryConfig: skillRegistryConfigService,
      launchProfiles: () => teamCubit,
    );
    teammateBusMcpGateway.attachCatalogHandler(
      catalogRuntime.handler,
      resolveSession: catalogRuntime.resolveSession,
    );
    final grokBootstrap = cliToolRegistry.bootstrap?.entry<GrokBootstrapEntry>(
      CliTool.grok,
    );
    if (grokBootstrap != null) {
      teammateBusMcpGateway.attachCredentialLeaseEndpoint(
        grokBootstrap.leaseEndpoint,
      );
    }
    teammateBusMcpGateway.attachSessionSshMcp(
      SessionSshMcpHttpAdapter(
        operations: SessionSshMcpOperations(
          executor: SshClientFactorySessionSshMcpExecutor(sshClientFactory),
        ),
        resolveContext: (sessionId, memberId) async {
          final session = await sessionRepo.findById(sessionId);
          if (session == null) return null;
          final workspace = (await sessionRepo.loadWorkspacesIndex())
              .firstWhereOrNull((w) => w.workspaceId == session.workspaceId);
          if (workspace == null) return null;
          final profileIds = <String>{};
          for (final folder in workspace.folders) {
            final profileId = sshProfileIdOfId(folder.targetId);
            if (profileId != null) profileIds.add(profileId);
          }
          // Resolve workspace SSH folders from the home-plane (B source)
          // catalog only. findById -> loadAll lends the matching device vault
          // reference (required for the subsequent connect); a dropped plane
          // reads as empty: no error surfaced, no A-source fallback.
          final profiles = <String, SshProfile>{};
          try {
            for (final id in profileIds) {
              final profile = await planeSshProfileRepo.findById(id);
              if (profile != null) profiles[id] = profile;
            }
          } on Object catch (error, stackTrace) {
            appLogger.w(
              '[ssh-mcp] home-plane catalog read failed; '
              'resolving no SSH MCP targets',
              error: error,
              stackTrace: stackTrace,
            );
            profiles.clear();
          }
          return resolveSessionSshMcpContext(
            session: session,
            workspace: workspace,
            profileOf: (id) => profiles[id],
            localFs: homeStorage.fs,
            localUsesPosixPaths: homeStorage.usesPosixPaths,
            memberId: memberId,
          );
        },
      ),
    );
    catalogRuntime.bus.listen().listen((event) {
      // Automation writes are refreshed by the automation cubit's own
      // subscription; skip the unrelated catalog reloads for them.
      if (event.kind == 'automation') return;
      unawaited(skillCubit.loadAll());
      unawaited(pluginCubit.load());
      unawaited(mcpCubit.loadAll());
      unawaited(WorkspaceProjectConfigCubit.reloadLive(event.workspaceId));
    });

    // App-scoped durable prompt-delivery composition (Task 7): the coordinator
    // is created after ChatCubit because its fenced terminal adapter needs the
    // tab store; the lazy getter below is resolved when the session runtime is
    // first touched, which only happens after bootstrap completes.
    PromptDeliveryCoordinator? appScopedPromptDeliveries;
    chatCubit = wireChatSession(
      storage: homeStorage,
      sessions: () => sessionRepo,
      lifecycle: () => sessionLifecycleService,
      runtimeContexts: runtimeContextRegistry,
      cliToolRegistry: cliToolRegistry,
      sessionPreferences: sessionPreferencesCubit,
      identities: () => identityRepository,
      sshProfiles: () => sshProfileCubit,
      promptDeliveries: () => appScopedPromptDeliveries,
      teammateBusMcpGateway: teammateBusMcpGateway,
      agentStatusSeatLookup: agentStatusSeatLookup,
      agentAttentionCubit: agentAttentionCubit,
      seatLeaseCubit: seatLeaseCubit,
      askUserAnswerPendingStore: askUserAnswerPendingStore,
      askUserQuestionAnswerService: askUserQuestionAnswerService,
      generalPermissionRequestGate: generalPermissionRequestGate,
      exitPlanModeApprovalService: exitPlanModeApprovalService,
      automationRepository: automationRepo,
      layoutCubit: layoutCubit,
      targets: targetsRepo,
      transportFactory: transportFactory,
      // Combined B-first + A-fallback id resolver so B-only workload hosts
      // can run remote sessions / provisioning (Task 4 wiring gap).
      sshProfileById: sessionProfileById,
      defaultTargetResolver: defaultTargetResolver,
      sshClientFactory: sshClientFactory,
      runtimePlanBuilder: sessionRuntimePlanBuilder,
      remoteCliReadiness: remoteCliReadiness,
      installJobRegistry: installJobRegistry,
      termuxGate: () => termuxGateCubit,
    );
    // Terminal-less ACP chat copy: l10n is resolved per-call from the
    // platform locale (the launch service reads it at session connect).
    chatCubit.acpChatStringsResolver = (tool) {
      final locale = PlatformDispatcher.instance.locale;
      final l10n = lookupAppLocalizations(
        basicLocaleListResolution([locale], appLocalizationsSupportedLocales),
      );
      final adapter = tool == CliTool.codex
          ? l10n.codex.acpLaunchFailedAdapter
          : l10n.acp.launchFailedAdapter;
      final notLoggedIn = tool == CliTool.codex
          ? l10n.codex.acpChatNotLoggedIn
          : l10n.acp.chatNotLoggedIn;
      return AcpChatStrings(
        launchFailedVersion: l10n.acp.launchFailedVersion,
        launchFailedAdapter: adapter,
        launchFailed: l10n.acp.chatLaunchFailed(
          cliName: l10n.appProviderToolLabel(tool),
        ),
        turnFailed: l10n.acp.chatTurnFailed,
        processExited: l10n.acp.chatProcessExited(
          cliName: l10n.appProviderToolLabel(tool),
        ),
        notLoggedIn: notLoggedIn,
        sessionOpenFailed: l10n.acp.chatSessionOpenFailed(
          cliName: l10n.appProviderToolLabel(tool),
        ),
      );
    };
    final agentRuntimeWiring = wireAgentRuntime(
      storage: homeStorage,
      gateway: agentEventPlane.agentEventGateway,
      projections: agentEventPlane.runtimeProjections,
      chatCubit: () => chatCubit,
      sessionLifecycleService: () => sessionLifecycleService,
    );
    appScopedPromptDeliveries = agentRuntimeWiring.promptDeliveries;
    final agentRuntime = agentRuntimeWiring.agentRuntime;

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
    final workbenchCubit = WorkbenchCubit();

    // Per-workbench split-layout persistence (Task 9): one debounced save
    // subscription for every workspace; restore is triggered per workspace
    // after its sessions rehydrate (WorkspacePage activation chain).
    final workbenchLayoutPersistence = WorkbenchLayoutPersistence(
      workbench: workbenchCubit,
      chat: chatCubit,
      storage: homeStorage,
      terminalRegistry: workspaceTerminalRegistry,
      restoreTerminalSessions: () =>
          layoutCubit.state.preferences.restoreTerminalSessions,
    )..start();

    // Team-generation workflow graph. Built after chatCubit and workbenchCubit
    // so the cubit session port can bind both; services receive interfaces only.
    TeamGenerationGraph? teamGenerationGraph;
    try {
      final graph = buildTeamGenerationGraph(
        chatCubit: chatCubit,
        workbenchCubit: workbenchCubit,
        teamCubit: teamCubit,
        sessionRepo: sessionRepo,
        identityRepository: identityRepository,
        cliToolRegistry: cliToolRegistry,
        targetRegistry: workspaceTargetRegistry,
        remoteCliReadiness: remoteCliReadiness,
        storage: homeStorage,
        catalogRegistry: catalogRuntime.registry,
        expertHubCatalog: expertHubCatalog,
      );
      TeamGenerationGraphBootstrap(
        graph: graph,
        port: TeamGenerationGraphBootstrapPort(
          setTokenIssuer: chatCubit.setTeamGenerationTokenIssuer,
          attachResourceProviderResolver:
              sessionLifecycleService.attachResourceProviderResolver,
          attachComposerHandler: ({required handler, required authorizer}) {
            teammateBusMcpGateway.attachTeamComposerHandler(
              handler: handler,
              authorizer: authorizer,
            );
          },
          setComposerPrincipalResolver:
              teammateBusMcpGateway.setTeamComposerPrincipalResolver,
          attachCatalogGenerationStager:
              catalogRuntime.handler.attachGenerationMutationHandler,
        ),
        principalResolver: (sessionId) async {
          final session = await sessionRepo.findById(sessionId);
          if (session == null ||
              session.purpose != SessionPurpose.teamGeneration ||
              session.workflowId.isEmpty) {
            return null;
          }
          return ComposerPrincipal(
            sessionId: session.sessionId,
            workspaceId: session.workspaceId,
            workflowId: session.workflowId,
          );
        },
      ).attach();
      teamGenerationGraph = graph;
    } on Object catch (e, st) {
      appLogger.w(
        '[team-generation] wiring failed; generation disabled: $e\n$st',
      );
    }

    registerLayoutCommands(
      commandBus,
      layoutCubit,
      uiZoomBaseline: () => uiZoomBaseline.value,
      composeLanding: () => workbenchCubit.centerLandingActive(
        chatCubit.tabStore.activeWorkspaceId,
      ),
      onTogglePanel: openFloatingNewTerminal,
    );

    // Pushed presence events: the projection is app-lifetime (one per app, not
    // per bootstrap retry); the bridge is owned by this shell's cubit, which
    // disposes it on close — so a discarded shell can never kill a shared edge.
    memberPresenceCubit = MemberPresenceCubit(
      storage: homeStorage,
      presenceProjection: presenceProjection,
      presenceBridge: presenceSink == null || connectionModeService.isSshMode
          ? null
          : PresenceEventBridge(sink: presenceSink),
    );
    chatCubit.bindPresenceCubit(memberPresenceCubit);

    // Single owner of SSH home connectivity state. It owns the retry
    // coordinator (exposed below for DI + the terminal panel) and publishes
    // one state stream that both connection cubits project from.
    final sshHomeConnectivity = SshHomeConnectivitySupervisor(
      factory: sshClientFactory,
      events: sshConnectionEvents,
      profileResolver: sshProfileById,
      gate: sshConnectivityGate,
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
    // The coordinator stays available to RepositoryProvider consumers and to
    // the terminal panel, but is now owned by the supervisor.
    final sshProfileConnectionCoordinator = sshHomeConnectivity.coordinator;

    // Paired profiles (QR scan) try lan → extra → relay and persist the winner
    // without invalidating the pool connection that just succeeded.
    final pairedConnectAttempt = PairedConnectAttempt(
      saveLastGood: (updated) async {
        await sshProfileRepo.save(updated);
        await sshProfileCubit.load();
      },
      openRelayTunnel: (profile, endpoint) =>
          pairedRelayTunnels.ensureSshTunnel(profile),
    );

    final sshConnectionCubit = SshConnectionCubit(
      factory: sshClientFactory,
      coordinator: sshProfileConnectionCoordinator,
      connectivity: sshHomeConnectivity,
      selectProfileOnConnect: Platform.isAndroid
          ? (id) => applyAndroidSshConnectHome(
              profileId: id,
              selectHome: homeTargetController.select,
              selectProfile: sshProfileCubit.selectProfile,
            )
          : null,
      pairedConnectAttempt: pairedConnectAttempt,
      relayTunnels: pairedRelayTunnels,
    );

    TeamProfile? teamById(String teamId) =>
        LaunchProfileSelectors.teamById(teamCubit.state, teamId);
    CliPreset? resolveCliPreset(String presetId) =>
        cliPresetsCubit.state.presetById(presetId);

    final scheduleCalculator = AutomationScheduleCalculator();
    final automation = wireAutomationRuntime(
      repository: automationRepo,
      scheduleCalculator: scheduleCalculator,
      catalogRuntime: catalogRuntime,
      chatCubit: () => chatCubit,
      sessionRepository: () => sessionRepo,
      sessionPreferences: sessionPreferencesCubit,
      teamById: teamById,
      resolveCliPreset: resolveCliPreset,
      homeTarget: defaultTargetResolver,
      sshSpawner: repoCloneSshSpawner,
    );
    automationCubit = automation.automationCubit;
    automationScheduler = automation.automationScheduler;
    final automationCatalogSub = automation.catalogSubscription;

    final sessionRuntime = await wireSessionRuntime(
      deviceStorage: deviceLocalHomeStorage(nativeAppDataPath),
      chat: () => chatCubit,
      cliPresets: () => cliPresetsCubit,
      lifecycle: () => sessionLifecycleService,
      connectionMode: () => connectionModeService,
      cliToolRegistry: cliToolRegistry,
      workbench: workbenchCubit,
      workspaceSearchIndexes: workspaceSearchIndexes,
      notificationCubit: notificationCubit,
      notifyOnSessionIdle: () =>
          sessionPreferencesCubit.state.preferences.notifyOnSessionIdle,
      isExpectedFailure: isSshProfileDown,
      waitForRecovery: waitForSshProfileRecovery,
      onHistoryLoaderCreated: (loader) => aiHistoryLoaderRef = loader,
    );
    final mailboxCubit = sessionRuntime.mailboxCubit;
    final boardCubit = sessionRuntime.boardCubit;
    final aiHistoryCubit = sessionRuntime.aiHistoryCubit;
    final sessionRemoteActivityCubit =
        sessionRuntime.sessionRemoteActivityCubit;
    sessionAuthority = sessionRuntime.sessionAuthority;
    final sessionActivitySource = sessionRuntime.activitySource;
    final sessionProtocolController = sessionRuntime.protocolController;
    final sessionRemoteRefreshSub = sessionRuntime.sessionRemoteRefreshSub;
    final contentInvalidationSub = sessionRuntime.contentInvalidationSub;
    final contentStreamSub = sessionRuntime.contentStreamSub;
    attentionInbox = sessionRuntime.attentionInbox;
    attentionSub = sessionRuntime.attentionSub;
    void reloadHistorySeat(String sessionId) {
      unawaited(aiHistoryCubit.softReloadIfSession(sessionId));
    }

    chatCubit.onSessionHistoryStale = (sessionId) {
      reloadHistorySeat(sessionId);
      if (connectionModeService.isLocalMode) {
        sessionAuthority!.publishContentInvalidated(sessionId: sessionId);
      }
    };
    chatCubit.onSessionCreated = (session) {
      final entry = SessionListEntry.fromSession(session).toJson();
      if (connectionModeService.isLocalMode) {
        sessionAuthority!.publishSessionList(
          workspaceId: session.workspaceId,
          upserted: [entry],
        );
      } else if (connectionModeService.isSshMode) {
        unawaited(
          sessionProtocolController.createSession(
            workspaceId: session.workspaceId,
            sessionId: session.sessionId,
            entry: entry,
          ),
        );
      }
    };
    chatCubit.onSessionRemoved = (workspaceId, sessionId) {
      if (connectionModeService.isLocalMode) {
        sessionAuthority!.publishSessionList(
          workspaceId: workspaceId,
          removed: [sessionId],
        );
      } else if (connectionModeService.isSshMode) {
        unawaited(
          sessionProtocolController.removeSession(
            workspaceId: workspaceId,
            sessionId: sessionId,
          ),
        );
      }
    };
    chatCubit.onHistorySeatsDispose = aiHistoryCubit.disposeSeatsForSession;
    // Landing seed routing: pods own the store; these sinks are the fallback.
    chatCubit.onSeedHistoryPending = (sid, mid, text) => aiHistoryCubit
        .seedPendingUser(sessionId: sid, memberId: mid, text: text);
    chatCubit.onCancelSeedHistoryPending = (sid, text) =>
        aiHistoryCubit.cancelSeedPendingUser(sessionId: sid, text: text);

    final appUpdateCubit = AppUpdateCubit(
      service: appUpdateService,
      settings: appSettings,
      installJobRegistry: installJobRegistry,
      appUpdateRunner: AppUpdateInstallJobRunner(service: appUpdateService),
    );

    boot('loading layout');
    await layoutCubit.load();
    floatingWorkspacePersistence.hydrateFromLayout();
    workspaceToolsCubit.hydrate(
      RightToolOpenSet.sanitize(
        openIds: layoutCubit.state.preferences.rightToolOpenIds,
        selectedId: layoutCubit.state.preferences.rightToolSelectedId,
        dismissedIds: layoutCubit.state.preferences.rightToolDismissedIds,
      ),
    );
    floatingWorkspacePersistence.bind();
    if (!deferHomePlaneLoads) {
      await shortcutCubit.load();
      unawaited(
        notificationBootstrap().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          // Background warm-up off the critical path: keep the queue alive
          // instead of surfacing an uncaught async error.
          appLogger.w(
            '[boot] notification bootstrap failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
    boot('layout ready (home index prefetched in background)');
    applyWorkspaceEntryMode(
      layoutCubit.state.preferences.workspaceEntryMode,
      lastOpenedWorkspaceId:
          layoutCubit.state.preferences.lastOpenedWorkspaceId,
    );
    boot('buildAppShell complete');
    bootstrapCubit?.markShellReady();
    boot('buildAppShell shell ready');

    reloadAllAppData =
        ({
          bool reinstallSshHome = true,
          ReloadLevel level = ReloadLevel.full,
        }) async {
          await managedProviderControlPlane.invalidateForStorageContextChange();
          switch (level) {
            // Minor invalidation: rerun the home index only. Cubit loads are
            // single-flight/idempotent and already warm, so the auxiliary chain
            // (providers, skills, plugins, MCP, extensions) and workspace data
            // reload are skipped.
            case ReloadLevel.indexOnly:
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
                storage: homeStorage,
                home: defaultTargetResolver(),
                reinstallSshHome: reinstallSshHome,
                expertHubCatalog: expertHubCatalog,
              );
            case ReloadLevel.none:
              break;
            case ReloadLevel.full:
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
                storage: homeStorage,
                managedProviderCubit: resolvedManagedProviderCubit,
                managedProviderUsageCubit: resolvedManagedProviderUsageCubit,
                home: defaultTargetResolver(),
                reinstallSshHome: reinstallSshHome,
                expertHubCatalog: expertHubCatalog,
              );
          }
          await homePlaneSwitch.persistSshHomePathCacheIfLive();
        };

    // Assigned once the shell graph is wired. bootstrapAppData only runs after
    // buildAppShell returns, so the reference below is safe at call time.
    late final HomeInvalidationService homeInvalidationService;

    /// True when a recovered target claims SSH but the published home plane is
    /// still the boot-time native fallback (`resolveCached` with no
    /// `lastHome`). Operating on that plane silently diverges from the home the
    /// user believes they are on.
    bool homeRecoveredOntoNativeFallback() =>
        defaultTargetResolver().kind == RuntimeKind.ssh &&
        homeStorage.context.mode != StorageBackendMode.ssh;

    // Seeded from the first bounded attempt so StartupGate can render the
    // connection page without re-probing. Local/wsl/termux homes are seeded
    // connected and never probe here (unchanged boot behavior).
    homeConnectionCubit = HomeConnectionCubit(
      connect: () async {
        // Read the LIVE home id, not the boot snapshot: a home switch must
        // retry the replacement target instead of the abandoned profile.
        final id = activeHomeProfileId;
        final result = id == null
            ? HomeConnectResult.connected(runtimeContextRegistry.home())
            : await homeAttempt.run(id);
        // Re-arm the background loop when an explicit retry (「继续重试」 /
        // 「重试」) ends unreachable: `userConnect` can succeed while the
        // bounded resolve still fails, and without this the cubit would sit in
        // `unreachable` with nothing retrying. The boot seed never runs this
        // (it uses markInitial), so boot keeps its single auto-start.
        if (!result.reachable && id != null) {
          sshProfileConnectionCoordinator.restartReconnect(id);
        }
        return result;
      },
      cancelRetry: () {
        final id = activeHomeProfileId;
        return id == null
            ? Future<void>.value()
            : sshProfileConnectionCoordinator.userDisconnect(id);
      },
      resumeRetry: () async {
        final id = activeHomeProfileId;
        if (id == null) return;
        // Single retry driver: hand off to the coordinator instead of opening
        // storage here (that ran in parallel with the coordinator's own attempt
        // and produced `Duplicate SSH worker request id`).
        sshProfileConnectionCoordinator.resumeRetries(id);
      },
      // Hot recovery: make sure recovery landed on the SSH home plane, run the
      // deferred remote boot once, then let the SSH liveness/team-generation
      // path resume now that the transport is back. Errors are logged (the
      // shell is already marked ready and must not crash on a late background
      // failure).
      onConnected: () {
        final cubit = homeConnectionCubit;
        final needsPlaneRebind = homeRecoveredOntoNativeFallback();
        if (needsPlaneRebind) {
          // Hold the gate while the boot-time native fallback plane is swapped
          // onto the live SSH home. The swap re-resolves the target with the
          // transport now up, so it normally succeeds and needs no restart.
          cubit?.markPlaneRebinding();
        }
        unawaited(() async {
          try {
            if (needsPlaneRebind) {
              final failure = await homePlaneSwitch.rebindHomeStoragePlane();
              if (failure != null) {
                cubit?.markUnreachable(failure);
                return;
              }
              cubit?.markPlaneReady();
            }
            await shellBoot.runRemoteBootAfterConnect();
            await shellBoot.reconnectHomeSshIfNeeded();
          } on Object catch (error, stackTrace) {
            appLogger.w(
              '[boot] remote boot after reconnect failed',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }());
      },
      profileId: isSshHome ? homeProfileId : null,
      host: isSshHome ? homeSshProfile?.host : null,
      port: isSshHome ? homeSshProfile?.port : null,
    )..markInitial(initialHome);

    // Single subscription to the supervisor drives the home connection page.
    // `markReconnected()` internally fires onConnected (plane rebind + deferred
    // remote boot), so hot recovery is preserved; an `up` that follows a
    // connecting/reconnecting/failed phase is the only thing that runs it.
    SshPhase? previousHomePhase;
    homeConnectivitySub = sshHomeConnectivity.changes.listen((state) {
      final cubit = homeConnectionCubit;
      if (cubit == null || cubit.isClosed) return;
      if (state.profileId != activeHomeProfileId) return;
      final previous = previousHomePhase;
      previousHomePhase = state.phase;
      if (state.planeRebinding) {
        cubit.markPlaneRebinding();
        return;
      }
      switch (state.phase) {
        case SshPhase.idle:
        case SshPhase.connecting:
          break;
        case SshPhase.up:
        case SshPhase.degraded:
          // Hot recovery (plane rebind + deferred remote boot) belongs to a
          // genuine retry-loop recovery only, i.e. `reconnecting` → `up`.
          // A plain `connecting` → `up` is a user/boot connect: treating it
          // as a recovery re-enters `onConnected`, which calls
          // `reconnectHomeSshIfNeeded` → `connect`, republishing `connecting`
          // and looping forever (and re-running `selectProfile`, which spams
          // stale remote-CLI discovery). Just project the status there.
          if (previous == SshPhase.reconnecting) {
            cubit.markReconnected();
          } else {
            cubit.markPlaneReady();
          }
        case SshPhase.reconnecting:
          cubit.markBackgroundAttempt(state.attempt);
        case SshPhase.unreachable:
        case SshPhase.suspended:
        case SshPhase.failed:
          cubit.markUnreachable(
            switch (state.failure) {
              SshFailureKind.hostIdentityChanged =>
                HomeErrorKind.hostIdentityChanged,
              SshFailureKind.authFailed => HomeErrorKind.authFailed,
              SshFailureKind.transportError => HomeErrorKind.transportError,
              SshFailureKind.unknown => HomeErrorKind.unknown,
              null => HomeErrorKind.transportError,
            },
          );
      }
    });

    // The supervisor owns the retry loop's persistence decision; activate the
    // current home so retries keep running until it is up (invariant 4).
    sshHomeConnectivity.activateHome(isSshHome ? homeProfileId : null);

    // A cold start that could not reach the SSH home never opened a transport,
    // so no close event will ever start the coordinator's loop. Start it once
    // here so recovery is automatic; the connection page shows progress and
    // can cancel/continue it. Reachable and non-SSH homes keep their previous
    // boot behavior.
    // isSshHome implies a non-null homeProfileId (set from
    // isSshHome ? homeProfileId : null in wireHomePlane).
    if (isSshHome && !initialHome.reachable) {
      sshProfileConnectionCoordinator.restartReconnect(homeProfileId!);
    }

    // Saving an edited SSH target used to only reload the profile catalog, so
    // fixing the host while the connection page was up left it retrying the
    // old address until a restart. Watch the CURRENT home profile's identity
    // and re-arm one bounded attempt when it changes.
    watchedHomeProfileConnectivityKey = () {
      final id = activeHomeProfileId;
      if (id == null) return null;
      final profile = sshProfileById(id);
      return profile == null ? null : sshProfileConnectivityKey(profile);
    }();
    homeProfileWatchSub = sshProfileCubit.stream.listen((_) {
      final id = activeHomeProfileId;
      if (id == null) return;
      final profile = sshProfileById(id);
      if (profile == null) return;
      final key = sshProfileConnectivityKey(profile);
      final previous = watchedHomeProfileConnectivityKey;
      watchedHomeProfileConnectivityKey = key;
      if (previous == key) return;
      final cubit = homeConnectionCubit;
      if (cubit == null || cubit.isClosed) return;
      if (cubit.state.status == HomeConnectionStatus.connected) return;
      appLogger.i('[home] current profile edited; retrying the connection');
      cubit.rebind(profileId: id, host: profile.host, port: profile.port);
      // A local re-target: clear the stale failure and re-dial the edited
      // profile without ever latching it as a non-retryable host-key change.
      sshHomeConnectivity.profileEdited(id);
      unawaited(cubit.retryNow());
    });

    // The app-data boot chain. Constructed here — after `homeConnectionCubit`
    // exists by value and before `editorCubit` — because `onConnected` may
    // reach it only once the shell graph is wired: `homePlaneSwitch` and
    // `homeInvalidationService` are forward references resolved at call time,
    // never copied.
    shellBoot = ShellBootController(
      homeStorage: homeStorage,
      sshProfileCubit: sshProfileCubit,
      sshWorkloadProfileCubit: sshWorkloadProfileCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
      teamCubit: teamCubit,
      connectionModeService: connectionModeService,
      defaultTargetResolver: defaultTargetResolver,
      sshProfileById: sshProfileById,
      bootstrapCubit: bootstrapCubit,
      homeIndexPrefetch: homeIndexPrefetch,
      notificationBootstrap: notificationBootstrap,
      shortcutCubit: shortcutCubit,
      localExpertStore: localExpertStore,
      expertHubCatalog: expertHubCatalog,
      automationScheduler: automationScheduler,
      sshConnectionCubit: sshConnectionCubit,
      homeConnectionCubit: homeConnectionCubit,
      deferHomePlaneLoads: deferHomePlaneLoads,
      boot: boot,
      appSettings: appSettings,
      appProviderCubit: appProviderCubit,
      cliPresetsCubit: cliPresetsCubit,
      aiFeatureSettingsCubit: aiFeatureSettingsCubit,
      discoverySettingsCubit: discoverySettingsCubit,
      homeWorkspaceUiCache: homeWorkspaceUiCache,
      llmConfigCubit: llmConfigCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      extensionCubit: extensionCubit,
      hydrateManagedProviderData: hydrateManagedProviderData,
      reinstallStorageContext: reinstallStorageContext,
      homePlaneSwitch: () => homePlaneSwitch,
      homeInvalidationService: () => homeInvalidationService,
    );

    editorCubit = EditorCubit(storage: homeStorage);
    // Fire-and-forget: warm the common tree-sitter grammars so the first file
    // open paints colored instead of cold. Never blocks app start.
    unawaited(EditorPlatform.bootstrap());
    // Single domain ↔ bar handshake: new session tabs surface in the bar and
    // bar removals tear down the domain via the bridge (which implements both
    // ports) instead of the deleted WorkbenchSessionSync reconcile.
    final workbenchChatBridge = WorkbenchChatBridge(
      workbench: workbenchCubit,
      chat: chatCubit,
      replacedPreviewTeardown: (workspaceId, replaced) {
        switch (replaced.kind) {
          case WorkbenchTabKind.file:
            editorCubit.closeFile(workspaceId, replaced.id, force: true);
          case WorkbenchTabKind.diff:
            editorCubit.closeDiff(workspaceId, replaced.id);
          case WorkbenchTabKind.shell:
            workspaceTerminalRunService.handleEntryClosed(replaced.id);
            workspaceTerminalRegistry
                .groupFor(workspaceId)
                .removeEntry(replaced.id);
          case WorkbenchTabKind.run:
            final workspace = chatCubit.state.workspaces
                .where((w) => w.workspaceId == workspaceId)
                .firstOrNull;
            if (workspace != null) {
              unawaited(
                workspaceRunRegistry
                    .cubitFor(
                      tabScopeId: workspaceId,
                      workspaceId: workspace.workspaceId,
                      folders: workspace.folders,
                    )
                    .dismissSession(replaced.id),
              );
            }
          case WorkbenchTabKind.session:
            break;
          case WorkbenchTabKind.htmlPreview:
            break;
          case WorkbenchTabKind.gitGraph:
            break;
          case WorkbenchTabKind.gitCompare:
            break;
        }
      },
    );
    workbenchCubit.port = workbenchChatBridge;
    chatCubit.workbenchPort = workbenchChatBridge;
    chatCubit.onSessionTabOpened = workbenchChatBridge.onSessionTabOpened;
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
      readFloatingPreviewTabs: () =>
          layoutCubit.state.preferences.floatingPreviewTabs,
    );
    workbenchEditorOpenerRef = workbenchEditorOpener;
    final resolvedShellLauncher = WorkbenchShellLauncher(
      floating: floatingWorkspaceCubit,
      workbench: workbenchCubit,
      chat: chatCubit,
      registry: workspaceTerminalRegistry,
      connector: workspaceShellConnector,
      layout: layoutCubit,
      sessionOps: workspaceTerminalSessionOps,
      homeTarget: defaultTargetResolver,
      sshDefaultWorkingDirectory: () =>
          sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
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
        descriptorFor: workbenchLayoutPersistence.descriptorFor,
        restoreTab: resolvedShellLauncher.restorePersistedShell,
      ),
      diff: DiffPreviewFloatingSurface(
        editor: editorCubit,
        floating: floatingWorkspaceCubit,
      ),
      html: HtmlPreviewFloatingSurface(floating: floatingWorkspaceCubit),
      gitGraph: GitGraphFloatingSurface(),
      gitCompare: GitCompareFloatingSurface(),
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
      workbenchCubit,
      WorkbenchStripNavigator(workbench: workbenchCubit, chat: chatCubit),
    );
    registerSplitCommands(commandBus, chatCubit, workbenchCubit);

    // P1: switching the home target persists the id, rebinds the home context,
    // and republishes it through HomeStorage. No explicit reload here (I1): the
    // HomeInvalidationService subscribes to HomeStorage.changes and drives the
    // single full reload — the swap itself is the trigger.
    Future<void> applyHomeEventTransport({bool restart = false}) async {
      final cubit = memberPresenceCubit;
      if (cubit != null) {
        if (connectionModeService.isSshMode) {
          cubit.setPresenceBridge(null);
        } else if (presenceSink != null) {
          cubit.setPresenceBridge(PresenceEventBridge(sink: presenceSink));
        } else {
          cubit.setPresenceBridge(null);
        }
      }
      final controller = eventTransportController;
      if (controller != null) {
        bindEventTransportHome?.call(homeStorage);
        await applyEventTransportForHome(
          controller: controller,
          connectionMode: connectionModeService,
          homeStorage: homeStorage,
          sshClientFactory: sshClientFactory,
          homeProfile: () {
            final id = defaultTargetResolver().sshProfileId;
            if (id == null || id.isEmpty) return null;
            return sshProfileById(id);
          },
          waitForRecovery: waitForSshProfileRecovery,
          restart: restart,
        );
      }
      if (connectionModeService.isLocalMode) {
        sessionAuthority!.clear();
        sessionActivitySource.start(sessionAuthority!);
      } else {
        sessionActivitySource.stop();
      }
      await applySessionProtocolForHome(
        controller: sessionProtocolController,
        connectionMode: connectionModeService,
        homeStorage: homeStorage,
        sshClientFactory: sshClientFactory,
        homeProfile: () {
          final id = defaultTargetResolver().sshProfileId;
          if (id == null || id.isEmpty) return null;
          return sshProfileById(id);
        },
        restart: restart,
      );
    }

    // Home-plane switching. Constructed here — after `applyHomeEventTransport`,
    // `sshHomeConnectivity`, and `homeConnectionCubit` exist by value — because
    // every later caller (`reinstallStorageContext`, the remote-index and
    // recovery closures) may reach it only once the shell graph is wired.
    homePlaneSwitch = HomePlaneSwitchController(
      runtimeContexts: runtimeContextRegistry,
      sshProfiles: sshProfileCubit,
      storage: homeStorage,
      managedProviders: managedProviderControlPlane,
      homeTargetStore: homeTargetStore,
      homeTargetFromId: homeTargetFromId,
      sshProfileById: sshProfileById,
      sshProfileConnectivityKey: sshProfileConnectivityKey,
      sshHomeConnectivity: sshHomeConnectivity,
      homeConnectionCubit: homeConnectionCubit,
      applyHomeEventTransport: applyHomeEventTransport,
      reinstallStorageContext: reinstallStorageContext,
      readHomeTarget: () => homeTarget,
      writeHomeTarget: (target) => homeTarget = target,
      readActiveHomeProfileId: () => activeHomeProfileId,
      writeActiveHomeProfileId: (id) => activeHomeProfileId = id,
      writeWatchedConnectivityKey: (key) =>
          watchedHomeProfileConnectivityKey = key,
      homeInvalidationService: () => homeInvalidationService,
    );

    // Bootstrap-owned invalidation: replaces the HomeSshProfileBinder widget
    // (a pending invalidation can no longer be dropped by `!mounted`). Starts
    // before bootstrapAppData so the profile baseline is primed from the
    // current catalog; profile diffs and home plane swaps map to reload
    // levels, and a missing home profile falls back to the local home.
    homeInvalidationService = HomeInvalidationService(
      profileStates: sshProfileCubit.stream,
      storageChanges: homeStorage.changes,
      homeTargetId: () => defaultTargetResolver().id,
      reload: (level) => reloadAllAppData(level: level),
      switchHome: homePlaneSwitch.switchHomeTarget,
      initialProfiles: sshProfileCubit.state.profiles,
      // Seed the generation token with swaps published before this
      // subscription existed so they are not mistaken for fresh planes.
      initialGeneration: homeStorage.generation,
    );
    homeInvalidationService.start();
    // M2: the invalidator is the service's policy helper (impact
    // classification); it stays exposed for RepositoryProvider consumers.
    final homeStorageInvalidator = homeInvalidationService.invalidator;

    homeTargetController = HomeTargetController(
      // Home selection reads the device-local home-binding palette (A source).
      registry: homeTargetRegistry,
      // Workspace machine pickers read the home-plane workload catalog
      // (B source, persisted in targets.json).
      workloadRegistry: workspaceTargetRegistry,
      current: defaultTargetResolver,
      switchTo: homePlaneSwitch.switchHomeTarget,
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
    // target's filesystem (real SSH connect for ssh targets) and lists the
    // home-plane workload targets (B source).
    final directoryPicker = WorkspaceDirectoryPicker(
      resolveContext: runtimeContextRegistry.forTarget,
      listTargets: () => workspaceTargetRegistry.listTargets(),
    );

    final sessionLifecycleHandler = eventDispatcher == null
        ? null
        : _SessionLifecycleRefreshHandler(
            chatCubit,
            () => connectionModeService.isSshMode,
          );
    if (eventDispatcher != null && sessionLifecycleHandler != null) {
      eventDispatcher.registerFamily<SessionLifecycleKind>(
        SessionLifecycleKind.sessionSpawned.runtimeType,
        sessionLifecycleHandler,
      );
    }
    final shell = AppShell(
      cliToolRegistry: cliToolRegistry,
      homeTargetController: homeTargetController,
      directoryPicker: directoryPicker,
      chatCubit: chatCubit,
      remoteCliReadiness: remoteCliReadiness,
      teamGenerationGraph: teamGenerationGraph,
      memberPresenceCubit: memberPresenceCubit,
      sessionRemoteActivityCubit: sessionRemoteActivityCubit,
      sessionProtocolController: sessionProtocolController,
      sessionActivitySource: sessionActivitySource,
      sessionAuthority: sessionAuthority!,
      sessionLifecycleHandler: sessionLifecycleHandler,
      agentAttentionCubit: agentAttentionCubit,
      seatLeaseCubit: seatLeaseCubit,
      agentStatusSeatLookup: agentStatusSeatLookup,
      agentRuntime: agentRuntime,
      mailboxCubit: mailboxCubit,
      boardCubit: boardCubit,
      aiHistoryCubit: aiHistoryCubit,
      notificationCubit: notificationCubit,
      progressActivityCubit: progressActivityCubit,
      repoCloneCubit: repoCloneCubit,
      installJobRegistry: installJobRegistry,
      editorCubit: editorCubit,
      workbenchCubit: workbenchCubit,
      workbenchLayoutPersistence: workbenchLayoutPersistence,
      workbenchEditorOpener: workbenchEditorOpener,
      workbenchShellLauncher: resolvedShellLauncher,
      floatingWorkspaceCubit: floatingWorkspaceCubit,
      floatingSurfaceRegistry: floatingSurfaceRegistry,
      floatingMaximizeInsets: floatingMaximizeInsets,
      sessionRepo: sessionRepo,
      workspaceProjectConfigRepository: workspaceProjectConfigRepository,
      sshProfileRepo: sshProfileRepo,
      combinedSshProfileRepo: combinedSshProfileRepo,
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
      workspaceSessionGroupsRegistry: workspaceSessionGroupsRegistry,
      workspaceToolsScopeRegistry: workspaceToolsScopeRegistry,
      workspaceRunRegistry: workspaceRunRegistry,
      sshClientFactory: sshClientFactory,
      sshProfileConnectionCoordinator: sshProfileConnectionCoordinator,
      connectionModeService: connectionModeService,
      identityRepository: identityRepository,
      teamCubit: teamCubit,
      sessionUsageCubit: sessionUsageCubit,
      cursorUsageApiClient: cursorUsageApiClient,
      configCubit: configCubit,
      connectCubit: connectCubit,
      embeddedSshServer: embeddedSshServer,
      systemSshdBackend: systemSshdBackend,
      connectDeviceStore: connectDeviceStore,
      appProviderCubit: appProviderCubit,
      managedProviderControlPlane: managedProviderControlPlane,
      managedProviderRepository: resolvedManagedProviderRepository,
      managedProviderUsageRepository: resolvedManagedProviderUsageRepository,
      managedProviderSecretStore: resolvedManagedProviderSecretStore,
      managedProviderUsageRegistry: resolvedManagedProviderUsageRegistry,
      managedProviderUsageCoordinator: resolvedManagedProviderUsageCoordinator,
      managedProviderCubit: resolvedManagedProviderCubit,
      managedProviderUsageCubit: resolvedManagedProviderUsageCubit,
      llmConfigCubit: llmConfigCubit,
      layoutCubit: layoutCubit,
      workspaceToolsCubit: workspaceToolsCubit,
      sessionPreferencesCubit: sessionPreferencesCubit,
      pluginCubit: pluginCubit,
      cliPresetsCubit: cliPresetsCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      hookCubit: hookCubit,
      hookRepository: hookRepository,
      hookImportParser: hookImportParser,
      hookImportService: hookImportService,
      teamHubCubit: teamHubCubit,
      expertHubCubit: expertHubCubit,
      expertHubCatalog: expertHubCatalog,
      expertCapabilityResolver: expertCapabilityResolver,
      extensionCubit: extensionCubit,
      appUpdateCubit: appUpdateCubit,
      remoteDownloadCatalogCubit: remoteDownloadCatalogCubit,
      sshProfileCubit: sshProfileCubit,
      sshWorkloadProfileCubit: sshWorkloadProfileCubit,
      vaultService: vaultService,
      homeVaultScope: scope,
      vaultCubit: vaultCubit,
      vaultCredentialCapture: vaultCredentialCapture,
      vaultUnlockGate: vaultUnlockGate,
      termuxCubit: termuxCubit,
      homeStorageInvalidator: homeStorageInvalidator,
      homeInvalidationService: homeInvalidationService,
      homeStorage: homeStorage,
      homeConnectionCubit: homeConnectionCubit,
      sshConnectionCubit: sshConnectionCubit,
      githubCredentialsStore: githubCredentialsStore,
      githubAccountCubit: githubAccountCubit,
      appSettings: appSettings,
      aiFeatureSettingsCubit: aiFeatureSettingsCubit,
      discoverySettingsCubit: discoverySettingsCubit,
      reinstallStorageContext: reinstallStorageContext,
      bootstrapAppData: shellBoot.bootstrapAppData,
      warmStartupCaches: warmStartupCaches,
      catalogRuntime: catalogRuntime,
      homeWorkspaceUiCache: homeWorkspaceUiCache,
      automationCubit: automationCubit,
      automationScheduler: automationScheduler,
      commandBus: commandBus,
      shortcutCubit: shortcutCubit,
      workspaceChromeCommands: workspaceChromeCommands,
      runCommandHost: runCommandHost,
      workspaceSearchHost: workspaceSearchHost,
      workspaceContentSearchHost: workspaceContentSearchHost,
      uiZoomBaseline: uiZoomBaseline,
    );
    shell._automationCatalogSub = automationCatalogSub;
    shell._homeProfileWatchSub = homeProfileWatchSub;
    shell._homeConnectivitySub = homeConnectivitySub;
    shell._vaultPlaneSyncSub = vaultPlaneSyncSub;
    shell._sessionRemoteRefreshSub = sessionRemoteRefreshSub;
    shell._contentInvalidationSub = contentInvalidationSub;
    shell._contentStreamSub = contentStreamSub;
    shell._attentionInbox = attentionInbox;
    shell._attentionSub = attentionSub;
    managedProviderControlPlaneLease.transferOwnership();
    await applyHomeEventTransport();
    return shell;
  } on Object {
    // The failed shell is discarded: stop its catalog mutation bus before a
    // bootstrap retry constructs a new one, so the app-lifetime dispatcher
    // no longer relays mutations into the dead shell's cubits. For the same
    // reason close the presence cubit: it holds a subscription to the
    // app-lifetime presence projection, which would otherwise keep waking a
    // cubit from a discarded shell. `memberPresenceCubit` is nullable because
    // construction may throw before it is assigned.
    await eventTransportController?.apply(EventTransportRole.none);
    await homeProfileWatchSub?.cancel();
    await homeConnectivitySub?.cancel();
    await attentionSub?.cancel();
    await attentionInbox?.dispose();
    await sessionAuthority?.dispose();
    await memberPresenceCubit?.close();
    await catalogRuntime?.bus.close();
    await homeConnectionCubit?.close();
    // The workload catalog subscribes to homeStorage.changes; close it so the
    // discarded shell leaves no listener on a plane that may be reused.
    await sshWorkloadProfileCubit.close();
    await managedProviderControlPlaneLease.closeIfOwned();
    rethrow;
  }
}

/// Mobile-side consumer of the desktop's `sessionLifecycle` family.
///
/// SFTP has no watcher, so a session created/closed on the desktop must refresh
/// this workspace's cached session list explicitly.
final class _SessionLifecycleRefreshHandler
    implements event_bus.EventHandler<SessionLifecycleEvent> {
  _SessionLifecycleRefreshHandler(this._chat, this._isSsh);

  final ChatCubit _chat;
  final bool Function() _isSsh;

  @override
  void handle(SessionLifecycleEvent event) {
    if (!_isSsh() || event.memberId != null) return;
    final workspaceId = event.workspaceId.trim();
    if (workspaceId.isEmpty) return;
    unawaited(_chat.refreshSessionsForWorkspace(workspaceId));
  }
}
