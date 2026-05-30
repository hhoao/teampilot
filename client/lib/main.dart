import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/src/rust/frb_generated.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_shell.dart';
import 'cubits/chat_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'l10n/l10n_extensions.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/ssh_credential_store.dart';
import 'repositories/ssh_known_host_repository.dart';
import 'repositories/ssh_profile_repository.dart';
import 'router/app_router.dart';
import 'services/cli/registry/cli_tool_registry_scope.dart';
import 'services/storage/app_storage.dart';
import 'services/app/connection_mode_service.dart';
import 'services/storage/flashskyai_storage_roots.dart';
import 'services/ssh/ssh_client_factory.dart';
import 'services/terminal/terminal_transport_factory.dart';
import 'services/terminal/terminal_fonts.dart';
import 'theme/app_theme.dart';
import 'theme/app_typography_scale.dart';
import 'pages/system/error_page.dart';
import 'utils/logger.dart';
import 'widgets/ui_warmup.dart';

class _CleanupWindowListener extends WindowListener {
  _CleanupWindowListener(this.chatCubit);
  final ChatCubit chatCubit;

  @override
  void onWindowClose() {
    unawaited(_shutdownAndDestroy());
  }

  Future<void> _shutdownAndDestroy() async {
    try {
      await chatCubit.close();
    } finally {
      await windowManager.destroy();
    }
  }
}

/// [BlocProvider.value] does not call [ChatCubit.close]; dispose here covers
/// hot restart and other cases where the widget tree tears down.
class _AppShutdownScope extends StatefulWidget {
  const _AppShutdownScope({required this.chatCubit, required this.child});

  final ChatCubit chatCubit;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    unawaited(widget.chatCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _preloadBundledUiFonts() async {
  try {
    await GoogleFonts.pendingFonts([GoogleFonts.notoSansSc()]);
  } on Object {
    // Run `dart run tool/sync_bundled_google_fonts.dart` from client/, then rebuild.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  GoogleFonts.config.allowRuntimeFetching = false;
  await loadBundledTerminalFonts();
  await _preloadBundledUiFonts();

  if (!Platform.isAndroid) {
    await windowManager.ensureInitialized();
    final windowRect = await windowManager.getBounds();
    WindowOptions windowOptions = WindowOptions(
      size: Size(
        (windowRect.width > 400) ? windowRect.width : 1200,
        (windowRect.height > 300) ? windowRect.height : 700,
      ),
      minimumSize: const Size(800, 500),
      center: false,
      title: 'TeamPilot',
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
          windowManager.addListener(_CleanupWindowListener(shell.chatCubit));
        }
        return _AppShutdownScope(
          chatCubit: shell.chatCubit,
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SharedPreferences>.value(
                value: preferences,
              ),
              RepositoryProvider<AppSettingsRepository>.value(
                value: shell.appSettings,
              ),
              RepositoryProvider<SessionRepository>.value(
                value: shell.sessionRepo,
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
              RepositoryProvider<FlashskyaiStorageRoots>.value(
                value: shell.storageRoots,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: shell.teamCubit),
                BlocProvider.value(value: shell.chatCubit),
                BlocProvider.value(value: shell.editorCubit),
                BlocProvider.value(value: shell.configCubit),
                BlocProvider.value(value: shell.appProviderCubit),
                BlocProvider.value(value: shell.llmConfigCubit),
                BlocProvider.value(value: shell.layoutCubit),
                BlocProvider.value(value: shell.sessionPreferencesCubit),
                BlocProvider.value(value: shell.pluginCubit),
                BlocProvider.value(value: shell.skillCubit),
                BlocProvider.value(value: shell.mcpCubit),
                BlocProvider.value(value: shell.appUpdateCubit),
                BlocProvider.value(value: shell.sshProfileCubit),
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
          builder: (context, child) =>
              UiWarmup(child: child ?? const SizedBox.shrink()),
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
