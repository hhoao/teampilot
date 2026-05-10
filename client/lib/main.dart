import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'cubits/chat_cubit.dart';
import 'cubits/config_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/llm_config_cubit.dart';
import 'cubits/team_cubit.dart';
import 'l10n/app_localizations.dart';
import 'repositories/layout_repository.dart';
import 'repositories/llm_config_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/team_repository.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  final windowRect = await windowManager.getBounds();
  WindowOptions windowOptions = WindowOptions(
    size: Size(
      (windowRect.width > 400) ? windowRect.width : 1200,
      (windowRect.height > 300) ? windowRect.height : 700,
    ),
    minimumSize: const Size(800, 500),
    center: false,
    title: 'FlashskyAI Teams',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final preferences = await SharedPreferences.getInstance();

  final teamCubit = TeamCubit(repository: TeamRepository(preferences));
  final chatCubit = ChatCubit();
  final configCubit = ConfigCubit();
  final configPath = p.absolute(p.join(
    Directory.current.path,
    '..',
    'flashshkyai',
    'llm',
    'llm_config.json',
  ));
  final llmConfigCubit = LlmConfigCubit(
      repository: LlmConfigRepository(File(configPath)));
  final layoutCubit = LayoutCubit(repository: LayoutRepository(preferences));

  await teamCubit.load();
  await layoutCubit.load();
  await llmConfigCubit.load();
  chatCubit.loadSessions(const SessionRepository());

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: teamCubit),
        BlocProvider.value(value: chatCubit),
        BlocProvider.value(value: configCubit),
        BlocProvider.value(value: llmConfigCubit),
        BlocProvider.value(value: layoutCubit),
      ],
      child: const FlashskyAiClientApp(),
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

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FlashskyAI Teams',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeModeFromPrefs(prefs.themeMode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: savedLocale.isNotEmpty ? Locale(savedLocale) : null,
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
