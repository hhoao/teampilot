import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_shell.dart';
import 'app/home_index_prefetch.dart';
import 'cubits/app_bootstrap_cubit.dart';
import 'cubits/app_update_cubit.dart';
import 'cubits/board_cubit.dart';
import 'cubits/chat_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/mailbox_cubit.dart';
import 'cubits/notification_cubit.dart';
import 'l10n/l10n_extensions.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/launch_profile_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/ssh_credential_store.dart';
import 'repositories/ssh_known_host_repository.dart';
import 'repositories/ssh_profile_repository.dart';
import 'router/app_router.dart';
import 'services/cli/registry/cli_tool_registry_scope.dart';
import 'services/home_workspace/home_workspace_ui_cache.dart';
import 'services/storage/app_storage.dart';
import 'services/app/boot_splash.dart';
import 'services/app/connection_mode_service.dart';
import 'services/storage/home_target_controller.dart';
import 'services/storage/workspace_directory_picker.dart';
import 'services/app/desktop_window_actions.dart';
import 'services/ssh/ssh_client_factory.dart';
import 'services/terminal/terminal_transport_factory.dart';
import 'services/file_tree/workspace_file_tree_store.dart';
import 'services/git/git_repo_store.dart';
import 'services/workspace/workspace_tools_scope_registry.dart';
import 'services/workspace/workspace_worktree_registry.dart';
import 'services/terminal/workspace_shell_connector.dart';
import 'services/terminal/workspace_terminal_registry.dart';
import 'services/notification/notification_recorder.dart';
import 'services/terminal/terminal_fonts.dart';
import 'theme/app_icon_sizes.dart';
import 'theme/app_toast_theme.dart';
import 'theme/app_theme.dart';
import 'theme/app_typography_scale.dart';
import 'pages/system/error_page.dart';
import 'services/app/windows_keyboard_workaround.dart';
import 'utils/logger.dart';
import 'widgets/app_text_scale_boundary.dart';
import 'widgets/app_update_available_dialog.dart';
import 'widgets/ui_warmup.dart';
import 'widgets/ui_zoom.dart';

class _CleanupWindowListener extends WindowListener {
  _CleanupWindowListener(
    this.chatCubit,
    this.workspaceTerminalRegistry,
    this.gitRepoStore,
    this.workspaceFileTreeStore,
    this.workspaceWorktreeRegistry,
    this.workspaceToolsScopeRegistry,
  );
  final ChatCubit chatCubit;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;

  @override
  void onWindowClose() {
    unawaited(_shutdownAndDestroy());
  }

  Future<void> _shutdownAndDestroy() async {
    try {
      await chatCubit.close();
      workspaceTerminalRegistry.disposeAll();
      gitRepoStore.dispose();
      workspaceFileTreeStore.dispose();
      workspaceWorktreeRegistry.dispose();
      workspaceToolsScopeRegistry.dispose();
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
    required this.mailboxCubit,
    required this.boardCubit,
    required this.notificationCubit,
    required this.workspaceTerminalRegistry,
    required this.gitRepoStore,
    required this.workspaceFileTreeStore,
    required this.workspaceWorktreeRegistry,
    required this.workspaceToolsScopeRegistry,
    required this.child,
  });

  final ChatCubit chatCubit;
  final MailboxCubit mailboxCubit;
  final BoardCubit boardCubit;
  final NotificationCubit notificationCubit;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final GitRepoStore gitRepoStore;
  final WorkspaceFileTreeStore workspaceFileTreeStore;
  final WorkspaceWorktreeRegistry workspaceWorktreeRegistry;
  final WorkspaceToolsScopeRegistry workspaceToolsScopeRegistry;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    unawaited(widget.chatCubit.close());
    unawaited(widget.mailboxCubit.close());
    unawaited(widget.boardCubit.close());
    unawaited(widget.notificationCubit.close());
    NotificationRecorder.install(null);
    widget.workspaceTerminalRegistry.disposeAll();
    widget.gitRepoStore.dispose();
    widget.workspaceFileTreeStore.dispose();
    widget.workspaceWorktreeRegistry.dispose();
    widget.workspaceToolsScopeRegistry.dispose();
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

Future<void> _preloadBundledUiFonts() async {
  try {
    // Only Regular is awaited before first paint (keeps launch fast). The other
    // weights are warmed during the boot gate in UiInteractiveWarmup.
    await GoogleFonts.pendingFonts([GoogleFonts.notoSansSc()]);
  } on Object {
    // Run `dart run tool/sync_bundled_google_fonts.dart` from client/, then rebuild.
  }
}

/// Builds the engine's text-shaping subsystem before the first frame.
///
/// The *first* text layout in a process pays a large one-time cost: Skia/
/// HarfBuzz init, system-font enumeration, and constructing the bundled Noto
/// Sans SC face. Startup traces show this lands inside the first frame's LAYOUT
/// phase — a single offstage `RenderParagraph` took ~1.3s, dominating cold
/// start, while every later paragraph (subsystem now warm) was ~150ms.
///
/// One synchronous shaping pass here moves that cost off the first frame. It is
/// run while startup IO (app paths, prefs) is in flight so part of it overlaps.
/// Loading the bytes (`_preloadBundledUiFonts`) is not enough — the face/shaper
/// is built lazily on first *layout*, which is exactly what we trigger here.
void _warmTextLayoutSubsystem() {
  try {
    // Latin + common CJK so both the system font-manager init and the Noto
    // Sans SC face are built now, not on first paint. Regular weight only —
    // heavier weights are warmed in UiInteractiveWarmup during the boot gate.
    // enough: the dominant cost is the one-time subsystem/face setup, not the
    // per-glyph shaping.
    final painter = TextPainter(
      text: TextSpan(text: '加载中 Aa1', style: GoogleFonts.notoSansSc()),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.dispose();
  } on Object {
    // Bundled weights may be absent in dev trees: see
    // tool/sync_bundled_google_fonts.dart.
  }
}

/// Desktop default window size (Linux GTK + Windows Win32 + [WindowOptions]).
const kDefaultDesktopWindowSize = Size(1380, 960);

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  preserveBootSplash(binding);
  installWindowsKeyboardWorkaround();
  await RustLib.init();
  GoogleFonts.config.allowRuntimeFetching = false;
  await loadBundledTerminalFonts();
  await _preloadBundledUiFonts();

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
      // Frameless chrome is applied in completeBootSplashTransition() so the
      // main window does not resize under the native splash.
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Linux paints the splash as an in-window overlay over the Flutter view,
      // so the window itself stays visible. Windows/macOS hide the main window
      // behind the plugin's separate splash window until the reveal.
      if (!Platform.isLinux) {
        await windowManager.setOpacity(0);
      }
      await ensureBootSplashOnTop();
    });
  }

  // Start startup IO up front so the synchronous text-shaping warm-up below
  // overlaps it instead of stacking onto the first frame.
  final pathsFuture = AppPathsBootstrapper.init();
  final preferencesFuture = SharedPreferences.getInstance();

  // Build the text-shaping subsystem + Noto Sans SC face now (off the first
  // frame's LAYOUT phase). Runs while pathsFuture / preferencesFuture are in
  // flight, hiding part of the cost behind their IO.
  _warmTextLayoutSubsystem();

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

  final preferences = await preferencesFuture;
  final defaultWorkspaceDirectoryFuture = DefaultWorkspaceDirectory.resolve(
    preferences: preferences,
  );
  final homeIndexPrefetchFuture = prefetchHomeIndexSnapshots(nativeAppDataPath);
  final bootstrapCubit = AppBootstrapCubit();

  if (!Platform.isAndroid) {
    await windowManager.setPreventClose(true);
  }

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
              shell.workspaceTerminalRegistry,
              shell.gitRepoStore,
              shell.workspaceFileTreeStore,
              shell.workspaceWorktreeRegistry,
              shell.workspaceToolsScopeRegistry,
            ),
          );
        }
        return _AppShutdownScope(
          chatCubit: shell.chatCubit,
          mailboxCubit: shell.mailboxCubit,
          boardCubit: shell.boardCubit,
          notificationCubit: shell.notificationCubit,
          workspaceTerminalRegistry: shell.workspaceTerminalRegistry,
          gitRepoStore: shell.gitRepoStore,
          workspaceFileTreeStore: shell.workspaceFileTreeStore,
          workspaceWorktreeRegistry: shell.workspaceWorktreeRegistry,
          workspaceToolsScopeRegistry: shell.workspaceToolsScopeRegistry,
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
              RepositoryProvider<ConnectionModeService>.value(
                value: shell.connectionModeService,
              ),
              RepositoryProvider<HomeTargetController>.value(
                value: shell.homeTargetController,
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
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: shell.teamCubit),
                BlocProvider.value(value: shell.chatCubit),
                BlocProvider.value(value: shell.memberPresenceCubit),
                BlocProvider.value(value: shell.mailboxCubit),
                BlocProvider.value(value: shell.boardCubit),
                BlocProvider.value(value: shell.notificationCubit),
                BlocProvider.value(value: shell.editorCubit),
                BlocProvider.value(value: shell.configCubit),
                BlocProvider.value(value: shell.appProviderCubit),
                BlocProvider.value(value: shell.llmConfigCubit),
                BlocProvider.value(value: shell.layoutCubit),
                BlocProvider.value(value: shell.workspaceToolsCubit),
                BlocProvider.value(value: shell.sessionPreferencesCubit),
                BlocProvider.value(value: shell.pluginCubit),
                BlocProvider.value(value: shell.skillCubit),
                BlocProvider.value(value: shell.mcpCubit),
                BlocProvider.value(value: shell.teamHubCubit),
                BlocProvider.value(value: shell.extensionCubit),
                BlocProvider.value(value: shell.appUpdateCubit),
                BlocProvider.value(value: shell.sshProfileCubit),
                BlocProvider.value(value: shell.cliPresetsCubit),
                BlocProvider.value(value: shell.aiFeatureSettingsCubit),
              ],
              child: CliToolRegistryScope(
                registry: shell.cliToolRegistry,
                child: const TeamPilotApp(),
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
      (
        String themeMode,
        String colorPreset,
        String typographyScale,
        double typographyCustomMultiplier,
        String uiZoomScale,
        double uiZoomCustomMultiplier,
        String locale,
      )
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
          themeMode,
          normalizeThemeColorPreset(prefs.themeColorPreset),
          normalizeTypographyScale(prefs.typographyScale),
          prefs.typographyScaleCustomMultiplier,
          normalizeTypographyScale(prefs.uiZoomScale),
          prefs.uiZoomCustomMultiplier,
          prefs.locale,
        );
      },
      builder: (context, themePrefs) {
        final (
          themeMode,
          colorPreset,
          typographyScaleId,
          typographyCustomMultiplier,
          uiZoomScaleId,
          uiZoomCustomMultiplier,
          savedLocale,
        ) = themePrefs;
        // Text size: scales fonts via the theme. `standard` == the per-system
        // baseline (OS text-scaling × display scaling); compact/comfortable/
        // custom are relative to it. Read system metrics from the implicit view
        // — there is no MediaQuery ancestor above MaterialApp here.
        final systemView =
            WidgetsBinding.instance.platformDispatcher.implicitView;
        final systemMq = systemView == null
            ? const MediaQueryData()
            : MediaQueryData.fromView(systemView);
        final textBaseline = autoTextScaleForSystem(
          systemMq.textScaler.scale(1.0),
          systemMq.devicePixelRatio,
        );
        final effectiveTextMult = resolveRelativeScale(
          scaleId: typographyScaleId,
          customMultiplier: typographyCustomMultiplier,
          baseline: textBaseline,
        );
        final textScale = AppTypographyScale(multiplier: effectiveTextMult);
        final iconScale = AppTypographyScale(
          multiplier: AppIconSizes.resolveIconMultiplier(
            effectiveTextMultiplier: effectiveTextMult,
            textBaseline: textBaseline,
          ),
        );

        ThemeMode themeModeFromPrefs(String mode) => switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        return ToastificationWrapper(
          config: buildAppToastificationConfig(),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'TeamPilot',
            theme: buildLightTheme(colorPreset, textScale, iconScale),
            darkTheme: buildDarkTheme(colorPreset, textScale, iconScale),
            themeMode: themeModeFromPrefs(themeMode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: savedLocale.isNotEmpty ? Locale(savedLocale) : null,
            builder: (context, child) {
              // Interface zoom: `standard` == the per-display baseline (1/dpr,
              // compensating for OS display scaling); compact/comfortable/custom
              // are relative to it.
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final effectiveZoom = clampUiZoom(
                resolveRelativeScale(
                  scaleId: uiZoomScaleId,
                  customMultiplier: uiZoomCustomMultiplier,
                  baseline: autoUiZoomForDevicePixelRatio(dpr),
                ),
              );
              Widget content = AppTextScaleBoundary(
                child: UiWarmup(
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
              return content;
            },
            localeResolutionCallback: (locale, supportedLocales) {
              if (savedLocale.isNotEmpty) return Locale(savedLocale);
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
      },
    );
  }
}
