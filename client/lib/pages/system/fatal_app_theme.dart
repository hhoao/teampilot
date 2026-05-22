import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../repositories/layout_repository.dart';
import '../../theme/app_theme.dart';

/// Resolves TeamPilot light/dark theme from saved layout prefs (or system).
Future<ThemeData> resolveFatalAppTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final layout = await LayoutRepository(prefs).load();
    final preset = layout.themeColorPreset;
    final brightness = switch (layout.themeMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    return brightness == Brightness.dark
        ? buildDarkTheme(preset)
        : buildLightTheme(preset);
  } on Object {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark
        ? buildDarkTheme()
        : buildLightTheme();
  }
}

/// MaterialApp shell shared by fatal error and other pre-bootstrap routes.
class FatalAppShell extends StatelessWidget {
  const FatalAppShell({
    required this.theme,
    required this.navigatorKey,
    required this.home,
    super.key,
  });

  final ThemeData theme;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeamPilot',
      debugShowCheckedModeBanner: false,
      theme: theme,
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }
}
