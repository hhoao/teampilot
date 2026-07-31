import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/pane_entry_animation.dart';

void main() {
  testWidgets('PaneEntryAnimation renders child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PaneEntryAnimation(child: Text('pane'))),
      ),
    );

    expect(find.text('pane'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('pane'), findsOneWidget);
  });

  testWidgets('PaneEntryAnimation restartToken replays without remounting child', (
    tester,
  ) async {
    var mounts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneEntryAnimation(
            restartToken: 0,
            child: _MountProbe(onMount: () => mounts++),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(mounts, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneEntryAnimation(
            restartToken: 1,
            child: _MountProbe(onMount: () => mounts++),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(mounts, 1);
    expect(find.text('probe'), findsOneWidget);
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
