import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/widgets/settings/settings_dialog.dart';

Widget _wrap({required Widget child}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
    ),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
      child: child,
    ),
  );
}

Future<void> _pumpSized(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(child: child));
}

List<SettingsDialogEntry> _stubEntries() => [
  SettingsDialogEntry(
    icon: Icons.home_outlined,
    navLabel: (_) => 'Section A',
    title: (_) => 'Section A Title',
    subtitle: (_) => 'Section A subtitle',
    bodyBuilder: (_) => const Text('body-a'),
  ),
  SettingsDialogEntry(
    icon: Icons.settings_outlined,
    navLabel: (_) => 'Section B',
    title: (_) => 'Section B Title',
    subtitle: (_) => 'Section B subtitle',
    bodyBuilder: (_) => const Text('body-b'),
  ),
];

List<SettingsDialogEntry> _statefulEntries() => [
  SettingsDialogEntry(
    icon: Icons.home_outlined,
    navLabel: (_) => 'Section A',
    title: (_) => 'Section A Title',
    subtitle: (_) => '',
    bodyBuilder: (_) => const _CounterPane(label: 'A'),
  ),
  SettingsDialogEntry(
    icon: Icons.settings_outlined,
    navLabel: (_) => 'Section B',
    title: (_) => 'Section B Title',
    subtitle: (_) => '',
    bodyBuilder: (_) => const _CounterPane(label: 'B'),
  ),
];

Future<void> _openSettingsDialog(
  WidgetTester tester, {
  required Size viewport,
  List<SettingsDialogEntry>? entries,
}) async {
  await _pumpSized(
    tester,
    viewport,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () {
            showSettingsDialog(
              context,
              navTitle: (_) => 'Settings',
              entries: entries ?? _stubEntries(),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow: nav labels, tap detail, back to nav', (tester) async {
    await _openSettingsDialog(
      tester,
      viewport: const Size(400, 800),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('Section B'), findsOneWidget);
    expect(find.text('Section A Title'), findsNothing);
    expect(find.text('body-a'), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    await tester.tap(find.text('Section A'));
    await tester.pumpAndSettle();

    expect(find.text('Section A Title'), findsOneWidget);
    expect(find.text('body-a'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Section A Title'), findsNothing);
    expect(find.text('body-a'), findsNothing);
  });

  testWidgets('wide: nav and body panes visible together', (tester) async {
    await _openSettingsDialog(
      tester,
      viewport: const Size(1200, 800),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('Section B'), findsOneWidget);
    expect(find.text('Section A Title'), findsOneWidget);
    expect(find.text('body-a'), findsOneWidget);
    expect(find.text('body-b'), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

    await tester.tap(find.text('Section B'));
    await tester.pumpAndSettle();

    expect(find.text('Section B Title'), findsOneWidget);
    expect(find.text('body-b'), findsOneWidget);
    expect(find.text('body-a'), findsNothing);
  });

  testWidgets('uses WorkspacePanePolicy narrow breakpoint', (tester) async {
    final breakpoint = WorkspacePanePolicy.narrowBreakpointWidth;
    await _openSettingsDialog(
      tester,
      viewport: Size(breakpoint - 1, 800),
    );

    expect(find.text('Section A Title'), findsNothing);
    expect(find.text('Section A'), findsOneWidget);

    await tester.tap(find.text('Section A'));
    await tester.pumpAndSettle();

    expect(find.text('Section A Title'), findsOneWidget);
  });

  testWidgets('wide: A→B→A keeps pane state', (tester) async {
    await _openSettingsDialog(
      tester,
      viewport: const Size(1200, 800),
      entries: _statefulEntries(),
    );

    expect(find.text('A: 0'), findsOneWidget);

    await tester.tap(find.text('inc'));
    await tester.pumpAndSettle();
    expect(find.text('A: 1'), findsOneWidget);

    await tester.tap(find.text('Section B'));
    await tester.pumpAndSettle();
    expect(find.text('B: 0'), findsOneWidget);
    expect(find.text('A: 1'), findsNothing);

    await tester.tap(find.text('Section A'));
    await tester.pumpAndSettle();
    expect(find.text('A: 1'), findsOneWidget);
  });

  testWidgets('wide: Escape dismisses settings dialog', (tester) async {
    await _openSettingsDialog(
      tester,
      viewport: const Size(1200, 800),
    );

    expect(find.text('Section A Title'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Section A Title'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

class _CounterPane extends StatefulWidget {
  const _CounterPane({required this.label});

  final String label;

  @override
  State<_CounterPane> createState() => _CounterPaneState();
}

class _CounterPaneState extends State<_CounterPane> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.label}: $_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('inc'),
        ),
      ],
    );
  }
}
