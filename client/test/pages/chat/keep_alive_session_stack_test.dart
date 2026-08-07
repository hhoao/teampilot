import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/keep_alive_session_stack.dart';

void main() {
  testWidgets('switching active index keeps inactive host State mounted', (
    tester,
  ) async {
    var active = 'a';
    late StateSetter setActive;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setActive = setState;
            return KeepAliveSessionStack(
              sessionIds: const ['a', 'b'],
              activeSessionId: active,
              hosts: const [_ProbeHost(id: 'a'), _ProbeHost(id: 'b')],
            );
          },
        ),
      ),
    );

    // Host A active; increment its counter.
    await tester.tap(find.byKey(const Key('probe-a')));
    await tester.pump();
    expect(find.text('a-count-1', skipOffstage: false), findsOneWidget);

    // Switch to B: A goes offstage but stays mounted (State survives).
    setActive(() => active = 'b');
    await tester.pump();
    expect(find.text('b-count-0'), findsOneWidget);
    expect(find.text('a-count-1', skipOffstage: false), findsOneWidget);

    // Back to A: the counter persisted because State was never disposed.
    setActive(() => active = 'a');
    await tester.pump();
    expect(find.text('a-count-1'), findsOneWidget);
  });
}

class _ProbeHost extends StatefulWidget {
  const _ProbeHost({required this.id});

  final String id;

  @override
  State<_ProbeHost> createState() => _ProbeHostState();
}

class _ProbeHostState extends State<_ProbeHost> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: Key('probe-${widget.id}'),
        onTap: () => setState(() => _count++),
        child: Text('${widget.id}-count-$_count'),
      ),
    );
  }
}
