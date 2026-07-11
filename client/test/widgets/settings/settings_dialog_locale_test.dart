import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/settings_dialog.dart';

void main() {
  testWidgets('settings dialog nav and header follow locale changes', (
    tester,
  ) async {
    late VoidCallback changeLocale;

    await tester.pumpWidget(
      _LocaleHost(
        onReady: (change) => changeLocale = change,
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showSettingsDialog(
                  context,
                  navTitle: (l10n) => l10n.settings,
                  entries: [
                    SettingsDialogEntry(
                      icon: Icons.dashboard_customize_outlined,
                      navLabel: (l10n) => l10n.layout,
                      title: (l10n) => l10n.layout,
                      subtitle: (l10n) => l10n.layoutPageSubtitle,
                      bodyBuilder: (_) => const SizedBox.shrink(),
                    ),
                  ],
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Layout'), findsWidgets);

    changeLocale();
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(find.text('通用'), findsWidgets);
  });
}

class _LocaleHost extends StatefulWidget {
  const _LocaleHost({required this.child, required this.onReady});

  final Widget child;
  final void Function(VoidCallback changeLocale) onReady;

  @override
  State<_LocaleHost> createState() => _LocaleHostState();
}

class _LocaleHostState extends State<_LocaleHost> {
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    widget.onReady(() => setState(() => _locale = const Locale('zh')));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: widget.child),
    );
  }
}
