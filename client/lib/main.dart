import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_shell.dart';
import 'cubits/chat_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/mailbox_cubit.dart';
import 'l10n/l10n_extensions.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/project_profile_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/ssh_credential_store.dart';
import 'repositories/ssh_known_host_repository.dart';
import 'repositories/ssh_profile_repository.dart';
import 'router/app_router.dart';
import 'services/cli/registry/cli_tool_registry_scope.dart';
import 'services/storage/app_storage.dart';
import 'services/app/connection_mode_service.dart';
import 'services/storage/storage_resolver.dart';
import 'services/ssh/ssh_client_factory.dart';
import 'services/terminal/terminal_transport_factory.dart';
import 'services/terminal/workspace_terminal_registry.dart';
import 'services/terminal/terminal_fonts.dart';
import 'theme/app_theme.dart';
import 'theme/app_typography_scale.dart';
import 'pages/system/error_page.dart';
import 'services/app/windows_keyboard_workaround.dart';
import 'utils/logger.dart';
import 'widgets/app_text_scale_boundary.dart';
import 'widgets/ui_warmup.dart';

class _CleanupWindowListener extends WindowListener {
  _CleanupWindowListener(this.chatCubit, this.workspaceTerminalRegistry);
  final ChatCubit chatCubit;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;

  @override
  void onWindowClose() {
    unawaited(_shutdownAndDestroy());
  }

  Future<void> _shutdownAndDestroy() async {
    try {
      await chatCubit.close();
      workspaceTerminalRegistry.disposeAll();
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
    required this.workspaceTerminalRegistry,
    required this.child,
  });

  final ChatCubit chatCubit;
  final MailboxCubit mailboxCubit;
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    unawaited(widget.chatCubit.close());
    unawaited(widget.mailboxCubit.close());
    widget.workspaceTerminalRegistry.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _preloadBundledUiFonts() async {
  try {
    // Only Regular is awaited before first paint (keeps launch fast). The other
    // weights are ~10MB each and loaded lazily by GoogleFonts on first use,
    // which is what janks the first project tab click — UiWarmup preloads them
    // right after first frame, before the user can click.
    await GoogleFonts.pendingFonts([GoogleFonts.notoSansSc()]);
  } on Object {
    // Run `dart run tool/sync_bundled_google_fonts.dart` from client/, then rebuild.
  }
}

/// Desktop default window size (Linux GTK + Windows Win32 + [WindowOptions]).
const kDefaultDesktopWindowSize = Size(1380, 960);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  late final String nativeAppDataPath;
  try {
    await AppPathsBootstrapper.init();
    nativeAppDataPath = AppPathsBootstrapper.current.basePath;
    await initAppLogging(nativeAppDataPath);
  } on Object catch (error, stackTrace) {
    await showInitErrorApp(error: error, stackTrace: stackTrace);
    return;
  }

  final preferences = await SharedPreferences.getInstance();

  if (!Platform.isAndroid) {
    await windowManager.setPreventClose(true);
  }

  runApp(
    TeamPilotBootstrap(
      preferences: preferences,
      nativeAppDataPath: nativeAppDataPath,
      childBuilder: (shell) {
        if (!Platform.isAndroid) {
          windowManager.addListener(
            _CleanupWindowListener(
              shell.chatCubit,
              shell.workspaceTerminalRegistry,
            ),
          );
        }
        return _AppShutdownScope(
          chatCubit: shell.chatCubit,
          mailboxCubit: shell.mailboxCubit,
          workspaceTerminalRegistry: shell.workspaceTerminalRegistry,
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SharedPreferences>.value(value: preferences),
              RepositoryProvider<AppSettingsRepository>.value(
                value: shell.appSettings,
              ),
              RepositoryProvider<SessionRepository>.value(
                value: shell.sessionRepo,
              ),
              RepositoryProvider<ProjectProfileRepository>.value(
                value: shell.projectProfileRepository,
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
              RepositoryProvider<StorageRoots>.value(value: shell.storageRoots),
              RepositoryProvider<WorkspaceTerminalRegistry>.value(
                value: shell.workspaceTerminalRegistry,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: shell.teamCubit),
                BlocProvider.value(value: shell.chatCubit),
                BlocProvider.value(value: shell.memberPresenceCubit),
                BlocProvider.value(value: shell.mailboxCubit),
                BlocProvider.value(value: shell.editorCubit),
                BlocProvider.value(value: shell.configCubit),
                BlocProvider.value(value: shell.appProviderCubit),
                BlocProvider.value(value: shell.llmConfigCubit),
                BlocProvider.value(value: shell.layoutCubit),
                BlocProvider.value(value: shell.workspaceToolsCubit),
                BlocProvider.value(value: shell.sessionPreferencesCubit),
                BlocProvider.value(value: shell.pluginCubit),
                BlocProvider.value(value: shell.projectProfileCubit),
                BlocProvider.value(value: shell.skillCubit),
                BlocProvider.value(value: shell.mcpCubit),
                BlocProvider.value(value: shell.teamHubCubit),
                BlocProvider.value(value: shell.extensionCubit),
                BlocProvider.value(value: shell.appUpdateCubit),
                BlocProvider.value(value: shell.sshProfileCubit),
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
          prefs.locale,
        );
      },
      builder: (context, themePrefs) {
        final (
          themeMode,
          colorPreset,
          typographyScaleId,
          typographyCustomMultiplier,
          savedLocale,
        ) = themePrefs;
        final typographyScale = typographyScaleForPreferences(
          scaleId: typographyScaleId,
          customMultiplier: typographyCustomMultiplier,
        );

        ThemeMode themeModeFromPrefs(String mode) => switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'TeamPilot',
          theme: buildLightTheme(colorPreset, typographyScale),
          darkTheme: buildDarkTheme(colorPreset, typographyScale),
          themeMode: themeModeFromPrefs(themeMode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: savedLocale.isNotEmpty ? Locale(savedLocale) : null,
          builder: (context, child) {
            // TEMP DIAGNOSTIC (removed in Task 8): records the real per-platform
            // scaling inputs so the compact UI-scale default is measured, not
            // guessed. Run `flutter run -d linux` and read the UI_SCALE_DIAG line.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final mq = MediaQuery.maybeOf(context);
              appLogger.i(
                'UI_SCALE_DIAG platform=${Platform.operatingSystem} '
                'dpr=${mq?.devicePixelRatio} textScaler=${mq?.textScaler} '
                'size=${mq?.size}',
              );
            });
            Widget content = AppTextScaleBoundary(
              child: UiWarmup(child: child ?? const SizedBox.shrink()),
            );
            // The native title bar is hidden (TitleBarStyle.hidden), which on
            // Linux/GTK also strips the resize-border grips. DragToResizeArea
            // re-adds invisible resize handles on all edges/corners so the
            // frameless window can still be resized from its borders.
            if (!Platform.isAndroid) {
              content = DragToResizeArea(child: content);
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
        );
      },
    );
  }
}
