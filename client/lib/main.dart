import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_shell.dart';
import 'app/teampilot_widgets_flutter_binding.dart';
import 'app/ui_zoom_baseline.dart';
import 'app/home_index_prefetch.dart';
import 'cubits/app_bootstrap_cubit.dart';
import 'cubits/app_update_cubit.dart';
import 'cubits/board_cubit.dart';
import 'cubits/automation_cubit.dart';
import 'cubits/ssh_connection_cubit.dart';
import 'cubits/termux_cubit.dart';
import 'cubits/chat_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/mailbox_cubit.dart';
import 'cubits/notification_cubit.dart';
import 'cubits/progress_activity_cubit.dart';
import 'cubits/ai_history_cubit.dart';
import 'cubits/shortcut_cubit.dart';
import 'l10n/l10n_extensions.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/launch_profile_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/workspace_project_config_repository.dart';
import 'repositories/ssh_credential_store.dart';
import 'repositories/ssh_known_host_repository.dart';
import 'repositories/ssh_profile_repository.dart';
import 'router/app_router.dart';
import 'services/cli/registry/cli_tool_registry_scope.dart';
import 'services/commands/command_bus.dart';
import 'services/commands/key_chord.dart';
import 'services/commands/run_command_registrar.dart';
import 'services/commands/workspace_search_command_registrar.dart';
import 'services/commands/shortcut_context.dart';
import 'services/commands/shortcut_dispatcher.dart';
import 'services/commands/shortcut_dispatcher_handle.dart';
import 'services/commands/shortcut_focus.dart';
import 'services/expert_hub/expert_capability_resolver.dart';
import 'services/home_workspace/home_workspace_ui_cache.dart';
import 'pages/home_workspace/workspace_chrome_commands.dart';
import 'services/storage/app_storage.dart';
import 'services/perf/live_perf_driver.dart';
import 'services/app/boot_splash.dart';
import 'services/app/desktop_text_input_probe_bypass.dart';
import 'services/app/platform_utils.dart';
import 'services/app/windows_keyboard_workaround.dart';
import 'services/app/connection_mode_service.dart';
import 'services/storage/home_storage_invalidator.dart';
import 'services/storage/home_target_controller.dart';
import 'services/storage/workspace_directory_picker.dart';
import 'services/app/desktop_window_actions.dart';
import 'services/ssh/ssh_client_factory.dart';
import 'services/ssh/ssh_profile_connection_coordinator.dart';
import 'services/terminal/terminal_transport_factory.dart';
import 'services/file_tree/workspace_file_tree_store.dart';
import 'services/floating_workspace/floating_maximize_insets.dart';
import 'services/floating_workspace/floating_surface_registry.dart';
import 'services/git/git_repo_store.dart';
import 'services/workspace/workspace_tools_scope_registry.dart';
import 'services/workspace/workspace_run_registry.dart';
import 'services/workspace/workspace_worktree_registry.dart';
import 'services/terminal/workspace_shell_connector.dart';
import 'services/terminal/workspace_terminal_registry.dart';
import 'services/terminal/workspace_terminal_run_service.dart';
import 'services/notification/desktop_system_notifier.dart';
import 'services/notification/notification_recorder.dart';
import 'services/notification/session_idle_notification_tap.dart';
import 'widgets/notification/session_idle_notification_listener.dart';
import 'widgets/ssh/home_ssh_profile_binder.dart';
import 'widgets/ssh/ssh_connection_binder.dart';
import 'widgets/termux/termux_work_ops_message_binder.dart';
import 'repositories/layout_repository.dart';
import 'theme/app_font_prepare.dart';
import 'theme/app_font_resolver.dart';
import 'theme/installed_font_enumerator.dart';
import 'theme/app_theme.dart';
import 'theme/team_pilot_toast_config.dart';
import 'theme/workspace_surface_layers.dart';
import 'theme/app_typography_scale.dart';
import 'pages/system/error_page.dart';
import 'services/automation/automation_scheduler.dart';
import 'utils/logging/logger.dart';
import 'widgets/app_text_scale_boundary.dart';
import 'widgets/app_update_available_dialog.dart';
import 'widgets/ui_zoom.dart';

/// Live [ShortcutContext] used by [ShortcutDispatcherHost].
///
/// `inCompose` / `inTerminal` / `inTextInput` are derived by walking up
/// from [FocusManager.instance.primaryFocus]'s element to the nearest
/// [ShortcutFocus] ancestor (see `ShortcutFocus.maybeOf`) — compose fields
/// wrap themselves in `ShortcutFocus(kind: ShortcutFocusKind.compose, ...)`
/// and agent / workspace-shell terminal views wrap themselves in
/// `ShortcutFocus(kind: ShortcutFocusKind.terminal, ...)` on build, so this
/// needs no static registry. `hasWorkspace` and `hasSessionTab` are cheap
/// to derive correctly today, so they are. `hasOpenWorkspaceTabs` reads
/// [WorkspaceChromeCommands.openTabCount], which `HomeShell` keeps in sync
/// with its title-bar tabs (`0` whenever no `HomeShell` is mounted).
ShortcutContext _liveShortcutContext(
  ChatCubit chatCubit,
  WorkspaceChromeCommands workspaceChromeCommands,
) {
  final location = appRouter.routerDelegate.currentConfiguration.uri
      .toString();
  final focusKind = _primaryShortcutFocusKind();
  return ShortcutContext(
    inTerminal: focusKind == ShortcutFocusKind.terminal,
    inCompose: focusKind == ShortcutFocusKind.compose,
    inTextInput:
        focusKind == ShortcutFocusKind.compose ||
        focusKind == ShortcutFocusKind.text,
    hasWorkspace: location.contains('/home-v2/workspace/'),
    hasOpenWorkspaceTabs: workspaceChromeCommands.openTabCount >= 1,
    hasSessionTab: chatCubit.state.activeSessionId != null,
  );
}

/// Returns the [ShortcutFocusKind] of the nearest [ShortcutFocus] ancestor
/// of the primary focus's element, or `null` if there is none (e.g. no
/// focused widget, or the focused widget sits outside any `ShortcutFocus`).
ShortcutFocusKind? _primaryShortcutFocusKind() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return null;
  return ShortcutFocus.maybeOf(focusContext)?.kind;
}

/// Installs the root [ShortcutDispatcher]: attaches a [HardwareKeyboard]
/// handler on mount and detaches it on dispose. Must sit under the
/// [CommandBus] / [ShortcutCubit] / [ChatCubit] providers so it can read them
/// once in [initState] — matching + dispatch itself needs no `BuildContext`.
class ShortcutDispatcherHost extends StatefulWidget {
  const ShortcutDispatcherHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShortcutDispatcherHost> createState() =>
      _ShortcutDispatcherHostState();
}

class _ShortcutDispatcherHostState extends State<ShortcutDispatcherHost> {
  ShortcutDispatcher? _dispatcher;

  @override
  void initState() {
    super.initState();
    final shortcutCubit = context.read<ShortcutCubit>();
    final chatCubit = context.read<ChatCubit>();
    final workspaceChromeCommands = context.read<WorkspaceChromeCommands>();
    final dispatcher = ShortcutDispatcher(
      bus: context.read<CommandBus>(),
      effectiveChords: (commandId) =>
          shortcutCubit.effective[commandId] ?? const [],
      context: () => _liveShortcutContext(chatCubit, workspaceChromeCommands),
      isMacOS: defaultIsMacOS,
    );
    dispatcher.attach();
    _dispatcher = dispatcher;
    ShortcutDispatcherHandle.instance = dispatcher;
  }

  @override
  void dispose() {
    if (ShortcutDispatcherHandle.instance == _dispatcher) {
      ShortcutDispatcherHandle.instance = null;
    }
    _dispatcher?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CleanupWindowListener extends WindowListener {
  _CleanupWindowListener(
    this.chatCubit,
    this.automationScheduler,
    this.workspaceTerminalRegistry,
    this.gitRepoStore,
    this.workspaceFileTreeStore,
    this.workspaceWorktreeRegistry,
    this.workspaceToolsScopeRegistry,
    this.workspaceRunRegistry,
  );
  final ChatCubit chatCubit;
  final AutomationScheduler automationScheduler;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final WorkspaceRunRegistry workspaceRunRegistry;

  @override
  void onWindowClose() {
    unawaited(_shutdownAndDestroy());
  }

  Future<void> _shutdownAndDestroy() async {
    try {
      automationScheduler.stop();
      await chatCubit.close();
      workspaceTerminalRegistry.disposeAll();
      gitRepoStore.dispose();
      workspaceFileTreeStore.dispose();
      workspaceWorktreeRegistry.dispose();
      workspaceToolsScopeRegistry.dispose();
      workspaceRunRegistry.dispose();
    } finally {
      await windowManager.destroy();
    }
  }
}

/// [BlocProvider.value] does not call [ChatCubit.close]; dispose here covers
/// hot restart and other cases where the widget tree tears down.
class _AppShutdownScope extends StatefulWidget {
  const _AppShutdownScope({
    required this.chatCubit,
    required this.automationScheduler,
    required this.automationCubit,
    required this.mailboxCubit,
    required this.boardCubit,
    required this.aiHistoryCubit,
    required this.notificationCubit,
    required this.progressActivityCubit,
    required this.sshConnectionCubit,
    required this.termuxCubit,
    required this.workspaceTerminalRegistry,
    required this.gitRepoStore,
    required this.workspaceFileTreeStore,
    required this.workspaceWorktreeRegistry,
    required this.workspaceToolsScopeRegistry,
    required this.workspaceRunRegistry,
    required this.child,
  });

  final ChatCubit chatCubit;
  final AutomationScheduler automationScheduler;
  final AutomationCubit automationCubit;
  final MailboxCubit mailboxCubit;
  final BoardCubit boardCubit;
  final AiHistoryCubit aiHistoryCubit;
  final NotificationCubit notificationCubit;
  final ProgressActivityCubit progressActivityCubit;
  final SshConnectionCubit sshConnectionCubit;
  final TermuxCubit termuxCubit;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final WorkspaceRunRegistry workspaceRunRegistry;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    widget.automationScheduler.stop();
    unawaited(widget.chatCubit.close());
    unawaited(widget.automationCubit.close());
    unawaited(widget.mailboxCubit.close());
    unawaited(widget.boardCubit.close());
    unawaited(widget.aiHistoryCubit.close());
    unawaited(widget.notificationCubit.close());
    unawaited(widget.progressActivityCubit.close());
    unawaited(widget.sshConnectionCubit.close());
    unawaited(widget.termuxCubit.close());
    NotificationRecorder.install(null);
    widget.workspaceTerminalRegistry.disposeAll();
    widget.gitRepoStore.dispose();
    widget.workspaceFileTreeStore.dispose();
    widget.workspaceWorktreeRegistry.dispose();
    widget.workspaceToolsScopeRegistry.dispose();
    widget.workspaceRunRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps [child] with [DragToResizeArea] only when the window is not maximized
/// or in fullscreen, so resize cursors don't appear on window edges that can't
/// be dragged.
/// Triggers the silent startup update check once the UI is mounted, and shows
/// the update dialog when [AppUpdateCubit] raises a one-shot prompt.
class _AppUpdateAutoCheck extends StatefulWidget {
  const _AppUpdateAutoCheck({required this.child});

  final Widget child;

  @override
  State<_AppUpdateAutoCheck> createState() => _AppUpdateAutoCheckState();
}

class _AppUpdateAutoCheckState extends State<_AppUpdateAutoCheck> {
  bool _started = false;

  /// Resolves the shared cubit, or null in harnesses that don't provide it
  /// (e.g. widget tests that pump [TeamPilotApp] in isolation).
  AppUpdateCubit? _cubitOrNull(BuildContext context) {
    try {
      return context.read<AppUpdateCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      // Fire-and-forget: never blocks startup or surfaces errors.
      unawaited(_cubitOrNull(context)?.autoCheckOnStartup());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cubitOrNull(context) == null) return widget.child;
    return BlocListener<AppUpdateCubit, AppUpdateState>(
      listenWhen: (prev, next) =>
          prev.promptRelease != next.promptRelease &&
          next.promptRelease != null,
      listener: (context, state) {
        final release = state.promptRelease;
        if (release == null) return;
        context.read<AppUpdateCubit>().consumePrompt();
        AppUpdateAvailableDialogHelper.show(release);
      },
      child: widget.child,
    );
  }
}

class _DragToResizeWrapper extends StatefulWidget {
  const _DragToResizeWrapper({required this.child});

  final Widget child;

  @override
  State<_DragToResizeWrapper> createState() => _DragToResizeWrapperState();
}

class _DragToResizeWrapperState extends State<_DragToResizeWrapper>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncExpanded();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncExpanded() async {
    final expanded = await isDesktopWindowExpanded();
    if (!mounted) return;
    setState(() => _isMaximized = expanded);
  }

  @override
  void onWindowMaximize() => unawaited(_syncExpanded());

  @override
  void onWindowUnmaximize() => unawaited(_syncExpanded());

  @override
  void onWindowEnterFullScreen() => unawaited(_syncExpanded());

  @override
  void onWindowLeaveFullScreen() => unawaited(_syncExpanded());

  @override
  Widget build(BuildContext context) {
    if (_isMaximized) {
      return widget.child;
    }
    return DragToResizeArea(child: widget.child);
  }
}

/// Builds the engine's text-shaping subsystem before the first frame.
///
/// Desktop default window size (Linux GTK + Windows Win32 + [WindowOptions]).
const kDefaultDesktopWindowSize = Size(1380, 960);

void main() async {
  // Custom binding installs DesktopTextInputProbeBypassMessenger — must run
  // before any other Flutter binding (full restart required, not hot reload).
  final binding = TeampilotWidgetsFlutterBinding.ensureInitialized();
  unawaited(LivePerfDriver.ensureStarted());
  final messenger = ServicesBinding.instance.defaultBinaryMessenger;
  // ignore: avoid_print
  print(
    'Teampilot binding=${binding.runtimeType} '
    'binaryMessenger=${messenger.runtimeType}',
  );
  final expectBypass = shouldInstallDesktopTextInputProbeBypass(
    isWeb: false,
    isAndroid: Platform.isAndroid,
    isIOS: Platform.isIOS,
    isLinux: Platform.isLinux,
    isWindows: Platform.isWindows,
    isMacOS: Platform.isMacOS,
  );
  if (expectBypass && messenger is! DesktopTextInputProbeBypassMessenger) {
    throw StateError(
      'DesktopTextInputProbeBypassMessenger not installed '
      '(got ${messenger.runtimeType}). Stop the app and cold-start; '
      'hot reload/hot restart cannot replace the binding.',
    );
  }
  if (expectBypass) {
    // Prove the wrapper is on the same path EditableText uses (SystemChannels).
    final hitsBefore = DesktopTextInputProbeBypassMessenger.bypassHitCount;
    await SystemChannels.platform.invokeMethod<dynamic>(
      'Clipboard.hasStrings',
      'text/plain',
    );
    final hitsAfter = DesktopTextInputProbeBypassMessenger.bypassHitCount;
    // ignore: avoid_print
    print(
      'Teampilot probe self-check hits=$hitsAfter '
      'misses=${DesktopTextInputProbeBypassMessenger.bypassMissCount} '
      'delta=${hitsAfter - hitsBefore}',
    );
    if (hitsAfter <= hitsBefore) {
      throw StateError(
        'DesktopTextInputProbeBypassMessenger is installed but did not '
        'intercept SystemChannels.platform Clipboard.hasStrings (misses='
        '${DesktopTextInputProbeBypassMessenger.bypassMissCount}).',
      );
    }
  }
  preserveBootSplash(binding);
  installWindowsKeyboardWorkaround();
  await RustLib.init();
  GoogleFonts.config.allowRuntimeFetching = false;

  if (!Platform.isAndroid) {
    await windowManager.ensureInitialized();
    // Cold-start window size. Do not use [getBounds] here — native runners
    // already size the window before Dart runs, so getBounds() masked edits to
    // a Dart-only fallback. When changing height/width, update this constant
    // and linux/runner/my_application.cc + windows/runner/main.cpp to match.
    const initialSize = kDefaultDesktopWindowSize;
    final windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: const Size(800, 500),
      center: false,
      title: 'TeamPilot',
      backgroundColor: const Color(0xFFFFFFFF),
      // Frameless chrome is finalized in completeBootSplashTransition(). Linux
      // and Windows already start without a native caption for overlay splash.
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Linux/Windows paint the splash as an in-window overlay, so the main
      // window stays visible. macOS still hides behind a separate splash window
      // until the reveal.
      if (Platform.isMacOS) {
        await windowManager.setOpacity(0);
      }
      await ensureBootSplashOnTop();
    });
  }

  // Start startup IO up front so font load + text-shaping warm-up below
  // overlap path init instead of stacking onto the first frame.
  final pathsFuture = AppPathsBootstrapper.init();
  final preferencesFuture = SharedPreferences.getInstance();

  // Resolve fonts from layout prefs (defaults to system) before first paint.
  final preferences = await preferencesFuture;
  final layoutPrefs = await LayoutRepository(preferences).load();
  // Enumerate native families first so installed:* prefs skip FontLoader when
  // fontconfig names are available.
  await InstalledFontEnumerator.listFamilies();
  final bootFonts = AppFontResolver.resolve(
    uiFontId: layoutPrefs.uiFontId,
    monoFontId: layoutPrefs.monoFontId,
  );
  await prepareFontsForUse(bootFonts);

  late final String nativeAppDataPath;
  try {
    await pathsFuture;
    nativeAppDataPath = AppPathsBootstrapper.current.basePath;
    await initAppLogging(nativeAppDataPath);
  } on Object catch (error, stackTrace) {
    if (!Platform.isAndroid) {
      await completeBootSplashTransition();
    }
    await showInitErrorApp(error: error, stackTrace: stackTrace);
    return;
  }

  final defaultWorkspaceDirectoryFuture = DefaultWorkspaceDirectory.resolve(
    preferences: preferences,
  );
  final homeIndexPrefetchFuture = prefetchHomeIndexSnapshots(nativeAppDataPath);
  final bootstrapCubit = AppBootstrapCubit();

  if (!Platform.isAndroid) {
    await windowManager.setPreventClose(true);
  }
  await DesktopSystemNotifier.ensureInitialized(
    onNotificationTap: (payload) {
      unawaited(
        handleSessionIdleNotificationTap(
          payload: payload,
          go: appRouter.go,
          markReadMatchingPayload: (location) async {
            final recorder = NotificationRecorder.maybeCurrent;
            if (recorder is NotificationCubit) {
              await recorder.markReadMatchingPayload(location);
            }
          },
          focusWindow: () async {
            if (Platform.isAndroid) return;
            await windowManager.show();
            await windowManager.focus();
          },
        ),
      );
    },
  );

  runApp(
    BlocProvider.value(
      value: bootstrapCubit,
      child: TeamPilotBootstrap(
        preferences: preferences,
        nativeAppDataPath: nativeAppDataPath,
        defaultWorkspaceDirectoryFuture: defaultWorkspaceDirectoryFuture,
        homeIndexPrefetchFuture: homeIndexPrefetchFuture,
        bootstrapCubit: bootstrapCubit,
        childBuilder: (shell) {
          if (!Platform.isAndroid) {
            windowManager.addListener(
              _CleanupWindowListener(
                shell.chatCubit,
                shell.automationScheduler,
                shell.workspaceTerminalRegistry,
                shell.gitRepoStore,
                shell.workspaceFileTreeStore,
                shell.workspaceWorktreeRegistry,
                shell.workspaceToolsScopeRegistry,
                shell.workspaceRunRegistry,
              ),
            );
          }
          return _AppShutdownScope(
            chatCubit: shell.chatCubit,
            automationScheduler: shell.automationScheduler,
            automationCubit: shell.automationCubit,
            mailboxCubit: shell.mailboxCubit,
            boardCubit: shell.boardCubit,
            aiHistoryCubit: shell.aiHistoryCubit,
            notificationCubit: shell.notificationCubit,
            progressActivityCubit: shell.progressActivityCubit,
            sshConnectionCubit: shell.sshConnectionCubit,
            termuxCubit: shell.termuxCubit,
            workspaceTerminalRegistry: shell.workspaceTerminalRegistry,
            gitRepoStore: shell.gitRepoStore,
            workspaceFileTreeStore: shell.workspaceFileTreeStore,
            workspaceWorktreeRegistry: shell.workspaceWorktreeRegistry,
            workspaceToolsScopeRegistry: shell.workspaceToolsScopeRegistry,
            workspaceRunRegistry: shell.workspaceRunRegistry,
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<SharedPreferences>.value(value: preferences),
                RepositoryProvider<AppSettingsRepository>.value(
                  value: shell.appSettings,
                ),
                RepositoryProvider<HomeWorkspaceUiCache>.value(
                  value: shell.homeWorkspaceUiCache,
                ),
                RepositoryProvider<SessionRepository>.value(
                  value: shell.sessionRepo,
                ),
                RepositoryProvider<WorkspaceProjectConfigRepository>.value(
                  value: shell.workspaceProjectConfigRepository,
                ),
                RepositoryProvider<LaunchProfileRepository>.value(
                  value: shell.identityRepository,
                ),
                RepositoryProvider<SshProfileRepository>.value(
                  value: shell.sshProfileRepo,
                ),
                RepositoryProvider<SshCredentialStore>.value(
                  value: shell.sshCredentialStore,
                ),
                RepositoryProvider<SshKnownHostRepository>.value(
                  value: shell.sshKnownHostRepo,
                ),
                RepositoryProvider<TerminalTransportFactory>.value(
                  value: shell.transportFactory,
                ),
                RepositoryProvider<SshClientFactory>.value(
                  value: shell.sshClientFactory,
                ),
                RepositoryProvider<SshProfileConnectionCoordinator>.value(
                  value: shell.sshProfileConnectionCoordinator,
                ),
                RepositoryProvider<ConnectionModeService>.value(
                  value: shell.connectionModeService,
                ),
                RepositoryProvider<HomeTargetController>.value(
                  value: shell.homeTargetController,
                ),
                RepositoryProvider<HomeStorageInvalidator>.value(
                  value: shell.homeStorageInvalidator,
                ),
                RepositoryProvider<WorkspaceDirectoryPicker>.value(
                  value: shell.directoryPicker,
                ),
                RepositoryProvider<WorkspaceTerminalRegistry>.value(
                  value: shell.workspaceTerminalRegistry,
                ),
                RepositoryProvider<WorkspaceShellConnector>.value(
                  value: shell.workspaceShellConnector,
                ),
                RepositoryProvider<WorkspaceTerminalRunService>.value(
                  value: shell.workspaceTerminalRunService,
                ),
                RepositoryProvider<GitRepoStore>.value(
                  value: shell.gitRepoStore,
                ),
                RepositoryProvider<WorkspaceFileTreeStore>.value(
                  value: shell.workspaceFileTreeStore,
                ),
                RepositoryProvider<WorkspaceWorktreeRegistry>.value(
                  value: shell.workspaceWorktreeRegistry,
                ),
                RepositoryProvider<WorkspaceToolsScopeRegistry>.value(
                  value: shell.workspaceToolsScopeRegistry,
                ),
                RepositoryProvider<WorkspaceRunRegistry>.value(
                  value: shell.workspaceRunRegistry,
                ),
                RepositoryProvider<ExpertCapabilityResolver>.value(
                  value: shell.expertCapabilityResolver,
                ),
                RepositoryProvider<CommandBus>.value(value: shell.commandBus),
                RepositoryProvider<WorkspaceChromeCommands>.value(
                  value: shell.workspaceChromeCommands,
                ),
                RepositoryProvider<RunCommandHost>.value(
                  value: shell.runCommandHost,
                ),
                RepositoryProvider<WorkspaceSearchHost>.value(
                  value: shell.workspaceSearchHost,
                ),
                RepositoryProvider<UiZoomBaseline>.value(
                  value: shell.uiZoomBaseline,
                ),
                RepositoryProvider<FloatingSurfaceRegistry>.value(
                  value: shell.floatingSurfaceRegistry,
                ),
                RepositoryProvider<FloatingMaximizeInsets>.value(
                  value: shell.floatingMaximizeInsets,
                ),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: shell.teamCubit),
                  BlocProvider.value(value: shell.chatCubit),
                  BlocProvider.value(value: shell.memberPresenceCubit),
                  BlocProvider.value(value: shell.agentAttentionCubit),
                  BlocProvider.value(value: shell.mailboxCubit),
                  BlocProvider.value(value: shell.boardCubit),
                  BlocProvider.value(value: shell.aiHistoryCubit),
                  BlocProvider.value(value: shell.notificationCubit),
                  BlocProvider.value(value: shell.progressActivityCubit),
                  BlocProvider.value(value: shell.editorCubit),
                  BlocProvider.value(value: shell.workbenchCubit),
                  BlocProvider.value(value: shell.floatingWorkspaceCubit),
                  RepositoryProvider.value(value: shell.workbenchEditorOpener),
                  RepositoryProvider.value(value: shell.workbenchShellLauncher),
                  BlocProvider.value(value: shell.configCubit),
                  BlocProvider.value(value: shell.appProviderCubit),
                  BlocProvider.value(value: shell.llmConfigCubit),
                  BlocProvider.value(value: shell.layoutCubit),
                  BlocProvider.value(value: shell.workspaceToolsCubit),
                  BlocProvider.value(value: shell.sessionPreferencesCubit),
                  BlocProvider.value(value: shell.pluginCubit),
                  BlocProvider.value(value: shell.skillCubit),
                  BlocProvider.value(value: shell.automationCubit),
                  BlocProvider.value(value: shell.mcpCubit),
                  BlocProvider.value(value: shell.teamHubCubit),
                  BlocProvider.value(value: shell.expertHubCubit),
                  BlocProvider.value(value: shell.extensionCubit),
                  BlocProvider.value(value: shell.appUpdateCubit),
                  BlocProvider.value(value: shell.sshProfileCubit),
                  BlocProvider.value(value: shell.sshConnectionCubit),
                  BlocProvider.value(value: shell.termuxCubit),
                  BlocProvider.value(value: shell.githubAccountCubit),
                  RepositoryProvider.value(
                    value: shell.githubCredentialsStore,
                  ),
                  BlocProvider.value(value: shell.cliPresetsCubit),
                  BlocProvider.value(value: shell.aiFeatureSettingsCubit),
                  BlocProvider.value(value: shell.shortcutCubit),
                ],
                child: CliToolRegistryScope(
                  registry: shell.cliToolRegistry,
                  child: SshConnectionBinder(
                    child: HomeSshProfileBinder(
                      child: const SessionIdleNotificationListener(
                        child: ShortcutDispatcherHost(child: TeamPilotApp()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class TeamPilotApp extends StatelessWidget {
  const TeamPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      LayoutCubit,
      LayoutState,
      ({
        String themeMode,
        String colorPreset,
        String typographyScale,
        double typographyCustomMultiplier,
        String uiFontId,
        String monoFontId,
      })
    >(
      selector: (state) {
        final prefs = state.preferences;
        var themeMode = prefs.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode: themeMode,
          colorPreset: normalizeThemeColorPreset(prefs.themeColorPreset),
          typographyScale: normalizeTypographyScale(prefs.typographyScale),
          typographyCustomMultiplier: prefs.typographyScaleCustomMultiplier,
          uiFontId: prefs.uiFontId,
          monoFontId: prefs.monoFontId,
        );
      },
      builder: (context, themeBundle) {
        return BlocSelector<LayoutCubit, LayoutState, String>(
          selector: (state) => state.preferences.locale,
          builder: (context, savedLocale) {
            return _TeamPilotMaterialApp(
              themeMode: themeBundle.themeMode,
              colorPreset: themeBundle.colorPreset,
              typographyScaleId: themeBundle.typographyScale,
              typographyCustomMultiplier:
                  themeBundle.typographyCustomMultiplier,
              uiFontId: themeBundle.uiFontId,
              monoFontId: themeBundle.monoFontId,
              savedLocale: savedLocale,
            );
          },
        );
      },
    );
  }
}

class _TeamPilotMaterialApp extends StatefulWidget {
  const _TeamPilotMaterialApp({
    required this.themeMode,
    required this.colorPreset,
    required this.typographyScaleId,
    required this.typographyCustomMultiplier,
    required this.uiFontId,
    required this.monoFontId,
    required this.savedLocale,
  });

  final String themeMode;
  final String colorPreset;
  final String typographyScaleId;
  final double typographyCustomMultiplier;
  final String uiFontId;
  final String monoFontId;
  final String savedLocale;

  @override
  State<_TeamPilotMaterialApp> createState() => _TeamPilotMaterialAppState();
}

class _TeamPilotMaterialAppState extends State<_TeamPilotMaterialApp> {
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;
  String? _cachedColorPreset;
  String? _cachedTypographyScaleId;
  double? _cachedTypographyCustomMultiplier;
  double? _cachedEffectiveTextMult;
  double? _cachedIconMultiplier;
  String? _cachedUiFontId;
  String? _cachedMonoFontId;

  /// Session-pinned fonts. Pref changes save immediately but apply on next
  /// cold start — mid-session [ThemeData] font swaps force a multi-second
  /// full-tree layout.
  late final String _sessionUiFontId = widget.uiFontId;
  late final String _sessionMonoFontId = widget.monoFontId;

  ({ThemeData light, ThemeData dark}) _resolveThemes() {
    // Text size: scales fonts via the theme. `standard` == the per-system
    // baseline (OS text-scaling × display scaling); compact/comfortable/
    // custom are relative to it. Read system metrics from the implicit view
    // — there is no MediaQuery ancestor above MaterialApp here.
    final systemView = WidgetsBinding.instance.platformDispatcher.implicitView;
    final systemMq = systemView == null
        ? const MediaQueryData()
        : MediaQueryData.fromView(systemView);
    final textBaseline = autoTextScaleForSystem(
      systemMq.textScaler.scale(1.0),
      systemMq.devicePixelRatio,
      compensateDisplayScaling: usesDesktopDisplayScalingCompensation,
    );
    final effectiveTextMult = resolveRelativeScale(
      scaleId: widget.typographyScaleId,
      customMultiplier: widget.typographyCustomMultiplier,
      baseline: textBaseline,
    );
    final iconMultiplier = TpIconSizes.resolveIconMultiplier(
      effectiveTextMultiplier: effectiveTextMult,
      textBaseline: textBaseline,
    );
    _cachedIconMultiplier = iconMultiplier;
    if (_lightTheme != null &&
        _darkTheme != null &&
        _cachedColorPreset == widget.colorPreset &&
        _cachedTypographyScaleId == widget.typographyScaleId &&
        _cachedTypographyCustomMultiplier ==
            widget.typographyCustomMultiplier &&
        _cachedEffectiveTextMult == effectiveTextMult &&
        _cachedUiFontId == _sessionUiFontId &&
        _cachedMonoFontId == _sessionMonoFontId) {
      return (light: _lightTheme!, dark: _darkTheme!);
    }
    final fonts = AppFontResolver.resolve(
      uiFontId: _sessionUiFontId,
      monoFontId: _sessionMonoFontId,
    );
    final textScale = AppTypographyScale(multiplier: effectiveTextMult);
    final iconScale = AppTypographyScale(multiplier: iconMultiplier);
    _cachedColorPreset = widget.colorPreset;
    _cachedTypographyScaleId = widget.typographyScaleId;
    _cachedTypographyCustomMultiplier = widget.typographyCustomMultiplier;
    _cachedEffectiveTextMult = effectiveTextMult;
    _cachedUiFontId = _sessionUiFontId;
    _cachedMonoFontId = _sessionMonoFontId;
    _lightTheme = buildLightTheme(
      widget.colorPreset,
      textScale,
      iconScale,
      fonts,
    );
    _darkTheme = buildDarkTheme(
      widget.colorPreset,
      textScale,
      iconScale,
      fonts,
    );
    return (light: _lightTheme!, dark: _darkTheme!);
  }

  ThemeMode _themeModeFromPrefs(String mode) => switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    final themes = _resolveThemes();

    return TpToastWrapper(
      config: buildTeamPilotToastConfig(),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'TeamPilot',
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: _themeModeFromPrefs(widget.themeMode),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: widget.savedLocale.isNotEmpty
            ? Locale(widget.savedLocale)
            : null,
        builder: (context, child) {
          return BlocSelector<
            LayoutCubit,
            LayoutState,
            ({String uiZoomScale, double uiZoomCustomMultiplier})
          >(
            selector: (state) => (
              uiZoomScale: normalizeTypographyScale(
                state.preferences.uiZoomScale,
              ),
              uiZoomCustomMultiplier: state.preferences.uiZoomCustomMultiplier,
            ),
            builder: (context, zoomBundle) {
              // Interface zoom: `standard` == the per-display baseline
              // (desktop: 1/dpr; mobile: 1.0 — see
              // [usesDesktopDisplayScalingCompensation]); presets are relative.
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final baseline = autoUiZoomForDevicePixelRatio(
                dpr,
                compensateDisplayScaling:
                    usesDesktopDisplayScalingCompensation,
              );
              context.read<UiZoomBaseline>().value = baseline;
              final effectiveZoom = clampUiZoom(
                resolveRelativeScale(
                  scaleId: zoomBundle.uiZoomScale,
                  customMultiplier: zoomBundle.uiZoomCustomMultiplier,
                  baseline: baseline,
                ),
              );
              Widget content = AppTextScaleBoundary(
                child: TermuxWorkOpsMessageBinder(
                  child: _AppUpdateAutoCheck(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
              // Single global zoom: scales fonts + icons + padding + every
              // control as one. Must sit INSIDE DragToResizeArea so the window
              // resize handles stay mapped to the real (unscaled) window edges.
              content = UiZoom(scale: effectiveZoom, child: content);
              // The native title bar is hidden (TitleBarStyle.hidden), which on
              // Linux/GTK also strips the resize-border grips. DragToResizeArea
              // re-adds invisible resize handles on all edges/corners so the
              // frameless window can still be resized from its borders.
              if (!Platform.isAndroid) {
                content = _DragToResizeWrapper(child: content);
              }
              // TpTheme outside UiZoom. Spacing stays at design baseline;
              // controlScale tracks text size; iconScale uses damped policy.
              final scheme = Theme.of(context).colorScheme;
              return TpTheme(
                data: TpThemeData.fromColorScheme(
                  scheme,
                  scale: 1.0,
                  iconScale: _cachedIconMultiplier ?? 1.0,
                  controlScale: _cachedEffectiveTextMult ?? 1.0,
                  toast: TpToastTheme.fromColorScheme(
                    scheme,
                    backgroundColor: scheme.workspaceCard,
                  ),
                ),
                child: content,
              );
            },
          );
        },
        localeResolutionCallback: (locale, supportedLocales) {
          if (widget.savedLocale.isNotEmpty) return Locale(widget.savedLocale);
          for (final supportedLocale in supportedLocales) {
            if (supportedLocale.languageCode == locale?.languageCode) {
              return supportedLocale;
            }
          }
          return const Locale('en');
        },
        routerConfig: appRouter,
      ),
    );
  }
}
