import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../cubits/app_bootstrap_cubit.dart';
import 'app_data_bootstrap.dart';
import 'bootstrap/managed_provider_control_plane.dart';
import 'bootstrap/provider_usage_http_client.dart';
import 'bootstrap/catalog_wiring.dart';
import 'bootstrap/install_wiring.dart';
import 'bootstrap/session_state_wiring.dart';
import 'bootstrap/session_usage_wiring.dart';
import 'team_generation_graph.dart';
import '../cubits/app_provider_cubit.dart';
import '../services/cli/antigravity/antigravity_bootstrap_entry.dart';
import '../services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import '../services/cli/gemini/gemini_bootstrap_entry.dart';
import '../services/cli/grok/grok_bootstrap_entry.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/remote_download_catalog_cubit.dart';
import '../cubits/automation_cubit.dart';
import '../cubits/agent_attention_cubit.dart';
import '../cubits/seat_lease_cubit.dart';
import '../cubits/session_remote_activity_cubit.dart';
import '../services/event/dispatcher.dart' as event_bus;
import '../services/event/session_lifecycle_event.dart';
import '../services/session_protocol/session_authority.dart';
import '../services/session_protocol/session_models.dart';
import '../services/session_sync/chat_session_activity_source.dart';
import '../services/session_sync/chat_session_control_port.dart';
import '../services/session_sync/session_content_invalidation_bus.dart';
import '../services/session_sync/session_content_stream_bus.dart';
import '../services/session_sync/session_protocol_controller.dart';
import 'session_protocol_home.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/session_groups_cubit.dart';
import '../cubits/session_usage_cubit.dart';
import '../services/cursor_usage/cursor_usage_api_client.dart';
import '../services/agent_runtime/agent_event_gateway.dart';
import '../services/agent_runtime/agent_runtime.dart';
import '../services/agent_runtime/runtime_event_journal.dart';
import '../services/agent_runtime/runtime_event_projection.dart';
import '../services/agent_runtime/seat_event_stream.dart';
import '../services/agent_runtime/seat_lease_projection.dart';
import '../services/editor/markdown_network_image_store.dart';
import '../services/event/agent_presence_projection.dart';
import '../services/event/agent_presence_sink.dart';
import '../services/event/event_transport_controller.dart';
import '../services/event/presence_event_bridge.dart';
import 'event_transport_home.dart';
import '../services/chat/conversation/prompt_delivery/prompt_delivery_coordinator.dart';
import '../services/chat/conversation/prompt_delivery/prompt_delivery_store.dart';
import '../services/agent_status/agent_status_seat_lookup.dart';
import '../services/agent_status/ask_user_answer_pending_store.dart';
import '../services/agent_status/ask_user_question_hook_gate.dart';
import '../services/agent_status/exit_plan_mode_hook_gate.dart';
import '../services/agent_status/general_permission_request_gate.dart';
import '../services/chat/conversation/approvals/ask_user_question_answer_service.dart';
import '../services/chat/conversation/approvals/exit_plan_mode_approval_service.dart';
import '../services/chat/team_generation/mcp/team_composer_mcp_handler.dart';
import '../models/app_provider_config.dart';
import '../models/app_session.dart';
import '../models/session_list_entry.dart';
import '../services/catalog/catalog_runtime.dart';
import '../services/catalog/catalog_mutation_bus.dart';
import '../services/catalog/catalog_production.dart';
import '../services/catalog/catalog_workspace_binder.dart';
import '../services/catalog/modules/automation_catalog_module.dart';
import '../services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../services/chat/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/chat/team_bus/remote/remote_member_bus_setup.dart';
import '../services/remote/local_credential_exporter.dart';
import '../services/remote/remote_cli_readiness.dart';
import '../services/editor_platform/editor_platform.dart';
import '../services/chat/launch/launch_factory.dart';
import '../services/launch_profile/team/launch_profile_selectors.dart';
import '../services/ssh/worker/ssh_worker_entry.dart';
import '../services/ssh/worker/ssh_worker_metrics.dart';
import '../cubits/board_cubit.dart';
import '../utils/session/workspace_tab_session_scope.dart';
import '../cubits/mailbox_cubit.dart';
import '../cubits/member_presence_cubit.dart';

import 'package:shared_ui/shared_ui.dart';

import '../cubits/notification_cubit.dart';
import '../pages/home_workspace/home_workspace_route.dart';
import '../services/notification/desktop_system_notifier.dart';
import '../cubits/progress_activity_cubit.dart';
import '../cubits/repo_clone_cubit.dart';
import '../services/app/app_update_service.dart';
import '../models/install_job/install_cancel_policy.dart';
import '../models/install_job/install_job_spec.dart';
import '../services/install/install_job_keys.dart';
import '../services/install/runners/hub_clone_install_job_runner.dart';
import '../services/remote_download/remote_download_http.dart';
import '../services/remote_download/remote_download_resolver.dart';
import '../services/remote_download/remote_downloader.dart';
import '../services/file_tree_import/workspace_import_service.dart';
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
import '../services/chat/conversation/history/session_history_context_builder.dart';
import '../cubits/ai_feature_settings_cubit.dart';
import '../cubits/discovery_settings_cubit.dart';
import '../cubits/config_cubit.dart';
import '../cubits/connect_cubit.dart';
import '../services/connect/endpoint_dial_planner.dart';
import '../services/connect/paired_device_store.dart';
import '../services/connect/paired_relay_tunnel_registry.dart';
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
import '../repositories/app_provider_repository.dart';
import '../repositories/launch_profile_repository.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../cubits/cli_presets_cubit.dart';
import '../models/cli_preset.dart';
import '../cubits/skill_cubit.dart';
import '../services/hook/hook_repository.dart';
import '../services/hook/import/hook_import_service.dart';
import '../services/mcp/mcp_dart_probe_handshake.dart';
import '../services/mcp/mcp_server_probe_service.dart';
import '../services/mcp/profile_mcp_linker_service.dart';
import '../cubits/ssh_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../cubits/vault_cubit.dart';
import '../cubits/termux_cubit.dart';
import '../cubits/github_account_cubit.dart';
import '../config/github_oauth_config.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/team_hub_cubit.dart';
import '../cubits/expert_hub_cubit.dart';
import '../models/runtime_target.dart';
import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../utils/ui/yield_ui_frame.dart';
import '../l10n/l10n_extensions.dart';
import '../services/acp/acp_chat_strings.dart';
import '../services/acp/acp_frame_logger.dart';
import '../pages/vault/vault_status_section.dart'
    show promptVaultUnlockFromRouter;
import '../repositories/app_settings_repository.dart';
import '../repositories/layout_repository.dart';
import '../repositories/session_preferences_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/automation_repository.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../repositories/workspace_project_config_repository.dart';
import '../repositories/managed_provider_repository.dart';
import '../repositories/managed_provider_usage_repository.dart';
import '../router/app_router.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/shared_state/device_id_store.dart';
import '../services/shared_state/shared_state_identity.dart';
import '../services/storage/app_paths.dart';
import '../services/storage/device_local_control_plane.dart';
import '../services/storage/remote_target_migration.dart';
import '../services/vault/credential_capture.dart';
import '../services/vault/encrypted_vault_backend.dart';
import '../services/vault/home_vault_service.dart';
import '../services/vault/vault_access.dart';
import '../services/vault/keychain_vault_backend.dart';
import '../services/vault/legacy_import.dart';
import '../services/vault/vault_split_migration.dart';
import '../models/vault_reference.dart';
import '../services/vault/provider_credential_link.dart';
import '../services/vault/vault_reference_indexer.dart';
import '../services/vault/vault_service.dart';
import '../services/vault/vault_unlock_gate.dart';
import '../services/io/local_filesystem.dart';
import '../services/connect/connect_agent.dart';
import '../services/connect/authorized_keys_file.dart';
import '../services/connect/connect_backend_host.dart';
import '../services/connect/connect_settings_store.dart';
import '../services/connect/connect_ssh_backend.dart';
import '../services/connect/embedded_ssh_server.dart' show EmbeddedSshServer;
import '../services/connect/sshd_presence.dart';
import '../services/connect/system_sshd_backend.dart';
import '../services/perf/live_perf_driver.dart';
import '../services/storage/workspace_layout.dart';
import '../services/automation/automation_bus_gateway.dart';
import '../services/automation/automation_command_executor.dart';
import '../services/automation/automation_command_runner.dart';
import '../services/automation/automation_dispatcher.dart';
import '../services/automation/automation_run_accounting.dart';
import '../services/automation/automation_schedule_calculator.dart';
import '../services/automation/automation_scheduler.dart';
import '../services/chat/launch/staging/session_runtime_plan_builder.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/team_config/team_clone_service.dart';
import '../services/team_hub/composite_team_hub_source.dart';
import '../services/team_hub/git_registry_team_hub_source.dart';
import '../services/team_hub/team_hub_favorites_store.dart';
import '../services/expert_hub/composite_expert_hub_source.dart';
import '../services/expert_hub/expert_capability_resolver.dart';
import '../services/expert_hub/expert_clone_service.dart';
import '../services/expert_hub/expert_hub_catalog.dart';
import '../services/expert_hub/local_expert_store.dart';
import '../services/expert_hub/expert_hub_favorites_store.dart';
import '../services/expert_hub/git_registry_expert_hub_source.dart';
import '../services/expert_hub/member_roster_service.dart';
import '../services/cli/acp_adapter_discovery.dart';
import '../services/cli/cli_executable_discovery.dart';
import '../services/cli/cli_local_discovery_bootstrap.dart';
import '../services/cli/cli_version_probe.dart';
import '../services/cli/toolchain_executable_discovery.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/layout_command_registrar.dart';
import '../services/commands/run_command_registrar.dart';
import '../services/commands/session_command_registrar.dart';
import '../services/commands/split_command_registrar.dart';
import '../services/commands/shortcuts_ui_commands.dart';
import '../services/commands/workspace_search_command_registrar.dart';
import '../services/commands/workspace_content_search_command_registrar.dart';
import '../services/floating_workspace/floating_maximize_insets.dart';
import '../services/floating_workspace/floating_surface_registry.dart';
import '../services/floating_workspace/floating_workspace_commands.dart';
import '../services/floating_workspace/floating_workspace_open_file.dart';
import '../services/floating_workspace/floating_workspace_persistence.dart';
import '../services/floating_workspace/surfaces/diff_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/file_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/git_compare_floating_surface.dart';
import '../services/floating_workspace/surfaces/git_graph_floating_surface.dart';
import '../services/floating_workspace/surfaces/html_preview_floating_surface.dart';
import '../services/floating_workspace/surfaces/run_floating_surface.dart';
import '../services/floating_workspace/surfaces/terminal_floating_surface.dart';
import '../pages/home_workspace/workspace_chrome_commands.dart';
import '../services/cli/registry/cli_bootstrap.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/cli/claude/claude_bootstrap_entry.dart';
import '../services/cli/codex/codex_bootstrap_entry.dart';
import '../services/cli/cursor/cursor_bootstrap_entry.dart';
import '../services/cli/registry/installer/binary_archive_installer.dart';
import '../services/cli/opencode/opencode_bootstrap_entry.dart';
import '../services/host/host_one_shot_runner_for_context.dart';
import '../services/host/host_process_starter_for_context.dart';
import '../services/host/host_shell_path_resolver.dart';
import '../services/cli/claude/provider/claude_provider_credentials_service.dart';
import '../services/cli/codex/provider/codex_provider_credentials_service.dart';
import '../services/cli/opencode/provider/opencode_models_service.dart';
import '../services/provider/api_model_catalog_service.dart';
import '../services/cli/cursor/provider/cursor_agent_models_service.dart';
import '../services/cli/cursor/provider/cursor_provider_credentials_service.dart';
import '../services/chat/runtime/pty/tab_member_pty_delivery.dart';
import '../services/provider/provider_credential_host_runner.dart';
import '../services/provider_usage/managed_provider_secret_store.dart';
import '../services/provider_usage/managed_provider_cli_row_janitor.dart';
import '../services/provider_usage/managed_provider_link_janitor.dart';
import '../services/provider_usage/managed_provider_usage_adapter.dart';
import '../services/provider_usage/managed_provider_usage_coordinator.dart';
import '../services/provider_usage/managed_provider_usage_registry.dart';
import '../services/provider_usage/adapters/claude_official_subscription_auth.dart';
import '../services/provider_usage/adapters/codex_official_subscription_auth.dart';
import '../services/provider_usage/adapters/cursor_official_subscription_auth.dart';
import '../services/provider_usage/cli_credential_source.dart';
import '../services/app/connection_mode_service.dart';
import '../services/cli/remote_cli_locator.dart';
import '../cubits/home_connection_cubit.dart';
import '../services/ssh/tcp_reachability_probe.dart';
import '../services/storage/home_connect_attempt.dart';
import '../services/storage/runtime_context_resolver.dart';
import '../services/storage/runtime_context_registry.dart';
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
import '../services/plugin/marketplace_shared_store.dart';
import '../services/plugin/plugin_repo_disk_cache_service.dart';
import '../services/skill/registry/skill_registry_factory.dart';
import '../services/storage/runtime_context.dart';
import '../services/github/github_credentials_store.dart';
import '../services/github/github_device_flow_auth.dart';
import '../services/hub_publish/http_github_api_client.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../services/ssh/ssh_connection_gate.dart';
import '../services/ssh/ssh_home_connectivity_supervisor.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/ssh/ssh_connection_events.dart';
import '../services/ssh/worker/ssh_profile_worker_manager.dart';
import '../services/ssh/worker/ssh_worker_auth_bridge.dart';
import '../widgets/ssh/ssh_host_key_prompt_dialog.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/ssh/mcp/session_ssh_mcp_executor.dart';
import '../services/ssh/mcp/session_ssh_mcp_http.dart';
import '../services/ssh/mcp/session_ssh_mcp_operations.dart';
import '../services/ssh/mcp/session_ssh_mcp_resolver.dart';
import '../services/ssh/ssh_transport_close.dart';
import '../services/ssh/ssh_connection_failure.dart';
import '../services/ssh/android_ssh_connect_home.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../services/file_tree/workspace_file_tree_store.dart';
import '../services/git/git_command_runner.dart';
import '../services/git/git_repo_store.dart';
import '../services/workspace/workspace_tools_scope_registry.dart';
import '../services/workspace/workspace_run_registry.dart';
import '../services/run/process_run_executor.dart';
import '../services/run/run_target_resolver.dart';
import '../services/run/workspace_run_platform_factory.dart';
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
  final documentsFuture =
      defaultWorkspaceDirectoryFuture ??
      DefaultWorkspaceDirectory.resolve(preferences: preferences);
  final cliToolRegistry = CliToolRegistry.builtIn();
  final cliExecutableDiscovery = CliExecutableDiscovery(
    registry: cliToolRegistry,
  );

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  // Apply the persisted ACP frame-log choice before any ACP session starts so
  // the log viewer toggle keeps working across restarts.
  AcpFrameLogger.mirrorEnabled = AcpFrameLogger.resolveEnabled(
    await appSettings.loadAcpFrameLogEnabled(),
  );
  final aiFeatureSettingsCubit = AiFeatureSettingsCubit(
    repository: appSettings,
  );
  final discoverySettingsCubit = DiscoverySettingsCubit(
    repository: appSettings,
  );
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    cliToolRegistry: cliToolRegistry,
  );
  if (!Platform.isAndroid) {
    boot('scheduling CLI tool discovery (background)');
    unawaited(() async {
      final counts = await runLocalCliDiscovery(
        cubit: sessionPreferencesCubit,
        locateCli: () => cliExecutableDiscovery.locateLocal(),
        locateAdapters: () =>
            AcpAdapterDiscovery(registry: cliToolRegistry).locateLocal(),
        locateToolchains: () => ToolchainExecutableDiscovery().locateLocal(),
        probeInstalled: CliVersionProbe().installed,
      );
      appLogger.i(
        '[boot] CLI/toolchain discovery complete '
        '(${counts.cliCount} CLI, ${counts.adapterCount} adapter, '
        '${counts.toolchainCount} toolchain, background)',
      );
    }());
  }
  boot('loading session preferences and workspace directory');
  final parallel = await Future.wait<Object?>([
    sessionPreferencesCubit.load(),
    documentsFuture,
  ]);
  // Native cwd must be TeamPilot's own subtree, never the OS documents root —
  // otherwise terminals/agents spill files directly into the user's Documents.
  final defaultWorkspaceDirectory =
      DefaultWorkspaceDirectory.teamPilotDirFromDocuments(
        parallel[1]! as String,
      );
  await Directory(defaultWorkspaceDirectory).create(recursive: true);
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
  // Business credentials live on the current home plane (the remote host);
  // SSH login credentials stay on the device vault so reconnection works while
  // the host is down. The scope is assigned once `homeStorage` exists below;
  // the resolver keeps routing correct across home-plane swaps.
  HomeVaultScope? homeVaultScope;
  final vaultService = VaultService(
    keychainBackend: KeychainVaultBackend(const FlutterSecureKeyValueStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: deviceLocalVaultRepository(nativeAppDataPath),
    ),
    masterKeyStore: const FlutterSecureKeyValueStore(),
    // Resolved lazily: before assignment, boot-time reads skip the home plane.
    homeVault: () => homeVaultScope?.service,
  );
  final vaultAccess = VaultAccess(vaultService);
  try {
    await vaultService.initialize();
    // Functional reads (SSH, providers, usage, GitHub) unlock silently with
    // the remembered master password; only an explicit reveal prompts.
    await vaultAccess.tryAutoUnlock();
  } on Object catch (error, stackTrace) {
    appLogger.w(
      '[vault] initialize failed: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
  // Shared vault-first capture path + unlock gate: every credential writer
  // (GitHub, app providers, SSH setup) goes through these so a locked vault
  // prompts exactly once per action instead of per call site.
  final vaultCredentialCapture = VaultCredentialCapture(vault: vaultService);
  final vaultUnlockGate = VaultUnlockGate(
    vault: vaultService,
    prompt: promptVaultUnlockFromRouter,
  );
  // Relay tunnels for paired (QR) SSH profiles: while a tunnel lives, every
  // dial for that profile rides the loopback port instead of the stored host.
  final pairedRelayTunnels = PairedRelayTunnelRegistry(
    credentialStore: sshCredentialStore,
    vault: vaultAccess,
  );
  final sshKnownHostRepo = SharedPrefsSshKnownHostRepository(preferences);
  final sshConnectionEvents = SshConnectionEvents();
  // Shared home-plane catalog rows cannot carry a vault reference; the device
  // vault entry is owned by the profile id instead. Resolve it at connect time
  // so a row created on the plane still finds the secret this device saved.
  // Without this, "test connection" (which resolves the owner entry in the
  // editor) succeeds while the durable connect gets an empty password.
  Future<String?> sshVaultEntryIdFor(String profileId) async {
    try {
      await vaultAccess.tryAutoUnlock();
      final entry = await vaultCredentialCapture.findOwner(
        vaultOwnerKindSshProfile,
        profileId,
      );
      final entryId = (entry?.id ?? '').trim();
      return entryId.isEmpty ? null : entryId;
    } on Object {
      return null;
    }
  }

  final sshWorkerAuthBridge = SshWorkerAuthBridge(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    onHostKeyPrompt: showSshHostKeyPrompt,
    dialTargetResolver: (profile) => pairedRelayTunnels.targetFor(profile.id),
    vault: (entryId, field) => vaultAccess.functionalField(entryId, field),
    vaultEntryIdFor: sshVaultEntryIdFor,
  );
  const sshWorkerCaptureMode = String.fromEnvironment(
    'SSH_WORKER_CAPTURE_MODE',
    defaultValue: 'worker',
  );
  final sshWorkerMetrics =
      bool.fromEnvironment('SSH_WORKER_METRICS', defaultValue: false)
      ? SshWorkerMetrics(enabled: true, logDiagnostic: appLogger.i)
      : null;
  final sshWorkerLauncher = sshWorkerCaptureMode == 'direct'
      ? DirectSshWorkerLauncher()
      : const IsolateSshWorkerLauncher();
  final sshProfileWorkerManager = SshProfileWorkerManager(
    launcher: sshWorkerLauncher,
    authChallengeHandlerFor: sshWorkerAuthBridge.handlerFor,
    metrics: sshWorkerMetrics,
  );
  // One app-level gate, owned by the connectivity supervisor. The pure pool
  // only receives its read-only `beforeIo` guard; every state write goes
  // through the supervisor (or its owned coordinator).
  final sshConnectivityGate = SshConnectionGate();
  final sshClientFactory = SshClientFactory(
    credentialStore: sshCredentialStore,
    knownHostRepository: sshKnownHostRepo,
    events: sshConnectionEvents,
    onHostKeyPrompt: showSshHostKeyPrompt,
    dialTargetResolver: (profile) => pairedRelayTunnels.targetFor(profile.id),
    vaultCredentials: (entryId, field) =>
        vaultAccess.functionalField(entryId, field),
    vaultEntryIdFor: sshVaultEntryIdFor,
    workerAuthBridge: sshWorkerAuthBridge,
    workerManager: sshProfileWorkerManager,
    ioGuard: sshConnectivityGate.beforeIo,
  );

  /// Waits for the single connection driver to bring [SshProfileDownException]
  /// profiles back up. Consumers use this instead of polling with their own
  /// backoff.
  Future<bool> waitForSshProfileRecovery(Object error) async {
    if (error is! SshProfileDownException) return false;
    await sshConnectivityGate.waitUntilUp(error.profileId);
    return true;
  }

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
  // Declared before the VaultCubit closure that captures it: the closure only
  // runs on a later unlock/encrypt, after the importer is assigned below.
  late final VaultLegacyImportService legacyImporter;
  late final VaultCubit vaultCubit;
  late final HomeTargetController homeTargetController;
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

  final githubCredentialsStore = GithubCredentialsStore(
    kv: const FlutterSecureKeyValueStore(),
    vault: vaultService,
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
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

  // P1: targets.json is a pure target catalog (no default/migrate); the home
  // target authority is the device-local homeTargetStore read above. The
  // registry is used by the picker UI to list selectable targets.
  final targetsRepo = deviceLocalTargetsRepository(nativeAppDataPath);
  final termuxConfigStore = deviceLocalTermuxConfigStore(nativeAppDataPath);
  final remoteDownloadSettingsStore = deviceLocalRemoteDownloadSettingsStore(
    nativeAppDataPath,
  );
  final remoteDownloadCatalogCubit = RemoteDownloadCatalogCubit(
    store: remoteDownloadSettingsStore,
  );
  unawaited(remoteDownloadCatalogCubit.load());
  final appUpdateResolver = RemoteDownloadResolver.withProvider(
    () => remoteDownloadCatalogCubit.state.catalog,
  );
  final appUpdateHttpClient = http.Client();
  final remoteDownloader = RemoteDownloader(
    client: appUpdateHttpClient,
    resolver: appUpdateResolver,
  );
  final appUpdateService = AppUpdateService(
    httpClient: appUpdateHttpClient,
    resolver: appUpdateResolver,
    downloadHttp: RemoteDownloadHttp(
      client: appUpdateHttpClient,
      resolver: appUpdateResolver,
    ),
    downloader: remoteDownloader,
  );
  final workspaceImportService = WorkspaceImportService();
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

  /// Identity fields that decide how an SSH home is reached. Deliberately
  /// excludes `updatedAt` and the persisted path cache: a successful connect
  /// writes those back and must not look like a user edit.
  String sshProfileConnectivityKey(SshProfile profile) =>
      '${profile.host}|${profile.port}|${profile.username}|'
      '${profile.authType.name}|${profile.vaultEntryId ?? ''}';

  final remoteCliReadiness = RemoteCliReadinessService(
    registry: cliToolRegistry,
    sshClientFactory: sshClientFactory,
    profileById: sshProfileById,
    cliPathOverride: targetsRepo.cliPathOverride,
    setCliPathOverride: targetsRepo.setCliPathOverride,
    acpAdapterPathOverride: targetsRepo.acpAdapterPathOverride,
    setAcpAdapterPathOverride: targetsRepo.setAcpAdapterPathOverride,
  );
  final runtimeTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
    hasTermuxConfig: () => termuxConfigCache != null,
  );

  // P2: de-singleton. One resolver + a per-target context registry. The home
  // context (control plane) is materialized once and published on HomeStorage;
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
          homeTargetFromId(targetId).sshProfileId ?? sshProfileIdOfId(targetId);
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
  // SSH homes get one bounded attempt (TCP probe + time-boxed resolve) so an
  // unreachable/slow host cannot hold the splash indefinitely. Every other
  // home kind keeps the existing unbounded resolve.
  final homeProfileId = homeTarget.sshProfileId;
  final isSshHome =
      homeTarget.kind == RuntimeKind.ssh &&
      homeProfileId != null &&
      homeProfileId.isNotEmpty;
  // The live home identity. [homeProfileId] is the boot-time snapshot; every
  // connection hook below reads this mutable value so a home switch inside the
  // running shell retargets the cubit/coordinator instead of retrying the
  // abandoned profile until the next restart.
  var activeHomeProfileId = isSshHome ? homeProfileId : null;
  final homeSshProfile = isSshHome ? sshProfileById(homeProfileId) : null;
  // One bounded attempt factory reused by boot and every later retry: it reads
  // the registry's CURRENT home target, so it follows [setHomeTarget] too.
  final homeAttempt = HomeConnectAttempt(
    probe: const SocketTcpReachabilityProbe(),
    resolve: () async {
      await runtimeContextRegistry.ensureHome();
      return runtimeContextRegistry.home();
    },
    cacheContext: runtimeContextRegistry.ensureHomeCached,
    profileById: sshProfileById,
  );
  HomeConnectResult initialHome;
  if (isSshHome) {
    initialHome = await homeAttempt.run(homeProfileId);
  } else {
    await runtimeContextRegistry.ensureHome();
    initialHome = HomeConnectResult.connected(runtimeContextRegistry.home());
  }
  boot('home runtime context ensured +${ensureHomeSw.elapsedMilliseconds}ms');
  // A failed attempt already carries the cached-path context, so the shell can
  // be built without waiting for any network round-trip.
  final homeCtx =
      initialHome.context ?? await runtimeContextRegistry.ensureHomeCached();
  // True when an SSH home failed its first bounded attempt. Home-plane reads
  // are then deferred to the post-connect chain: with no warm client every one
  // of them starts a fresh storage open bounded by SshStorageIo.ioTimeout, and
  // awaiting them here would reintroduce the splash stall this task removes.
  final deferHomePlaneLoads = isSshHome && !initialHome.reachable;
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
  // Versioned, drain-safe home facade: home swaps publish through it and the
  // outgoing context is retired (registry evict → drain-safe SSH disconnect)
  // only after the new context is live. Every control-plane consumer receives
  // it via constructor injection (or the RepositoryProvider in main.dart).
  final homeStorage = HomeStorage(
    homeCtx,
    retire: (old) => runtimeContextRegistry.disposeContext(old),
  );
  // Shared-state stamps are device-scoped, so the id lives in the device
  // plane and never travels through the home plane.
  final deviceId = await DeviceIdStore(
    fs: deviceLocalHomeStorage(nativeAppDataPath).fs,
    path: AppPaths.pathContextForDataRoot(nativeAppDataPath)
        .join(nativeAppDataPath, 'shared-state', 'device-id'),
  ).loadOrCreate();
  SharedStateIdentity.configure(deviceId: deviceId);
  homeWorkspaceUiCache = HomeWorkspaceUiCache(storage: homeStorage);
  // Disk cache for markdown network images lives under the home
  // <teampilotRoot>/cache; bind it before any editor surface loads a badge.
  MarkdownNetworkImageStore.storageHome = homeStorage;
  boot(
    'home context installed '
    '(${homeStorage.context.mode}, home=${homeTarget.id}, '
    'root=${homeStorage.appDataRoot})',
  );

  // Home-plane business vault. SSH login credentials remain in the device
  // vault; everything else is written to / read from <home>/vault/.
  final scope = HomeVaultScope(
    storage: homeStorage,
    keyStore: const FlutterSecureKeyValueStore(),
  );
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

  vaultCubit = VaultCubit(
    service: vaultService,
    sshProfiles: sshProfileRepo,
    appProviders: AppProviderRepository(storage: homeStorage),
    onUnlocked: () async {
      // Import first: GitHub hydration reads the store, and a token that only
      // lives in the vault must be captured before the pointer is consulted.
      // Hydration is NOT awaited: it may hit api.github.com, and unlock/save
      // must stay responsive while it runs.
      await legacyImporter.runOnce();
      // The vault page may already be mounted (the user just unlocked it):
      // re-read rows only; changing status during the unlock transition can
      // re-enter the page rebuild while a dialog is closing.
      await vaultCubit.reloadEntries();
      unawaited(
        githubAccountCubit.hydrate().catchError((
          Object error,
          StackTrace stack,
        ) {
          appLogger.w(
            '[vault] post-unlock GitHub hydrate failed: ${error.runtimeType}',
            stackTrace: stack,
          );
        }),
      );
    },
  );

  // Managed Providers belong to the home/control plane. Construct this graph
  // once after the home context is installed; workspace tabs only consume the Cubits
  // exposed by AppShell and never create provider-specific state.
  final resolvedManagedProviderSecretStore =
      managedProviderSecretStore ??
      ManagedProviderSecretStore(const FlutterSecureKeyValueStore());
  final resolvedManagedProviderUsageRepository =
      managedProviderUsageRepository ??
      ManagedProviderUsageRepository(storage: homeStorage);
  final resolvedManagedProviderRepository =
      managedProviderRepository ??
      ManagedProviderRepository(
        storage: homeStorage,
        onProvidersDeleted: resolvedManagedProviderUsageRepository.deleteMany,
      );

  vaultCubit.attachReferenceIndexer(
    VaultReferenceIndexer([
      (entryId) async {
        final profiles = await sshProfileRepo.loadAll();
        return [
          for (final profile in profiles)
            if (profile.vaultEntryId == entryId)
              VaultReference(
                kind: VaultReferenceKind.sshProfile,
                id: profile.id,
                label: profile.name,
              ),
        ];
      },
      (entryId) async {
        final perCli = await Future.wait([
          for (final cli in CliTool.values)
            AppProviderRepository(storage: homeStorage)
                .loadProviders(cli, reconcileCredentials: false),
        ]);
        return [
          for (final providers in perCli)
            for (final provider in providers)
              if (vaultEntryIdFromCredentialLink(provider.credentialLink) ==
                  entryId)
                VaultReference(
                  kind: VaultReferenceKind.appProvider,
                  id: provider.id,
                  label: provider.name,
                ),
        ];
      },
      (entryId) async {
        final entries = await resolvedManagedProviderRepository.load();
        return [
          for (final entry in entries)
            if ((entry.vaultEntryId ?? '').trim() == entryId)
              VaultReference(
                kind: VaultReferenceKind.managedProvider,
                id: entry.id,
                label: entry.name,
              ),
        ];
      },
      (entryId) async {
        final stored = await githubCredentialsStore.storedVaultEntryId();
        if ((stored ?? '').trim() != entryId) return const [];
        return const [
          VaultReference(
            kind: VaultReferenceKind.github,
            id: 'github',
            label: 'GitHub',
          ),
        ];
      },
    ]),
  );
  final ownsManagedProviderHttpClient =
      managedProviderUsageHttpClient == null &&
      managedProviderUsageCoordinator == null;
  final ProviderUsageHttpClient? resolvedManagedProviderHttpClient =
      managedProviderUsageHttpClient ??
      (managedProviderUsageCoordinator == null
          ? DefaultProviderUsageHttpClient()
          : null);
  final resolvedManagedProviderUsageRegistry =
      managedProviderUsageRegistry ??
      buildDefaultManagedProviderUsageRegistry(
        fs: homeStorage.fs,
        basePath: homeStorage.paths.basePath,
        cliCredentials:
            managedProviderCliCredentials ??
            CliCredentialSourceResolver(
              readers: {
                'claude': ClaudeOfficialSubscriptionAuthReader(
                  fs: homeStorage.fs,
                  basePath: homeStorage.paths.basePath,
                ),
                'codex': CodexOfficialSubscriptionAuthReader(
                  fs: homeStorage.fs,
                  basePath: homeStorage.paths.basePath,
                ),
                'cursor': CursorOfficialSubscriptionAuthReader(
                  fs: homeStorage.fs,
                  basePath: homeStorage.paths.basePath,
                ),
              },
            ),
      );
  final resolvedManagedProviderUsageCoordinator =
      managedProviderUsageCoordinator ??
      ManagedProviderUsageCoordinator(
        providerRepository: resolvedManagedProviderRepository,
        usageRepository: resolvedManagedProviderUsageRepository,
        registry: resolvedManagedProviderUsageRegistry,
        credentials: ManagedProviderCredentialResolver(
          resolvedManagedProviderSecretStore,
          // Live `provider:<cli>:<id>` credential sources read the app
          // provider catalog; a dedicated repository instance avoids the
          // (later-constructed) cubit's load-order dependency. Same disk,
          // same cache-free reads.
          appProviders: AppProviderRepository(storage: homeStorage),
          vault: vaultAccess,
        ),
        http: resolvedManagedProviderHttpClient!,
      );
  final resolvedManagedProviderUsageCubit =
      managedProviderUsageCubit ??
      ManagedProviderUsageCubit(
        coordinator: resolvedManagedProviderUsageCoordinator,
      );
  // Credential-login URL opener shared by the app provider cubit and the
  // per-CLI credential host runner; declared before the managed-provider
  // control plane so AppProviderCubit can be constructed above it.
  Future<void> openCredentialLoginUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Resolves a provider config's `credentialLink` to the linked managed
  // entry's stored secret (spec: reverse direction). Secret-free failure: a
  // missing entry or secret resolves to null, never throws.
  Future<String?> appProviderLinkedCredentialLookup(String link) async {
    final vaultEntryId = vaultEntryIdFromCredentialLink(link);
    if (vaultEntryId != null) {
      try {
        return await vaultAccess.functionalField(vaultEntryId, 'apiKey');
      } on Object {
        return null;
      }
    }
    final entries = await resolvedManagedProviderRepository.load();
    final entry = entries.where((e) => e.id == link.trim()).firstOrNull;
    if (entry == null) return null;
    final entryVaultEntryId = entry.vaultEntryId?.trim() ?? '';
    if (entryVaultEntryId.isNotEmpty) {
      final field = entry.endpointConfig.credentialField ?? 'apiKey';
      try {
        return await vaultAccess.functionalField(entryVaultEntryId, field);
      } on Object {
        return null;
      }
    }
    final ref = entry.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;
    final scope = await resolvedManagedProviderSecretStore.read(ref);
    final field = entry.endpointConfig.credentialField ?? 'apiKey';
    final value = scope.valueFor(field);
    return (value == null || value.isEmpty) ? null : value;
  }

  // CLI launch resolvers create their own AppProviderRepository instances
  // (OpenCode, Claude, cross-machine bridges); give them the vault-aware
  // lookup so `vault:` links resolve outside the provider cubit too.
  AppProviderRepository.installDefaultLinkedCredentialLookup(
    appProviderLinkedCredentialLookup,
  );

  // Constructed before the managed-provider control plane so
  // ManagedProviderCubit can ensure dedicated per-entry CLI provider rows;
  // only needs sessionPreferencesCubit and openCredentialLoginUrl.
  appProviderCubit = AppProviderCubit(
    storage: homeStorage,
    repository: AppProviderRepository(
      storage: homeStorage,
      linkedCredentialLookup: appProviderLinkedCredentialLookup,
    ),
    flashskyaiExecutablePath: sessionPreferencesCubit.resolveExecutable,
    openCredentialLoginUrl: openCredentialLoginUrl,
    managedProviderRepository: resolvedManagedProviderRepository,
    vaultCapture: vaultCredentialCapture,
    ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
  );

  // Reclaims dedicated CLI provider rows and their isolated HOME
  // directories: from the managed-provider delete hook and the one-shot
  // startup sweep below.
  final managedProviderCliRowJanitor = ManagedProviderCliRowJanitor(
    fs: homeStorage.fs,
    basePath: homeStorage.paths.basePath,
    appProviderCubit: appProviderCubit,
  );

  final resolvedManagedProviderCubit =
      managedProviderCubit ??
      ManagedProviderCubit(
        repository: resolvedManagedProviderRepository,
        appProviderCubit: appProviderCubit,
        rowJanitor: managedProviderCliRowJanitor,
        ensureVaultUnlocked: vaultUnlockGate.ensureUnlocked,
        onProviderDeletedState:
            resolvedManagedProviderUsageCubit.removeProvider,
        onProviderDeletedCredentialCleanup: (provider) async {
          final vaultEntryId = provider.vaultEntryId?.trim() ?? '';
          if (vaultEntryId.isNotEmpty) {
            try {
              await vaultService.delete(vaultEntryId);
            } on Object catch (error, stackTrace) {
              appLogger.w(
                'Vault entry cleanup failed for managed provider ${provider.id}',
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
          final ref = provider.credentialRef?.trim();
          if (ref != null && ref.isNotEmpty) {
            await resolvedManagedProviderSecretStore.delete(ref);
          }
          // Clear provider-config rows that referenced this entry's secret.
          await ManagedProviderLinkJanitor(appProviderCubit: appProviderCubit)
              .clearLinksFor(provider.id);
        },
      );
  final managedProviderControlPlane = ManagedProviderControlPlane(
    providerRepository: resolvedManagedProviderRepository,
    usageRepository: resolvedManagedProviderUsageRepository,
    secretStore: resolvedManagedProviderSecretStore,
    usageRegistry: resolvedManagedProviderUsageRegistry,
    usageCoordinator: resolvedManagedProviderUsageCoordinator,
    providerCubit: resolvedManagedProviderCubit,
    usageCubit: resolvedManagedProviderUsageCubit,
    ownsProviderCubit: managedProviderCubit == null,
    ownsUsageCubit: managedProviderUsageCubit == null,
    ownsUsageCoordinator: managedProviderUsageCoordinator == null,
    closeOwnedHttpClient: ownsManagedProviderHttpClient
        ? () =>
              (resolvedManagedProviderHttpClient!
                      as DefaultProviderUsageHttpClient)
                  .close()
        : null,
  );
  final managedProviderControlPlaneLease = ManagedProviderControlPlaneLease(
    managedProviderControlPlane,
  );

  // Vault-first migration of every legacy secret. Constructed after the
  // managed-provider graph and the GitHub store so the closure above always
  // sees a fully-assigned importer. `runOnce` is a no-op while the vault is
  // locked and after a clean pass, so it is safe at every boot.
  legacyImporter = VaultLegacyImportService(
    vault: vaultService,
    capture: vaultCredentialCapture,
    importKey: nativeAppDataPath,
    sshProfiles: sshProfileRepo,
    sshCredentials: sshCredentialStore,
    appProviders: AppProviderRepository(storage: homeStorage),
    managedProviders: resolvedManagedProviderRepository,
    managedSecrets: resolvedManagedProviderSecretStore,
    github: githubCredentialsStore,
  );
  // One background sequence, not two: hydration reads the GitHub store that
  // the import writes, so running them independently can duplicate the vault
  // entry. Failure-tolerant and off the boot critical path.
  unawaited(() async {
    try {
      await githubAccountCubit.hydrate();
      await legacyImporter.runOnce();
      // Repair pass: imports only rows that still carry a plaintext secret and
      // no vault reference, so a provider key added after the one-shot marker
      // (or captured while the plane was down) still reaches the vault.
      await legacyImporter.runRepair();
      // Boot import runs in the background; refresh rows on a possibly-open page.
      await vaultCubit.reloadEntries();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[vault] boot hydrate/import failed: ${error.runtimeType}',
        stackTrace: stackTrace,
      );
    }
  }());

  // A home switch changes which plane holds the business vault. Both passes are
  // idempotent: copy this device's business entries onto the new plane, then
  // re-run the owner imports so credentials captured while the plane was down
  // (or written before the split) reach it. SSH login credentials stay on the
  // device — the migration skips them.
  final vaultPlaneSyncSub = homeStorage.changes.listen((change) {
    if (!change.newContext.filesystem.isRemote) return;
    final scope = homeVaultScope;
    if (scope == null) return;
    unawaited(() async {
      try {
        await scope.prepare();
        await migrateBusinessVaultEntries(
          device: vaultService,
          home: scope.service,
        );
        await legacyImporter.runRepair();
        await vaultCubit.reloadEntries();
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[vault] home-plane vault sync failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  });

  // One-shot startup sweep: reclaim orphaned `-mp-` rows and the legacy
  // shared rows. Fire-and-forget and failure-tolerant — the control plane
  // is fully usable without it.
  unawaited(() async {
    try {
      final entries = await resolvedManagedProviderRepository.load();
      await managedProviderCliRowJanitor.sweep(entries: entries);
    } on Object catch (error, stackTrace) {
      if (isSshProfileDown(error)) {
        appLogger.d(
          '[managed-provider] cli row sweep waiting for home transport',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }
      appLogger.w(
        '[managed-provider] cli row sweep failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }());

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

  try {
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
    // through homeStorage.
    Future<void> setHomeTarget(String id) async {
      await managedProviderControlPlane.invalidateForStorageContextChange();
      await homeTargetStore.save(id);
      final previousHomeId = defaultTargetResolver().id;
      final nextHomeTarget = homeTargetFromId(id);
      // Drop any cached wrapper for the destination target so rebindHome
      // materializes a fresh context (unchanged from the pre-swap sequence).
      if (id != previousHomeId) await runtimeContextRegistry.dispose(id);
      await runtimeContextRegistry.rebindHome(nextHomeTarget);
      homeTarget = nextHomeTarget;
      final nextProfileId = nextHomeTarget.sshProfileId;
      activeHomeProfileId =
          nextHomeTarget.kind == RuntimeKind.ssh &&
              nextProfileId != null &&
              nextProfileId.isNotEmpty
          ? nextProfileId
          : null;
      // Publish the new home plane synchronously, then retire the outgoing
      // context — its registry entry is evicted and the SSH transport closed
      // only after in-flight ops drain (Task 5 deferred close).
      await homeStorage.swap(runtimeContextRegistry.home());
      await persistSshHomePathCacheIfLive();
    }

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
      await persistSshHomePathCacheIfLive();
    };

    void onCredentialLoginHint(CredentialLoginProgress progress) {
      appProviderCubit.reportCredentialLoginProgress(progress);
    }

    final credentialHostRunner = ProviderCredentialHostRunner(
      oneShot: () => hostOneShotRunnerForContext(homeStorage.context),
      streaming: () => hostProcessStarterForContext(homeStorage.context),
      openUrl: openCredentialLoginUrl,
      onLoginHint: onCredentialLoginHint,
    );

    final claudeCredentialsService = ClaudeProviderCredentialsService(
      storage: homeStorage,
      fs: homeStorage.fs,
      basePath: homeStorage.paths.basePath,
      resolveClaudeExecutable: () =>
          sessionPreferencesCubit.resolveExecutable(CliTool.claude),
      resolveHomeDirectory: () => homeStorage.home,
      hostRunner: credentialHostRunner,
    );
    final cursorCredentialsService = CursorProviderCredentialsService(
      storage: homeStorage,
      fs: homeStorage.fs,
      basePath: homeStorage.paths.basePath,
      resolveCursorExecutable: () =>
          sessionPreferencesCubit.resolveExecutable(CliTool.cursor),
      hostRunner: credentialHostRunner,
    );
    final codexCredentialsService = CodexProviderCredentialsService(
      storage: homeStorage,
      fs: homeStorage.fs,
      basePath: homeStorage.paths.basePath,
      resolveCodexExecutable: () =>
          sessionPreferencesCubit.resolveExecutable(CliTool.codex),
      hostRunner: credentialHostRunner,
    );
    final opencodeModelsService = OpencodeModelsService(storage: homeStorage);

    // Cached Gemini API key for the ACP agent env (refreshed from provider
    // rows; the ACP credential source is a sync closure).
    String? cachedGeminiApiKey;
    // Cached xAI API key for the ACP/headless env; provider-bound keys are
    // injected per seat, so this is only the app-wide fallback.
    String? cachedGrokApiKey;
    // Cached Claude provider row matching the CLI's selected official-vs-key
    // id for the sync ACP auth source; refreshed alongside the Gemini key.
    AppProviderConfig? cachedClaudeProvider;
    // Cached Codex provider row matching the CLI's selected official-vs-key
    // id for the sync ACP auth source; refreshed alongside Claude / Gemini.
    AppProviderConfig? cachedCodexProvider;

    cliToolRegistry.configure(
      CliBootstrap({
        CliTool.claude: ClaudeBootstrapEntry(
          credentialsService: claudeCredentialsService,
          acpAuthSource: () => claudeAcpAuthForProvider(
            cachedClaudeProvider,
            claudeCredentialsService,
          ),
          modelsService: ApiModelCatalogService(
            storage: homeStorage,
            protocol: ApiModelCatalogProtocol.anthropic,
            cacheDirectory: 'claude_models',
          ),
        ),
        CliTool.cursor: CursorBootstrapEntry(
          credentialsService: cursorCredentialsService,
          agentModelsService: CursorAgentModelsService(storage: homeStorage),
        ),
        CliTool.codex: CodexBootstrapEntry(
          credentialsService: codexCredentialsService,
          acpAuthSource: () => codexAcpAuthForProvider(cachedCodexProvider),
          codexPathSource: () =>
              sessionPreferencesCubit.resolveExecutable(CliTool.codex),
          modelsService: ApiModelCatalogService(
            storage: homeStorage,
            protocol: ApiModelCatalogProtocol.openAi,
            cacheDirectory: 'codex_models',
          ),
        ),
        CliTool.opencode: OpencodeBootstrapEntry(
          modelsService: opencodeModelsService,
        ),
        CliTool.gemini: GeminiBootstrapEntry(
          credentialSource: () => cachedGeminiApiKey,
        ),
        CliTool.grok: GrokBootstrapEntry(
          credentialSource: () => cachedGrokApiKey,
        ),
        CliTool.antigravity: AntigravityBootstrapEntry(
          storage: homeStorage,
          acpInstaller: AntigravityAcpAdapterInstaller(
            storage: homeStorage,
            binary: BinaryArchiveInstaller(
              fs: homeStorage.fs,
              fetch: (uri, {expectedSha256, onProgress, isCancelled}) =>
                  remoteDownloader.fetch(
                    uri,
                    destFileName: 'antigravity-acp.zip',
                    expectedSha256: expectedSha256,
                    onProgress: onProgress,
                    isCancelled: isCancelled,
                  ),
            ),
          ),
        ),
      }, storage: homeStorage),
    );
    // Keep the cached Gemini API key current: the credential source must be
    // sync (AcpCredentialSource), but provider rows load asynchronously.
    var geminiCredentialRefreshInFlight = false;
    void refreshGeminiCredential() {
      if (geminiCredentialRefreshInFlight) return;
      geminiCredentialRefreshInFlight = true;
      appProviderCubit
          .loadProvidersFor(CliTool.gemini)
          .then((providers) {
            final key = providers
                .where((p) => p.id == 'google')
                .map((p) => p.apiKey.trim())
                .firstWhere((k) => k.isNotEmpty, orElse: () => '')
                .trim();
            cachedGeminiApiKey = key.isEmpty ? null : key;
          })
          .catchError((Object _) {})
          .whenComplete(() => geminiCredentialRefreshInFlight = false);
    }

    var grokCredentialRefreshInFlight = false;
    void refreshGrokCredential() {
      if (grokCredentialRefreshInFlight) return;
      grokCredentialRefreshInFlight = true;
      appProviderCubit
          .loadProvidersFor(CliTool.grok)
          .then((providers) {
            final key = providers
                .map((p) => p.apiKey.trim())
                .firstWhere((k) => k.isNotEmpty, orElse: () => '')
                .trim();
            cachedGrokApiKey = key.isEmpty ? null : key;
          })
          .catchError((Object _) {})
          .whenComplete(() => grokCredentialRefreshInFlight = false);
    }

    var claudeProviderRefreshInFlight = false;
    void refreshClaudeProvider() {
      if (claudeProviderRefreshInFlight) return;
      claudeProviderRefreshInFlight = true;
      appProviderCubit
          .loadProvidersFor(CliTool.claude)
          .then((providers) {
            cachedClaudeProvider = pickClaudeAcpProvider(
              providers: providers,
              selectedId: appProviderCubit
                  .state
                  .selectedProviderIdByCli[CliTool.claude],
            );
          })
          .catchError((Object _) {})
          .whenComplete(() => claudeProviderRefreshInFlight = false);
    }

    var codexProviderRefreshInFlight = false;
    void refreshCodexProvider() {
      if (codexProviderRefreshInFlight) return;
      codexProviderRefreshInFlight = true;
      appProviderCubit
          .loadProvidersFor(CliTool.codex)
          .then((providers) {
            cachedCodexProvider = pickCodexAcpProvider(
              providers: providers,
              selectedId:
                  appProviderCubit.state.selectedProviderIdByCli[CliTool.codex],
            );
          })
          .catchError((Object _) {})
          .whenComplete(() => codexProviderRefreshInFlight = false);
    }

    refreshClaudeProvider();
    refreshCodexProvider();
    refreshGeminiCredential();
    refreshGrokCredential();
    // Self-managing: when appProviderCubit closes (shell teardown), the
    // broadcast stream's onDone fires and nothing further is refreshed.
    appProviderCubit.stream.listen((_) {
      refreshClaudeProvider();
      refreshCodexProvider();
      refreshGeminiCredential();
      refreshGrokCredential();
    }, onDone: () {});

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
      sshProfiles: sshProfileRepo,
      cliPresetsCubit: () => cliPresetsCubit,
      sshProfileById: sshProfileById,
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
      sshProfiles: sshProfileRepo,
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
      sshProfileById: sshProfileById,
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
    final catalogWorkspaceBinder = CatalogWorkspaceBinder(
      repo: workspaceProjectConfigRepository,
    );
    Future<void> unbindMcpEverywhere(String mcpId) async {
      await teamCubit.removeMcpFromAllTeams(mcpId);
      final changed = await catalogWorkspaceBinder.unbindMcpFromAllWorkspaces(
        mcpId,
      );
      for (final workspaceId in changed) {
        await WorkspaceProjectConfigCubit.reloadLive(workspaceId);
      }
    }

    mcpCubit = McpCubit(
      mcpRepository,
      storage: homeStorage,
      onMcpUnbound: unbindMcpEverywhere,
      probeService: McpServerProbeService(
        handshake: McpDartProbeHandshake(storage: homeStorage),
      ),
    );
    hookCubit = HookCubit(repository: hookRepository)..load();

    // Catalog caches are device-local: on Android the home root is remote
    // (SFTP), so a cache under it costs a network round trip per read.
    final catalogCacheRoot = deviceLocalCatalogCacheRoot(nativeAppDataPath);
    final catalogCacheFs = deviceLocalCatalogCacheFilesystem(nativeAppDataPath);
    final teamHubSource = CompositeTeamHubSource.withDefaults(
      GitRegistryTeamHubSource(
        storage: homeStorage,
        fs: catalogCacheFs,
        cacheDirOverride: '$catalogCacheRoot/team-hub',
      ),
    );
    final teamHubFavorites = TeamHubFavoritesStore(storage: homeStorage);
    final localExpertStore = LocalExpertStore(
      fs: homeStorage.fs,
      dirOverride: homeStorage.paths.memberHubLocalTemplatesDir,
    );
    // Unreachable SSH home: defer these home-plane reads to the post-connect
    // chain (the catalog warm below is already background and tolerates an
    // empty local store meanwhile).
    if (!deferHomePlaneLoads) {
      await localExpertStore.migrateLegacyLayout();
      await localExpertStore.ensureIndexLoaded();
    }
    final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
      registry: GitRegistryExpertHubSource(
        storage: homeStorage,
        fs: catalogCacheFs,
        cacheDirOverride: '$catalogCacheRoot/member-hub',
      ),
      teamIndex: teamHubSource.fetchTeams,
      localStore: localExpertStore,
    );
    final expertHubCatalog = ExpertHubCatalog(source: compositeExpertHubSource);
    // The home-index load materializes every team roster, which blocks on this
    // catalog's first snapshot (registry fetch on a cold cache). Warm it now so
    // that read overlaps the rest of shell wiring instead of the splash.
    unawaited(() async {
      try {
        await expertHubCatalog.snapshot();
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[boot] expert catalog warm failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
    final expertCloneService = ExpertCloneService(
      source: compositeExpertHubSource,
      store: localExpertStore,
      catalog: expertHubCatalog,
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
      cloneTeam: (team, {teamMode, cli}) => installJobRegistry.enqueue(
        InstallJobSpec(
          key: InstallJobKeys.hubTeam(team.key),
          title: 'Clone ${team.name}',
          cancelPolicy: InstallCancelPolicy.cooperative,
          historyMessageFor: (result) => result.hasFailures
              ? 'Cloned ${team.name} with ${result.failedDeps.length} dependency failures'
              : 'Cloned ${team.name}',
          run: (ctx) => teamCloneService.clone(
            team,
            teamMode: teamMode,
            cli: cli,
            onProgress: (progress) => reportHubCloneProgress(ctx, progress),
          ),
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

    final expertHubFavorites = ExpertHubFavoritesStore(storage: homeStorage);
    teamCubit.attachCatalog(expertHubCatalog);
    final expertCapabilityResolver = ExpertCapabilityResolver(
      installSkill: skillCubit.installTeamDependency,
      installPlugin: pluginCubit.installTeamDependency,
      installMcp: mcpCubit.installTeamDependency,
      localStore: localExpertStore,
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
      installJobRegistry: installJobRegistry,
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
    final workspaceToolsCubit = WorkspaceToolsCubit(
      persist: (set) {
        unawaited(layoutCubit.setRightToolOpenSet(set));
      },
    );
    final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
    final gitRepoStore = GitRepoStore(storage: homeStorage);
    final workspaceFileTreeStore = WorkspaceFileTreeStore();
    final workspaceSearchIndexes = WorkspaceSearchIndexes(storage: homeStorage);
    final workspaceWorktreeRegistry = WorkspaceWorktreeRegistry(
      storage: homeStorage,
      gitMutationSignals: gitRepoStore.headChanged,
    );
    final workspaceSessionGroupsRegistry = WorkspaceSessionGroupsRegistry(
      storage: homeStorage,
      cubitFactory: () => SessionGroupsCubit(
        storage: homeStorage,
        knownSessionIds: () => {
          for (final s in chatCubit.state.sessions) s.sessionId,
        },
      ),
    );
    final workspaceToolsScopeRegistry = WorkspaceToolsScopeRegistry();
    final workspaceRunRegistry = WorkspaceRunRegistry(
      storage: homeStorage,
      platformFactory: WorkspaceRunPlatformFactory(
        storage: homeStorage,
        extensionRepository: extensionRepository,
        projectConfigRepository: workspaceProjectConfigRepository,
        resolveWorkContext:
            sessionLifecycleService.resolveWorkContextForTargetId,
        sshProfileRepository: sshProfileRepo,
        sshClientFactory: sshClientFactory,
        homeTarget: defaultTargetResolver,
      ),
    );
    final configCubit = ConfigCubit();
    ConnectCubit? connectCubit;
    ConnectSshBackend? embeddedSshServer;
    ConnectSshBackend? systemSshdBackend;
    PairedDeviceStore? connectDeviceStore;
    if (!Platform.isAndroid) {
      final localFs = LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
      );
      final nativeHome =
          (Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '')
              .trim();
      if (nativeHome.isEmpty) {
        throw StateError('Could not resolve the local user home for Connect');
      }
      final username =
          (Platform.environment['USER'] ??
                  Platform.environment['USERNAME'] ??
                  localFs.pathContext.basename(nativeHome))
              .trim();
      final settingsStore = ConnectSettingsStore(
        fs: localFs,
        appDataRoot: nativeAppDataPath,
      );
      final settings = await settingsStore.load();
      final pairedDeviceStore = PairedDeviceStore(
        fs: localFs,
        appDataRoot: nativeAppDataPath,
      );
      connectDeviceStore = pairedDeviceStore;
      final server = EmbeddedSshServer(
        fs: localFs,
        appDataRoot: nativeAppDataPath,
        deviceStore: pairedDeviceStore,
        username: username,
        homePath: nativeHome,
      );
      final systemSshdSelectable = Platform.isLinux || Platform.isMacOS;
      final systemBackend = systemSshdSelectable
          ? SystemSshdBackend(
              presence: SshdPresence(
                probe: loopbackSshdProbe(),
                scan: sshKeyScanRunner(
                  run: (exe, args) async {
                    final result = await Process.run(exe, args);
                    return (
                      exitCode: result.exitCode,
                      stdout: result.stdout.toString(),
                      stderr: result.stderr.toString(),
                    );
                  },
                ),
              ),
              authorizedKeys: AuthorizedKeysFile(
                fs: localFs,
                homePath: nativeHome,
                chmod600: (path) async {
                  await Process.run('chmod', ['600', path]);
                },
              ),
            )
          : null;
      final backendHost = ConnectBackendHost(
        embedded: server,
        system: systemBackend,
        settings: settingsStore,
        systemSshdSelectable: systemSshdSelectable,
      );
      try {
        await backendHost.startSelected();
      } on Object catch (error, stackTrace) {
        // Non-blocking: the app continues; the Connect UI shows the failed
        // state with a retry affordance. Broad on purpose — anything from a
        // typed [EmbeddedSshServerStartException] (bind conflicts) to a
        // host-key persistence failure must not crash app boot.
        appLogger.e(
          '[connect] ssh backend failed to start',
          error: error,
          stackTrace: stackTrace,
        );
      }
      embeddedSshServer = server;
      systemSshdBackend = systemBackend;
      final connectAgent = ConnectAgent.production(
        sshBackend: backendHost.current,
        fs: localFs,
        extraEndpoints: settings.extraEndpoints,
        deviceStore: pairedDeviceStore,
      );
      // App-lifetime relay registration: keeps off-LAN SSH reachable via
      // device grants even when no QR is on screen.
      final relayUrl = settings.relayUrl.trim();
      if (relayUrl.isNotEmpty) {
        try {
          final uri = Uri.parse(relayUrl);
          if (uri.scheme == 'ws' || uri.scheme == 'wss') {
            await connectAgent.enableRelay(
              appDataRoot: nativeAppDataPath,
              registration: _relayRegistrationFor(uri),
            );
          }
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[connect-relay] startup registration failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      connectCubit = ConnectCubit(
        agent: ConnectAgentController.fromAgent(connectAgent),
        backends: backendHost,
        systemSshdHint: Platform.isMacOS
            ? ConnectSystemSshdHint.macos
            : (Platform.isLinux
                  ? ConnectSystemSshdHint.linux
                  : ConnectSystemSshdHint.none),
        deviceStore: pairedDeviceStore,
        settingsStore: settingsStore,
        listNetworkAddresses: () async {
          final interfaces = await NetworkInterface.list(includeLoopback: true);
          return [
            for (final interface in interfaces)
              for (final address in interface.addresses)
                ConnectNetworkAddress(
                  name: interface.name,
                  address: address.address,
                  isLoopback: address.isLoopback,
                  isIpv4: address.type == InternetAddressType.IPv4,
                ),
          ];
        },
        username: username,
        displayName: Platform.localHostname,
        appDataRoot: nativeAppDataPath,
      );
    }
    final commandBus = CommandBus();
    final shortcutCubit = ShortcutCubit(storage: homeStorage);
    final workspaceChromeCommands = WorkspaceChromeCommands();
    final runCommandHost = RunCommandHost();
    final workspaceSearchHost = WorkspaceSearchHost();
    final workspaceContentSearchHost = WorkspaceContentSearchHost();
    final uiZoomBaseline = UiZoomBaseline();
    registerShortcutsUiCommands(commandBus);
    registerRunCommands(commandBus, runCommandHost);
    registerWorkspaceSearchCommands(commandBus, workspaceSearchHost);
    registerWorkspaceContentSearchCommands(
      commandBus,
      workspaceContentSearchHost,
    );

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
      fs: homeStorage.fs,
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
              termuxWorkOpsBlockedMessage:
                  TermuxWorkOpsMessage.disconnectedBlocked,
            ),
      ),
    );

    final automationRepo = AutomationRepository(
      fs: homeStorage.fs,
      layout: WorkspaceLayout(
        teampilotRoot: homeStorage.paths.basePath,
        fs: homeStorage.fs,
      ),
    );
    final teammateBusMcpGateway = TeammateBusMcpGateway();
    await teammateBusMcpGateway.ensureStarted();

    // Shared AskUserAnswerPendingStore singleton (lives in buildAppShell):
    // gateway GET /ask-user-answer + ChatCubit answer facade must reuse
    // this instance — do not construct a second store.
    final askUserAnswerPendingStore = AskUserAnswerPendingStore();
    teammateBusMcpGateway.attachAskUserAnswerStore(askUserAnswerPendingStore);
    final askUserQuestionHookGate = AskUserQuestionHookGate();
    final generalPermissionRequestGate = GeneralPermissionRequestGate();
    final askUserQuestionAnswerService = AskUserQuestionAnswerService(
      store: askUserAnswerPendingStore,
      hookGate: askUserQuestionHookGate,
      generalPermissionGate: generalPermissionRequestGate,
    );
    final exitPlanModeHookGate = ExitPlanModeHookGate();
    final exitPlanPermissionRequestGate = ExitPlanPermissionRequestGate();
    final exitPlanModeApprovalService = ExitPlanModeApprovalService(
      hookGate: exitPlanModeHookGate,
      permissionGate: exitPlanPermissionRequestGate,
    );

    final agentAttentionCubit = AgentAttentionCubit();
    final seatLeaseCubit = SeatLeaseCubit();
    final agentStatusSeatLookup = AgentStatusSeatLookup();
    final agentRuntimeStream = SeatEventStream();
    final askUserQuestionProjection = AskUserQuestionRuntimeEventProjection(
      hookGate: askUserQuestionHookGate,
    );
    final exitPlanModeProjection = ExitPlanModeRuntimeEventProjection(
      hookGate: exitPlanModeHookGate,
      permissionGate: exitPlanPermissionRequestGate,
    );
    final generalPermissionProjection = GeneralPermissionRuntimeEventProjection(
      gate: generalPermissionRequestGate,
    );
    final runtimeProjections = [
      RuntimeEventProjection.attention(
        attention: agentAttentionCubit,
        resolveSkipPermissions: agentStatusSeatLookup.resolveSkipPermissions,
      ),
      seatLeaseProjection(leases: seatLeaseCubit),
      askUserQuestionProjection,
      exitPlanModeProjection,
      generalPermissionProjection,
    ];
    final agentEventGateway = AgentEventGateway(
      journal: FileRuntimeEventJournal(
        journalRoot: homeStorage.fs.pathContext.join(
          homeStorage.paths.basePath,
          'runtime-events',
        ),
        fs: homeStorage.fs,
      ),
      stream: agentRuntimeStream,
      resolveCli: agentStatusSeatLookup.resolveCli,
      projections: runtimeProjections,
      responders: [
        askUserQuestionProjection,
        exitPlanModeProjection,
        generalPermissionProjection,
      ],
    );
    teammateBusMcpGateway.attachAgentEventGateway(agentEventGateway);

    catalogRuntime = CatalogRuntime.assemble(
      storage: homeStorage,
      sessions: sessionRepo,
      runtimeContexts: runtimeContextRegistry,
      skillRepository: skillRepo,
      skillInstall: skillInstallService,
      skillEngine: skillAcquisitionEngine,
      pluginRepository: pluginRepository,
      pluginInstall: pluginRepository.install,
      mcpRepository: mcpRepository,
      workspaceConfig: workspaceProjectConfigRepository,
      searchSkills: (query) => CatalogProduction.searchSkills(
        query,
        registryConfig: skillRegistryConfigService,
        repository: skillRepo,
      ),
      searchPlugins: (query) => CatalogProduction.searchPlugins(
        query,
        repos: pluginRepository.repos,
        diskCache: PluginRepoDiskCacheService(
          filesystem: homeStorage.fs,
          teampilotRoot: homeStorage.paths.basePath,
        ),
      ),
      searchMcp: (query) =>
          CatalogProduction.searchMcp(query, storage: homeStorage),
      draftFromListing: (listingId) =>
          CatalogProduction.draftFromListing(listingId, storage: homeStorage),
      installPluginFromDiscovery: (args) =>
          CatalogProduction.installPluginFromDiscovery(
            args,
            storage: homeStorage,
            repository: pluginRepository,
          ),
      removeSkillFromAllTeams: teamCubit.removeSkillFromAllTeams,
      removePluginFromAllTeams: teamCubit.removePluginFromAllTeams,
      removeMcpFromAllTeams: teamCubit.removeMcpFromAllTeams,
    );
    teammateBusMcpGateway.attachCatalogHandler(
      catalogRuntime.handler,
      resolveSession: catalogRuntime.resolveSession,
    );
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
          final profiles = <String, SshProfile>{};
          for (final id in profileIds) {
            final profile = await sshProfileRepo.findById(id);
            if (profile != null) profiles[id] = profile;
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
    chatCubit = ChatCubit(
      storage: homeStorage,
      promptDeliveries: () => appScopedPromptDeliveries,
      teammateBusMcpGateway: teammateBusMcpGateway,
      agentStatusSeatLookup: agentStatusSeatLookup,
      agentAttentionCubit: agentAttentionCubit,
      seatLeaseCubit: seatLeaseCubit,
      askUserAnswerPendingStore: askUserAnswerPendingStore,
      askUserQuestionAnswerService: askUserQuestionAnswerService,
      generalPermissionGate: generalPermissionRequestGate,
      exitPlanApprovalService: exitPlanModeApprovalService,
      sessionRepository: sessionRepo,
      lifecycleService: sessionLifecycleService,
      automationRepository: automationRepo,
      layoutCubit: layoutCubit,
      autoLaunchAllMembersOnConnect: () => sessionPreferencesCubit
          .state
          .preferences
          .autoLaunchAllMembersOnConnect,
      discoveredAcpAdapterPath: sessionPreferencesCubit.resolveAcpAdapterPath,
      acpAdapterPathOverride: targetsRepo.acpAdapterPathOverride,
      reclaimIdleTerminalsEnabled: () =>
          sessionPreferencesCubit.state.preferences.reclaimIdleTerminals,
      reclaimIdleTerminalAfterSeconds: () => sessionPreferencesCubit
          .state
          .preferences
          .reclaimIdleTerminalAfterSeconds,
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
      remoteBusSetup: RemoteMemberBusSetup(
        resolver: RemoteBusBindingResolver(registry: cliToolRegistry),
      ),
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
        loadLocalCredentials: (cli) =>
            LocalCredentialExporter(storage: homeStorage).export(cli),
        localCliPath: (cli) async =>
            sessionPreferencesCubit.resolveExecutable(cli),
        runtimePlanBuilder: sessionRuntimePlanBuilder,
      ),
      remoteCliReadiness: remoteCliReadiness,
      installJobRegistry: installJobRegistry,
      termuxConnectedResolver: () => termuxGateCubit?.state.connected ?? true,
      termuxDisconnectedWorkOpsMessageResolver:
          TermuxWorkOpsMessage.disconnectedBlocked,
      termuxGateHomeResolver: defaultTargetResolver,
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
    final promptDeliveryStore = FilePromptDeliveryStore(
      root: homeStorage.fs.pathContext.join(
        homeStorage.paths.basePath,
        'prompt-deliveries',
      ),
      fs: homeStorage.fs,
    );
    appScopedPromptDeliveries = PromptDeliveryCoordinator(
      store: promptDeliveryStore,
      commands: TabPromptDeliveryCommands(chatCubit.tabStore),
    );
    // One app-scoped runtime join: journaled hooks drive delivery correlation
    // under per-seat serialization; restoreSession replays both durable stores
    // before a session's input is enabled (see SessionLifecycleService).
    final agentRuntime = AgentRuntime(
      gateway: agentEventGateway,
      projections: runtimeProjections,
      promptDeliveries: appScopedPromptDeliveries,
    );
    sessionLifecycleService.attachAgentRuntime(agentRuntime);

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
        targetRegistry: runtimeTargetRegistry,
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
    void refreshAutomations() {
      if (!automationCubit.isClosed) {
        unawaited(automationCubit.reloadPreservingScope());
      }
    }

    final automationCommandRunner = HostAutomationCommandRunner(
      workspaceById: (workspaceId) => chatCubit.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull,
      resolver: RunTargetResolver(homeTarget: defaultTargetResolver),
      executor: ProcessRunExecutor(sshSpawner: repoCloneSshSpawner),
    );
    final automationCommandExecutor = AutomationCommandExecutor(
      repository: automationRepo,
      accounting: AutomationRunAccounting(scheduleCalculator),
      runner: automationCommandRunner,
      onAfterRun: refreshAutomations,
    );
    final automationDispatcher = AutomationDispatcher(
      repository: automationRepo,
      scheduleCalculator: scheduleCalculator,
      sessionRepository: sessionRepo,
      busGateway: TabTeamBusGateway(
        memberMaterializer: chatCubit.memberMaterializer,
        sessionRuntime: chatCubit.sessionRuntime,
        tabStore: chatCubit.tabStore,
        activatePersonalAcp: chatCubit.retrySessionLaunch,
        activateMemberSeat: chatCubit.ensureMemberTerminalForView,
      ),
      requestOpenSession: chatCubit.requestOpenSession,
      requestCreateAndOpenSession: chatCubit.requestCreateAndOpenSession,
      workspaceById: (workspaceId) => chatCubit.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull,
      teamById: teamById,
      resolveCliPreset: resolveCliPreset,
      sessionById: (sessionId, workspaceId) => chatCubit.state.sessions
          .where(
            (s) => s.sessionId == sessionId && s.workspaceId == workspaceId,
          )
          .firstOrNull,
      applySessionTitle: chatCubit.applySessionTitle,
      acpDefaultFor: sessionPreferencesCubit.acpDefaultFor,
      runDeliveryInFlight: chatCubit.withOperatorDeliveryInFlight,
    );
    automationScheduler = AutomationScheduler(
      repository: automationRepo,
      dispatcher: automationDispatcher,
      scheduleCalculator: scheduleCalculator,
      commandExecutor: automationCommandExecutor,
    );
    automationCubit = AutomationCubit(
      repository: automationRepo,
      scheduler: automationScheduler,
      scheduleCalculator: scheduleCalculator,
    );
    chatCubit.bindAutomationsChangeNotifier(refreshAutomations);
    // Registered here rather than in CatalogRuntime.assemble because the
    // automation repo, scheduler and resolver locals are constructed below
    // that assemble call. The registry recomputes routes on every call, so
    // these tools appear as soon as this runs; the bus subscription refreshes
    // the Automations page after catalog-driven writes.
    catalogRuntime.registry.register(
      AutomationCatalogModule(
        repository: automationRepo,
        scheduleCalculator: scheduleCalculator,
        bus: catalogRuntime.bus,
        runNow: automationScheduler.runNow,
        teamExists: (teamId) => teamById(teamId) != null,
        presetExists: (presetId) => resolveCliPreset(presetId) != null,
        memberExists: (teamId, memberId) {
          final team = teamById(teamId);
          return team != null &&
              team.members.any((m) => m.id == memberId && m.isValid);
        },
        sessionExists: (sessionId, workspaceId) async {
          final session = await sessionRepo.findById(sessionId);
          return session != null && session.workspaceId == workspaceId;
        },
        workspaceFolders: (workspaceId) => chatCubit.state.workspaces
            .where((w) => w.workspaceId == workspaceId)
            .firstOrNull
            ?.folders,
      ),
    );
    final automationCatalogSub = catalogRuntime.bus.listen().listen((event) {
      if (event.kind != 'automation') return;
      refreshAutomations();
    });

    final mailboxCubit = MailboxCubit(
      busForScope: (scope) => scopedTeamBus(workbenchCubit, chatCubit, scope),
    );

    final boardCubit = BoardCubit(
      busForScope: (scope) => scopedTeamBus(workbenchCubit, chatCubit, scope),
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
    workspaceSearchIndexes.cachedHistoryMessages =
        ({required sessionId, required memberId, required token}) =>
            aiHistoryLoader.messagesIfCached(
              sessionId: sessionId,
              memberId: memberId,
              token: token,
            );
    // Pods own a per-session HistoryStore once the loader exists (ChatCubit is
    // constructed earlier); SessionChatView binds seats through the pod.
    chatCubit.historyLoader = aiHistoryLoader;
    final aiHistoryCubit = AiHistoryCubit(
      loader: aiHistoryLoader,
      loadMailboxRecords: (sessionId, memberId) async {
        final bus = chatCubit.tabStore
            .getOpenTabBySessionId(sessionId)
            ?.teamBus;
        if (bus == null) return const [];
        return bus.memberMailRecords(memberId);
      },
    );
    final sessionRemoteActivityCubit = SessionRemoteActivityCubit();
    final sessionAuthority = SessionAuthority(
      authorityId: SharedStateIdentity.deviceId,
      controlPort: ChatSessionControlPort(chatCubit),
    );
    final sessionActivitySource = ChatSessionActivitySource(chatCubit);
    final contentInvalidationSub = SessionContentInvalidationBus.stream.listen((
      event,
    ) {
      if (!connectionModeService.isLocalMode) return;
      sessionAuthority.publishContentInvalidated(
        sessionId: event.sessionId,
        memberId: event.memberId,
      );
    });
    final contentStreamSub = SessionContentStreamBus.stream.listen((chunk) {
      if (!connectionModeService.isLocalMode) return;
      sessionAuthority.publishContentDelta(
        sessionId: chunk.sessionId,
        memberId: chunk.memberId,
        kind: 'acp.messages',
        payload: chunk.payload,
        partial: !chunk.replace,
      );
    });
    final sessionRemoteRefreshSub = sessionRemoteActivityCubit.stream.listen((
      state,
    ) {
      if (!connectionModeService.isSshMode) return;
      final known = {
        for (final session in chatCubit.state.sessions) session.sessionId,
      };
      for (final snapshot in state.sessions.values) {
        final workspaceId = snapshot.workspaceId;
        if (workspaceId.isEmpty) continue;
        chatCubit.upsertRemoteSessionHint(
          sessionId: snapshot.sessionId,
          workspaceId: workspaceId,
        );
        if (known.contains(snapshot.sessionId)) continue;
        unawaited(chatCubit.refreshSessionsForWorkspace(workspaceId));
      }
    });
    Future<void> notifyRemoteAttention(SessionAttention attention) async {
      if (attention.kind != 'idle') return;
      final session = chatCubit.state.sessions
          .where((item) => item.sessionId == attention.sessionId)
          .firstOrNull;
      final title = (session?.display.trim().isNotEmpty ?? false)
          ? session!.display.trim()
          : attention.sessionId;
      final locale = PlatformDispatcher.instance.locale;
      final l10n = lookupAppLocalizations(
        basicLocaleListResolution([locale], appLocalizationsSupportedLocales),
      );
      final payload = HomeWorkspaceRoute.sessionLocation(
        workspaceId: session?.workspaceId ?? '',
        sessionId: attention.sessionId,
      );
      notificationCubit.record(
        title: title,
        message: l10n.session.idleNotificationSubtitle,
        variant: TpToastVariant.success,
        payload: payload,
      );
      final notifier = DesktopSystemNotifier.instance;
      if (await notifier.isAppFocused()) return;
      await notifier.showNotification(
        title: title,
        body: l10n.session.idleNotificationSubtitle,
        subtitle: l10n.session.idleNotificationTitle,
        payload: payload,
      );
    }

    final sessionProtocolController = SessionProtocolController(
      deviceId: SharedStateIdentity.deviceId,
      remoteCubit: sessionRemoteActivityCubit,
      authority: sessionAuthority,
      isExpectedFailure: isSshProfileDown,
      waitForRecovery: waitForSshProfileRecovery,
      onContentInvalidated: (invalidation) {
        SessionContentInvalidationBus.publish(
          sessionId: invalidation.sessionId,
          memberId: invalidation.memberId,
        );
        chatCubit.onSessionHistoryStale?.call(invalidation.sessionId);
      },
      onContentDelta: (delta) {
        if (delta.kind != 'acp.messages') return;
        SessionContentStreamBus.publish(
          sessionId: delta.sessionId,
          memberId: delta.memberId,
          payload: delta.payload,
          replace: !delta.partial,
        );
      },
      onSessionList: (delta) {
        if (!connectionModeService.isSshMode) return;
        chatCubit.applyRemoteSessionList(
          workspaceId: delta.workspaceId,
          upserted: delta.upserted,
          removed: delta.removed,
        );
      },
      onAttention: (attention) {
        unawaited(notifyRemoteAttention(attention));
      },
    );
    void reloadHistorySeat(String sessionId) {
      unawaited(aiHistoryCubit.softReloadIfSession(sessionId));
    }

    chatCubit.onSessionHistoryStale = (sessionId) {
      reloadHistorySeat(sessionId);
      if (connectionModeService.isLocalMode) {
        sessionAuthority.publishContentInvalidated(sessionId: sessionId);
      }
    };
    chatCubit.onSessionCreated = (session) {
      final entry = SessionListEntry.fromSession(session).toJson();
      if (connectionModeService.isLocalMode) {
        sessionAuthority.publishSessionList(
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
        sessionAuthority.publishSessionList(
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

    Future<void>? managedProviderHydration;
    Future<void> hydrateManagedProviderData() {
      final existing = managedProviderHydration;
      if (existing != null) return existing;
      final future = managedProviderControlPlane.hydrate(boot: boot);
      managedProviderHydration = future;
      return future;
    }

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
    Future<void> sweepStaleMarketplaceClones() async {
      try {
        await MarketplaceSharedStore(
          fs: homeStorage.fs,
          teampilotRoot: homeStorage.paths.basePath,
        ).sweepAll(
          workspaceIds: [
            for (final workspace in chatCubit.state.workspaces)
              workspace.workspaceId,
          ],
          activeSessionKeys: {
            for (final tab in chatCubit.tabStore.openTabs) tab.sessionId,
          },
        );
      } on Object catch (e, st) {
        appLogger.w('[boot] marketplaceCloneSweep failed: $e\n$st');
      }
    }

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

    /// Publishes the live SSH home plane after recovery. `reinstallStorageContext`
    /// re-resolves the target with the transport now live, so a successful swap
    /// means the whole app object graph can keep running on the SSH plane — no
    /// restart needed. Returns null on success, or the error kind to surface on
    /// the connection page when the swap failed (or still left a native plane).
    Future<HomeErrorKind?> rebindHomeStoragePlane() async {
      try {
        await homeInvalidationService.runSelfInitiatedSwap(
          reinstallStorageContext,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[boot] home storage plane rebind failed',
          error: error,
          stackTrace: stackTrace,
        );
        return isSshHostKeyFailure(error)
            ? HomeErrorKind.hostIdentityChanged
            : isSshAuthFailure(error)
            ? HomeErrorKind.authFailed
            : HomeErrorKind.transportError;
      }
      return homeStorage.context.mode == StorageBackendMode.ssh
          ? null
          : HomeErrorKind.transportError;
    }

    /// Warm the shell-hosted config + auxiliary data and resolve onboarding.
    /// Shared by the native path and the remote (post-connect) boot so both
    /// stay identical; returns `showOnboardingWizard`.
    Future<bool> warmShellAndPrepareInteractive() async {
      await yieldUiFrame();
      // Managed Provider cache hydration is deliberately background work. The
      // shell can paint while the global Cubits transition from initial to
      // ready, and the Cubit load methods keep repeated bootstrap calls single-
      // flight.
      unawaited(hydrateManagedProviderData());
      boot(
        'bootstrapAppData index ready '
        'workspaces=${chatCubit.state.workspaces.length} '
        '(sessions load on demand)',
      );
      unawaited(sweepStaleMarketplaceClones());
      bootstrapCubit?.beginWarmAuxiliary();
      // Only host config the home shell renders stays on the splash path.
      // Model catalogs are composer-only, and the rest (plugins, skills, MCP,
      // extensions, team resource syncs, llmConfig) loads in the background
      // behind its own loading states.
      await AppDataBootstrap.warmShellConfig(
        boot: boot,
        appProviderCubit: appProviderCubit,
      );
      unawaited(() async {
        try {
          await AppDataBootstrap.warmAuxiliaryData(
            boot: boot,
            llmConfigCubit: llmConfigCubit,
            appProviderCubit: appProviderCubit,
            teamCubit: teamCubit,
            pluginCubit: pluginCubit,
            skillCubit: skillCubit,
            mcpCubit: mcpCubit,
            extensionCubit: extensionCubit,
          );
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[boot] auxiliary warm-up failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }());
      return AppDataBootstrap.prepareInteractiveShell(
        boot: boot,
        appSettings: appSettings,
        sshProfileCubit: sshProfileCubit,
        cliPresetsCubit: cliPresetsCubit,
        aiFeatureSettingsCubit: aiFeatureSettingsCubit,
        discoverySettingsCubit: discoverySettingsCubit,
        homeWorkspaceUiCache: homeWorkspaceUiCache,
        storage: homeStorage,
        workspaces: chatCubit.state.workspaces,
      );
    }

    // Remote (home-storage) boot steps, deferred until the SSH home is known
    // reachable. A completed chain retires the retry surface; an in-flight
    // guard coalesces concurrent callers, and a failed chain leaves the flags
    // unset so the next reconnect retries it.
    var remoteBootCompleted = false;
    var remoteIndexBootstrapped = false;
    var deferredHomePlaneLoadsDone = false;
    var remoteShowOnboarding = false;
    Future<bool>? remoteBootInFlight;

    Future<bool> runRemoteBootAfterConnectOnce() async {
      // A first-ever-unreachable SSH home has no persisted `lastHome`, so boot
      // fell back to the native control plane (see `resolveCached`). Never
      // write the remote index/config into that plane: it would silently
      // diverge from the home the user believes they are on. The mismatch
      // self-heals on the next launch, when the live home resolves before boot.
      if (defaultTargetResolver().kind == RuntimeKind.ssh &&
          homeStorage.context.mode != StorageBackendMode.ssh) {
        appLogger.w(
          '[boot] home storage plane mismatch; skipping remote boot until restart',
        );
        return remoteShowOnboarding;
      }
      // Home-plane reads skipped during an unreachable splash (they are not
      // shown while the connection page is up). Run them now that the
      // transport is live.
      if (deferHomePlaneLoads) {
        try {
          await notificationBootstrap();
        } on Object catch (error, stackTrace) {
          // Notifications are off the shell's critical path. Keep warming the
          // rest; `retryableMemo` clears the failed attempt, so the next
          // reconnect tries it again.
          appLogger.w(
            '[boot] notification bootstrap failed after reconnect',
            error: error,
            stackTrace: stackTrace,
          );
        }
        if (!deferredHomePlaneLoadsDone) {
          await shortcutCubit.load();
          await localExpertStore.migrateLegacyLayout();
          await localExpertStore.ensureIndexLoaded();
          // The boot-time catalog warm cached a snapshot without the local
          // templates; invalidate so the next read includes them.
          expertHubCatalog.invalidate();
          deferredHomePlaneLoadsDone = true;
        }
      }
      // Deliberately not `bootstrapCubit.state.homeIndexReady`: that getter is
      // also true once the phase is `ready`, which is exactly the state a
      // deferred boot leaves behind, and hot recovery must still load the
      // index it skipped.
      if (!remoteIndexBootstrapped) {
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
            // buildAppShell just materialized the home context from the same
            // on-disk profiles this bootstrap reloads, so a rebind here would
            // only repeat the path probe (~0.7s over SSH) with no new input.
            reinstallSshHome: false,
            // Not invoked while the flag above is false. Kept bracketed:
            // a reinstall outside the invalidation service's reload would
            // publish a swap that echoes back as an external home switch and
            // schedules a duplicate full bootstrap.
            reinstallStorageContext: () => homeInvalidationService
                .runSelfInitiatedSwap(reinstallStorageContext),
            storage: homeStorage,
            home: defaultTargetResolver(),
            expertHubCatalog: expertHubCatalog,
          );
          await persistSshHomePathCacheIfLive();
          remoteIndexBootstrapped = true;
          bootstrapCubit?.markHomeIndexReady();
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[boot] remote home index bootstrap failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      remoteShowOnboarding = await warmShellAndPrepareInteractive();
      // Completed only once the whole chain succeeded: a transient failure
      // after a flaky reconnect must remain retryable by the next onConnected
      // (the status is `connected`, so the user has no manual retry surface).
      remoteBootCompleted = remoteIndexBootstrapped;
      return remoteShowOnboarding;
    }

    Future<bool> runRemoteBootAfterConnect() {
      if (remoteBootCompleted) return Future.value(remoteShowOnboarding);
      final inFlight = remoteBootInFlight;
      if (inFlight != null) return inFlight;
      final future = runRemoteBootAfterConnectOnce();
      remoteBootInFlight = future;
      return future.whenComplete(() {
        if (identical(remoteBootInFlight, future)) {
          remoteBootInFlight = null;
        }
      });
    }

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
              final failure = await rebindHomeStoragePlane();
              if (failure != null) {
                cubit?.markUnreachable(failure);
                return;
              }
              cubit?.markPlaneReady();
            }
            await runRemoteBootAfterConnect();
            await reconnectHomeSshIfNeeded();
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
    if (isSshHome && !initialHome.reachable) {
      sshProfileConnectionCoordinator.restartReconnect(homeProfileId);
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

    Future<void> bootstrapAppData() async {
      final connected =
          homeConnectionCubit?.state.status == HomeConnectionStatus.connected;
      final remoteWorkPlane = connectionModeService.isRemoteWorkPlane;
      // An unreachable SSH home defers every home-storage read: the shell must
      // paint the connection page without waiting on a dead transport. The
      // deferred chain runs once on the first successful (re)connect.
      final deferRemoteBoot = remoteWorkPlane && !connected;
      var showOnboarding = false;
      if (!deferRemoteBoot) {
        await notificationBootstrap();
        final indexReady = bootstrapCubit?.state.homeIndexReady ?? false;
        if (!indexReady) {
          bootstrapCubit?.beginHomeIndex();
        }
        boot('bootstrapAppData start');
        if (remoteWorkPlane) {
          showOnboarding = await runRemoteBootAfterConnect();
        } else {
          if (!indexReady) {
            boot('awaiting home index snapshots');
            await homeIndexPrefetch;
            await AppDataBootstrap.hydrateNativeHomeIndex(
              boot: boot,
              teamCubit: teamCubit,
              chatCubit: chatCubit,
              sessionRepo: sessionRepo,
              layoutCubit: layoutCubit,
              storage: homeStorage,
              home: defaultTargetResolver(),
              expertHubCatalog: expertHubCatalog,
            );
            bootstrapCubit?.markHomeIndexReady();
          }
          showOnboarding = await warmShellAndPrepareInteractive();
        }
      } else {
        // The device-local SSH catalog is the one boot read that must survive
        // an unreachable home: the connection page lists it to switch/recover,
        // and it never lives on the home plane. Deferring it together with the
        // remote boot left 「切换连接」 empty even though remote-targets.json
        // held every saved target. It is a local file read, so awaiting it
        // cannot stall on the dead transport.
        try {
          await sshProfileCubit.load(discoverRemoteCli: false);
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[boot] device-local SSH catalog load failed while the home was '
            'unreachable',
            error: error,
            stackTrace: stackTrace,
          );
        }
        boot('bootstrapAppData deferred: home unreachable');
      }
      // Unconditional: both the connected and the deferred (unreachable) path
      // must finish boot so StartupGate can render the connection page.
      bootstrapCubit?.markAppReady(showOnboardingWizard: showOnboarding);
      LivePerfDriver.instance?.markAppReady();
      boot('bootstrapAppData complete');
      if (connected) {
        // Team-generation jobs are not auto-resumed at cold start. Incomplete
        // builder/destination sessions reconnect only when the user opens them.
        // Never on the splash path: the shell is already marked ready, so a
        // failure here is logged rather than surfaced as a boot error.
        unawaited(
          reconnectHomeSshIfNeeded().catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            appLogger.w(
              '[boot] home ssh resume failed',
              error: error,
              stackTrace: stackTrace,
            );
          }),
        );
      }
      automationScheduler.start();
    }

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
        sessionAuthority.clear();
        sessionActivitySource.start(sessionAuthority);
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

    Future<void> switchHomeTarget(String id) async {
      final previousSshProfileId = activeHomeProfileId;
      // Prime the edit-watch baseline before the switch publishes anything, so
      // the path-cache write inside setHomeTarget is not mistaken for a user
      // edit of the new target.
      final pendingTarget = homeTargetFromId(id);
      final pendingProfileId =
          pendingTarget.kind == RuntimeKind.ssh &&
              (pendingTarget.sshProfileId ?? '').isNotEmpty
          ? pendingTarget.sshProfileId
          : null;
      final pendingProfile = pendingProfileId == null
          ? null
          : sshProfileById(pendingProfileId);
      watchedHomeProfileConnectivityKey = pendingProfile == null
          ? null
          : sshProfileConnectivityKey(pendingProfile);
      await setHomeTarget(
        id,
      ); // persists + rebinds home + republishes HomeStorage
      final nextSshProfileId = activeHomeProfileId;
      if (previousSshProfileId != nextSshProfileId) {
        // Latch the abandoned profile (in-flight attempts back out, timer is
        // dropped) and move the persistent retry loop to the new home — in one
        // supervisor command instead of two independent coordinator calls.
        sshHomeConnectivity.activateHome(nextSshProfileId);
      }
      // Reseed the connection cubit onto the new target. Its callbacks read
      // `activeHomeProfileId`, so without this the gate would keep showing the
      // connection page and 「继续重试」 would retry the abandoned home.
      final nextProfile = nextSshProfileId == null
          ? null
          : sshProfileById(nextSshProfileId);
      watchedHomeProfileConnectivityKey = nextProfile == null
          ? null
          : sshProfileConnectivityKey(nextProfile);
      final cubit = homeConnectionCubit;
      if (cubit != null && !cubit.isClosed) {
        cubit.rebind(
          profileId: nextSshProfileId,
          host: nextProfile?.host,
          port: nextProfile?.port,
        );
        if (nextSshProfileId == null) {
          // setHomeTarget already resolved and published the new non-SSH plane;
          // seed connected without replaying hot recovery.
          cubit.markInitial(
            HomeConnectResult.connected(runtimeContextRegistry.home()),
          );
        } else {
          // One bounded attempt against the replacement target: this is what
          // lets the gate leave the connection page once the new home connects.
          unawaited(cubit.retryNow());
        }
      }
      await applyHomeEventTransport(restart: true);
    }

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
      switchHome: switchHomeTarget,
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
      sessionAuthority: sessionAuthority,
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
      bootstrapAppData: bootstrapAppData,
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
    await memberPresenceCubit?.close();
    await catalogRuntime?.bus.close();
    await homeConnectionCubit?.close();
    await managedProviderControlPlaneLease.closeIfOwned();
    rethrow;
  }
}

ConnectRelayRegistration _relayRegistrationFor(Uri uri) {
  return ConnectRelayRegistration(
    url: uri.toString(),
    endpointHost: uri.host,
    endpointPort: uri.port == 0 ? (uri.scheme == 'wss' ? 443 : 80) : uri.port,
  );
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
