import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/pane_entry_animation.dart';
import 'package:teampilot/widgets/settings/settings_dialog_pane_host.dart';

void main() {
  testWidgets('SettingsDialogPaneHost builds only visited panes', (
    tester,
  ) async {
    var builtPanes = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialogPaneHost(
            paneCount: 3,
            selectedIndex: 0,
            builder: (context, index) {
              builtPanes.add(index);
              return Text('pane-$index');
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(builtPanes, {0});
    expect(find.text('pane-0'), findsOneWidget);
    expect(find.text('pane-1'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsDialogPaneHost(
            paneCount: 3,
            selectedIndex: 1,
            builder: (context, index) {
              builtPanes.add(index);
              return Text('pane-$index');
            },
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(builtPanes, {0, 1});
    expect(find.text('pane-1'), findsOneWidget);
    expect(find.text('pane-0'), findsNothing);
  });

  testWidgets('SettingsDialogPaneHost keeps pane state across re-selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _PaneHostHarness(
          entries: const [
            _CounterPane(label: 'A'),
            _CounterPane(label: 'B'),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('A: 0'), findsOneWidget);
    await tester.tap(find.text('inc'));
    await tester.pumpAndSettle();
    expect(find.text('A: 1'), findsOneWidget);

    await tester.tap(find.text('select-1'));
    await tester.pumpAndSettle();
    expect(find.text('B: 0'), findsOneWidget);

    await tester.tap(find.text('select-0'));
    await tester.pumpAndSettle();
    expect(find.text('A: 1'), findsOneWidget);
  });

  testWidgets('SettingsDialogPaneHost replays entry animation on reselect', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _PaneHostHarness(
          entries: const [
            Text('pane-A'),
            Text('pane-B'),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(PaneEntryAnimation), findsWidgets);

    final firstToken = tester
        .widgetList<PaneEntryAnimation>(find.byType(PaneEntryAnimation))
        .map((w) => w.restartToken)
        .whereType<int>()
        .toSet();

    await tester.tap(find.text('select-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('select-0'));
    await tester.pump();
    final tokensAfter = tester
        .widgetList<PaneEntryAnimation>(find.byType(PaneEntryAnimation))
        .map((w) => w.restartToken)
        .whereType<int>()
        .toSet();

    expect(tokensAfter.any((t) => !firstToken.contains(t)), isTrue);
  });
}

class _PaneHostHarness extends StatefulWidget {
  const _PaneHostHarness({required this.entries});

  final List<Widget> entries;

  @override
  State<_PaneHostHarness> createState() => _PaneHostHarnessState();
}

class _PaneHostHarnessState extends State<_PaneHostHarness> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _selectedIndex = 0),
            child: const Text('select-0'),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedIndex = 1),
            child: const Text('select-1'),
          ),
          Expanded(
            child: SettingsDialogPaneHost(
              paneCount: widget.entries.length,
              selectedIndex: _selectedIndex,
              builder: (context, index) => widget.entries[index],
            ),
          ),
        ],
      ),
    );
  }
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
