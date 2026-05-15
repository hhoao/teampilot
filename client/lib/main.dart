import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'cubits/chat_cubit.dart';
import 'cubits/config_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/llm_config_cubit.dart';
import 'cubits/session_preferences_cubit.dart';
import 'cubits/skill_cubit.dart';
import 'cubits/team_cubit.dart';
import 'l10n/app_localizations.dart';
import 'repositories/app_settings_repository.dart';
import 'repositories/layout_repository.dart';
import 'repositories/session_preferences_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/skill_repository.dart';
import 'repositories/team_repository.dart';
import 'router/app_router.dart';
import 'services/app_storage.dart';
import 'services/flashskyai_cli_locator.dart';
import 'services/team_skill_linker_service.dart';
import 'services/temp_team_cleaner.dart';
import 'theme/app_theme.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Noto Sans SC is listed under google_fonts/ assets (sync before build).
  GoogleFonts.config.allowRuntimeFetching = false;

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

  await AppStorage.init();

  final preferences = await SharedPreferences.getInstance();
  final cliLocated = await FlashskyaiCliLocator.locate();
  await AppStorage.useWslCliDataDirIfNeeded(cliLocated);

  final tempTeamCleaner = TempTeamCleaner();
  await tempTeamCleaner.cleanup();

  // Intercept window close so cleanup runs before the process exits.
  await windowManager.setPreventClose(true);

  final sessionRepo = SessionRepository();

  final teamRepo = TeamRepository();

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  final homeDirectory =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    locatedExecutable: cliLocated,
  );

  final llmConfigCubit = LlmConfigCubit(
    appSettings: appSettings,
    currentDirectory: Directory.current.path,
    homeDirectory: homeDirectory,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
  );

  String? llmConfigPathOverrideForLaunch() {
    final s = llmConfigCubit.state;
    return s.isUsingCustomPath ? s.effectiveConfigPath : null;
  }

  final skillRepo = SkillRepository();
  final teamCubit = TeamCubit(
    repository: teamRepo,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    skillLinker: TeamSkillLinkerService(),
    installedSkillsLoader: () => skillRepo.loadInstalled(),
  );
  final skillCubit = SkillCubit(
    skillRepo,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
  );
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));
  final chatCubit = ChatCubit(
    sessionRepository: sessionRepo,
    tempTeamCleaner: tempTeamCleaner,
    llmConfigPathOverride: llmConfigPathOverrideForLaunch,
    autoLaunchAllMembersOnConnect: () =>
        sessionPreferencesCubit.state.preferences.autoLaunchAllMembersOnConnect,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
  );
  final configCubit = ConfigCubit();

  await teamCubit.load();
  await layoutCubit.load();
  await sessionPreferencesCubit.load();
  await llmConfigCubit.load();
  chatCubit.loadProjectData(sessionRepo);
  await skillCubit.loadAll();
  await teamCubit.syncSelectedTeamSkills(installed: skillCubit.state.installed);

  windowManager.addListener(_CleanupWindowListener(chatCubit));

  runApp(
    _AppShutdownScope(
      chatCubit: chatCubit,
      child: RepositoryProvider<SessionRepository>.value(
        value: sessionRepo,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: teamCubit),
            BlocProvider.value(value: chatCubit),
            BlocProvider.value(value: configCubit),
            BlocProvider.value(value: llmConfigCubit),
            BlocProvider.value(value: layoutCubit),
            BlocProvider.value(value: sessionPreferencesCubit),
            BlocProvider.value(value: skillCubit),
          ],
          child: const FlashskyAiClientApp(),
        ),
      ),
    ),
  );
}

class FlashskyAiClientApp extends StatelessWidget {
  const FlashskyAiClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutCubit>().state;
    final prefs = layoutState.preferences;
    final savedLocale = prefs.locale;

    ThemeMode themeModeFromPrefs(String mode) => switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final colorPreset = normalizeThemeColorPreset(prefs.themeColorPreset);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'TeamPilot',
      theme: buildLightTheme(colorPreset),
      darkTheme: buildDarkTheme(colorPreset),
      themeMode: themeModeFromPrefs(prefs.themeMode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
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
  }
}
