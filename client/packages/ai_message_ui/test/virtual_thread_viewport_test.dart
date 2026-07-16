import 'package:ai_message_ui/src/thread_turns.dart';
import 'package:ai_message_ui/src/turn_height_cache.dart';
import 'package:ai_message_ui/src/virtual_thread_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mounts only overscan window not all turns', (tester) async {
    _Probe.mountedIds.clear();
    final turns = List.generate(
      40,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final cache = TurnHeightCache(estimate: 80);
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 240,
          child: VirtualThreadViewport(
            turns: turns,
            heightCache: cache,
            scrollController: controller,
            overscan: 2,
            turnBuilder: (context, turn) => _Probe(id: turn.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Jump near bottom so sticky hosts can start there later; for this unit
    // test start at 0 and assert mount count << 40.
    expect(_Probe.mountedIds.length, lessThan(15));
    expect(_Probe.mountedIds.length, greaterThan(0));
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.id});

  final String id;

  static final Set<String> mountedIds = {};

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.mountedIds.add(widget.id);
  }

  @override
  void dispose() {
    _Probe.mountedIds.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 80, child: Text(widget.id));
  }
}
