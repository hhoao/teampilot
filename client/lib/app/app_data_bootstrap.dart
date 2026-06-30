import 'dart:async';

import '../cubits/app_provider_cubit.dart';
import '../cubits/ai_feature_settings_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/cli_presets_cubit.dart';
import '../cubits/extension_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../models/layout_preferences.dart';
import '../models/workspace.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/session_repository.dart';
import '../router/app_router.dart';
import '../services/app/ui_interactive_warmup.dart';
import '../services/workspace/workspace_icon_warmup.dart';
import '../services/home_workspace/home_workspace_ui_cache.dart';
import '../services/storage/launch_profile_provisioner.dart';
import '../utils/yield_ui_frame.dart';
import '../services/team/default_workspace_service.dart';
import '../utils/logger.dart';

typedef BootLog = void Function(String message);

/// Orchestrates app-data loading: workspace index first, everything else warm.
abstract final class AppDataBootstrap {
  AppDataBootstrap._();

  /// Hydrates launch profiles + workspace index before the home shell is shown.
  static Future<void> hydrateNativeHomeIndex({
    required BootLog boot,
    required LaunchProfileCubit teamCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
  }) async {
    await Future.wait([
      _timed(
        boot,
        'launchProfiles',
        () => teamCubit.load(bootSilent: true),
      ),
      _timed(
        boot,
        'loadWorkspaceIndex',
        () => chatCubit.loadWorkspaceIndex(sessionRepo),
      ),
    ]);
    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );

    boot(
      'hydrateNativeHomeIndex index ready '
      'workspaces=${chatCubit.state.workspaces.length} '
      'identities=${teamCubit.state.identities.length}',
    );

    await _seedDefaultWorkspace(
      boot: boot,
      teamCubit: teamCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
    );
  }

  static Future<void> _seedDefaultWorkspace({
    required BootLog boot,
    required LaunchProfileCubit teamCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
  }) async {
    await _ensureDefaultWorkspace(
      boot,
      teamCubit: teamCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
    );
    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );
    boot(
      'defaultWorkspaceSeed complete '
      'workspaces=${chatCubit.state.workspaces.length}',
    );
  }

  static Future<void> _reapplyWorkspaceEntry({
    required BootLog boot,
    required LayoutCubit layoutCubit,
    required ChatCubit chatCubit,
  }) async {
    final preferences = layoutCubit.state.preferences;
    reapplyWorkspaceEntryFromPreferences(
      preferences,
      knownWorkspaceIds: {
        for (final workspace in chatCubit.state.workspaces) workspace.workspaceId,
      },
    );

    if (preferences.workspaceEntryMode == WorkspaceEntryMode.lastWorkspace) {
      final workspaceId = preferences.lastOpenedWorkspaceId.trim();
      if (workspaceId.isNotEmpty &&
          chatCubit.state.workspaces.any((w) => w.workspaceId == workspaceId)) {
        await _timed(
          boot,
          'prefetchSessionsForEntryWorkspace',
          () => chatCubit.ensureSessionsForWorkspace(workspaceId),
        );
      }
    }
  }

  /// SSH home reinstall + parallel team/workspace index — blocks until the home
  /// shell can list workspaces and identities. Sessions load on demand.
  static Future<void> bootstrapHomeIndex({
    required BootLog boot,
    required SshProfileCubit sshProfileCubit,
    required LaunchProfileCubit teamCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
    required bool isSshMode,
    required String? homeSshProfileId,
    required bool Function(String id) sshProfileExists,
    required Future<void> Function() reinstallStorageContext,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('bootstrapHomeIndex start');

    final sshLoad = sshProfileCubit.load(notifyActiveProfileChanged: false);

    if (isSshMode) {
      await sshLoad;
      boot('bootstrapHomeIndex ssh profiles loaded');
      if (homeSshProfileId != null && sshProfileExists(homeSshProfileId)) {
        boot('bootstrapHomeIndex reinstalling home storage context (ssh)');
        await reinstallStorageContext();
        boot('bootstrapHomeIndex home storage context reinstalled');
      }
      await Future.wait([
        _timed(
          boot,
          'launchProfiles',
          () => teamCubit.load(bootSilent: true),
        ),
        _timed(
          boot,
          'loadWorkspaceIndex',
          () => chatCubit.loadWorkspaceIndex(sessionRepo),
        ),
      ]);
    } else {
      await Future.wait([
        _timed(
          boot,
          'launchProfiles',
          () => teamCubit.load(bootSilent: true),
        ),
        _timed(
          boot,
          'loadWorkspaceIndex',
          () => chatCubit.loadWorkspaceIndex(sessionRepo),
        ),
      ]);
      unawaited(_timed(boot, 'sshProfiles', () => sshLoad));
    }

    await _reapplyWorkspaceEntry(
      boot: boot,
      layoutCubit: layoutCubit,
      chatCubit: chatCubit,
    );

    await _seedDefaultWorkspace(
      boot: boot,
      teamCubit: teamCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
    );

    boot(
      'bootstrapHomeIndex complete +${phaseSw.elapsedMilliseconds}ms '
      'workspaces=${chatCubit.state.workspaces.length} '
      'sessions=${chatCubit.state.sessions.length}',
    );
  }

  /// Plugins, skills, extensions, default-workspace seed, team resource sync.
  static Future<void> warmAuxiliaryData({
    required BootLog boot,
    required LlmConfigCubit llmConfigCubit,
    required AppProviderCubit appProviderCubit,
    required LaunchProfileCubit teamCubit,
    required PluginCubit pluginCubit,
    required SkillCubit skillCubit,
    required McpCubit mcpCubit,
    required ExtensionCubit extensionCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('warmAuxiliaryData start');

    await _timed(boot, 'llmConfig', llmConfigCubit.load);
    await yieldUiFrame();
    await _timed(
      boot,
      'appProvider',
      () => appProviderCubit.load(reconcileCredentials: false),
    );
    await yieldUiFrame();
    await _timed(boot, 'plugins', pluginCubit.load);
    await yieldUiFrame();
    await _timed(boot, 'skills', skillCubit.loadAll);
    await yieldUiFrame();
    await _timed(boot, 'mcp', () => mcpCubit.loadAll());
    await yieldUiFrame();

    await _timed(boot, 'extensions', extensionCubit.loadForBootstrap);
    await yieldUiFrame();

    await _timed(
      boot,
      'appProviderCredentials',
      () => appProviderCubit.reconcileCredentials(),
    );
    await yieldUiFrame();
    await _timed(
      boot,
      'syncTeamPlugins',
      () => teamCubit.syncSelectedTeamPlugins(
        installed: pluginCubit.state.installed,
      ),
    );
    await yieldUiFrame();
    await _timed(
      boot,
      'syncTeamMcp',
      () => teamCubit.syncSelectedTeamMcp(installed: mcpCubit.state.servers),
    );

    boot(
      'warmAuxiliaryData complete +${phaseSw.elapsedMilliseconds}ms',
    );
    await yieldUiFrame();
  }

  /// Fonts, glyph cache, and terminal engine — time-sliced for spinner fluidity.
  static Future<void> warmUiInteractive({
    required BootLog boot,
    required LayoutPreferences layoutPreferences,
  }) async {
    await _timed(
      boot,
      'uiInteractive',
      () => UiInteractiveWarmup.run(layoutPreferences: layoutPreferences),
    );
    await yieldUiFrame();
  }

  /// SSH profiles, CLI presets, feature flags, and onboarding gate — must
  /// finish before the router mounts so no second spinner appears on entry.
  static Future<bool> prepareInteractiveShell({
    required BootLog boot,
    required AppSettingsRepository appSettings,
    required SshProfileCubit sshProfileCubit,
    required CliPresetsCubit cliPresetsCubit,
    required AiFeatureSettingsCubit aiFeatureSettingsCubit,
    required HomeWorkspaceUiCache homeWorkspaceUiCache,
    required List<Workspace> workspaces,
  }) async {
    final phaseSw = Stopwatch()..start();
    boot('prepareInteractiveShell start');

    await _timed(
      boot,
      'sshProfiles',
      () => sshProfileCubit.load(notifyActiveProfileChanged: false),
    );
    await yieldUiFrame();
    await _timed(boot, 'cliPresets', cliPresetsCubit.load);
    await yieldUiFrame();
    await _timed(boot, 'aiFeatureSettings', aiFeatureSettingsCubit.load);
    await yieldUiFrame();
    await _timed(boot, 'homeWorkspaceUi', homeWorkspaceUiCache.warm);
    await yieldUiFrame();
    await _timed(
      boot,
      'workspaceIcons',
      () => WorkspaceIconWarmup.warm(workspaces),
    );

    await yieldUiFrame();

    final showOnboarding = !(await appSettings.loadHasCompletedOnboarding());
    boot(
      'prepareInteractiveShell complete +${phaseSw.elapsedMilliseconds}ms '
      'showOnboarding=$showOnboarding',
    );
    return showOnboarding;
  }

  /// Full reload after home-target or SSH-profile switch.
  static Future<void> reloadAll({
    required BootLog boot,
    required SshProfileCubit sshProfileCubit,
    required LlmConfigCubit llmConfigCubit,
    required AppProviderCubit appProviderCubit,
    required LaunchProfileCubit teamCubit,
    required PluginCubit pluginCubit,
    required SkillCubit skillCubit,
    required McpCubit mcpCubit,
    required ExtensionCubit extensionCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
    required LayoutCubit layoutCubit,
    required bool isSshMode,
    required String? homeSshProfileId,
    required bool Function(String id) sshProfileExists,
    required Future<void> Function() reinstallStorageContext,
  }) async {
    await bootstrapHomeIndex(
      boot: boot,
      sshProfileCubit: sshProfileCubit,
      teamCubit: teamCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      layoutCubit: layoutCubit,
      isSshMode: isSshMode,
      homeSshProfileId: homeSshProfileId,
      sshProfileExists: sshProfileExists,
      reinstallStorageContext: reinstallStorageContext,
    );
    await warmAuxiliaryData(
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
    await _timed(
      boot,
      'loadWorkspaceData',
      () => chatCubit.loadWorkspaceData(sessionRepo),
    );
  }

  static Future<T> _timed<T>(
    BootLog boot,
    String name,
    Future<T> Function() fn,
  ) async {
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      appLogger.i('[boot] $name +${sw.elapsedMilliseconds}ms');
    }
  }

  static Future<void> _ensureDefaultWorkspace(
    BootLog boot, {
    required LaunchProfileCubit teamCubit,
    required ChatCubit chatCubit,
    required SessionRepository sessionRepo,
  }) async {
    final defaultTeam = teamCubit.state.teams
        .where((t) => t.id == LaunchProfileProvisioner.defaultTeamId)
        .firstOrNull;
    if (defaultTeam == null) return;

    final mutated = await _timed(
      boot,
      'defaultWorkspaceEnsure',
      () => DefaultWorkspaceService.ensureDefault(
        sessionRepo,
        defaultTeam: defaultTeam,
        knownWorkspaces: chatCubit.state.workspaces,
      ),
    );
    if (mutated) {
      await _timed(
        boot,
        'loadWorkspaceIndexAfterSeed',
        () => chatCubit.loadWorkspaceIndex(sessionRepo),
      );
    }
  }
}
