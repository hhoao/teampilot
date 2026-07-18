import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _mountedMessageFinder() {
  return find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.key as ValueKey<String>?)?.value.startsWith('msg-') == true,
  );
}

Set<String> _mountedMessageIds(WidgetTester tester) {
  return _mountedMessageFinder()
      .evaluate()
      .map((e) => ((e.widget as Text).key! as ValueKey<String>).value)
      .toSet();
}

List<AiMessage> _pairedMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: i.isEven ? AiRole.user : AiRole.assistant,
      parts: [AiTextPart(text: 't$i')],
    ),
  );
}

/// One user message per turn so turn height == message height.
List<AiMessage> _soloUserMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 't$i')],
    ),
  );
}

Widget _harness({
  required List<AiMessage> messages,
  required ScrollController controller,
  int overscan = 2,
  double estimateHeight = 100,
  Widget? header,
  bool anchorEnd = false,
  bool mountTurns = true,
  bool suppressMeasureScrollCorrection = false,
  Duration keepAliveDuration = Duration.zero,
  int keepAliveMaxExtra = 12,
  bool retainMountedTurns = false,
  bool fillDataWindow = false,
  DateTime Function()? clock,
  void Function(double deltaPixels)? onMeasureScrollCorrection,
  Widget Function(BuildContext context, AiMessage message)? messageBuilder,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 400,
      child: SingleChildScrollView(
        controller: controller,
        child: VirtualThreadViewport(
          messages: messages,
          scrollController: controller,
          overscan: overscan,
          estimateHeight: estimateHeight,
          header: header,
          anchorEnd: anchorEnd,
          mountTurns: mountTurns,
          suppressMeasureScrollCorrection: suppressMeasureScrollCorrection,
          keepAliveDuration: keepAliveDuration,
          keepAliveMaxExtra: keepAliveMaxExtra,
          retainMountedTurns: retainMountedTurns,
          fillDataWindow: fillDataWindow,
          clock: clock,
          onMeasureScrollCorrection: onMeasureScrollCorrection,
          messageBuilder: messageBuilder ??
              (_, m) => SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mounts at most viewport+overscan turns', (tester) async {
    final controller = ScrollController();
    final messages = _pairedMessages(40);
    await tester.pumpWidget(
      _harness(messages: messages, controller: controller),
    );
    await tester.pumpAndSettle();

    // 40 messages → ~20 turns if paired; with height 100 and viewport 400
    // visible turns ~4 + overscan 2*2 → mount cap well under 20.
    final mounted = _mountedMessageFinder();
    expect(mounted.evaluate().length, lessThan(messages.length));
    expect(mounted.evaluate().length, lessThanOrEqualTo(20)); // generous cap
  });

  testWidgets('jumpTo mid moves mounted message window', (tester) async {
    final controller = ScrollController();
    final messages = _pairedMessages(40);
    await tester.pumpWidget(
      _harness(messages: messages, controller: controller),
    );
    await tester.pumpAndSettle();

    final before = _mountedMessageIds(tester);
    expect(before, isNotEmpty);

    final mid = controller.position.maxScrollExtent / 2;
    controller.jumpTo(mid);
    await tester.pumpAndSettle();

    final after = _mountedMessageIds(tester);
    expect(after, isNotEmpty);
    expect(after, isNot(equals(before)));
  });

  testWidgets('tall header shifts which messages mount at same scroll', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(40);
    const headerHeight = 500.0;

    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        header: const SizedBox(
          height: headerHeight,
          width: double.infinity,
          child: Text('HEADER'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Document offset just past the header → turn-space scroll ≈ 0.
    // Without subtracting header height, visibleRange treats 500 as mid-list.
    controller.jumpTo(headerHeight);
    await tester.pumpAndSettle();

    final mounted = _mountedMessageIds(tester);
    expect(mounted, contains('msg-m0'));
    expect(mounted, isNot(contains('msg-m10')));
  });

  testWidgets('expand fully above viewport requests scroll correction', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    final heights = <String, double>{
      for (final m in messages) m.id: 100,
    };
    final corrections = <double>[];

    late void Function(void Function()) setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return SizedBox(
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: VirtualThreadViewport(
                  messages: messages,
                  scrollController: controller,
                  // Keep turn0 mounted in overscan while viewport top is past it.
                  overscan: 3,
                  estimateHeight: 100,
                  onMeasureScrollCorrection: corrections.add,
                  messageBuilder: (_, m) => SizedBox(
                    height: heights[m.id]!,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Viewport top at turn-space 250 → turn0 (0–100) fully above.
    controller.jumpTo(250);
    await tester.pumpAndSettle();
    corrections.clear();

    setHarnessState(() {
      heights['m0'] = 200;
    });
    await tester.pumpAndSettle();

    expect(corrections, isNotEmpty);
    expect(corrections.reduce((a, b) => a + b), closeTo(100, 1));
  });

  testWidgets('expand straddling viewport top does not correct', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    final heights = <String, double>{
      for (final m in messages) m.id: 100,
    };
    final corrections = <double>[];

    late void Function(void Function()) setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return SizedBox(
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: VirtualThreadViewport(
                  messages: messages,
                  scrollController: controller,
                  overscan: 1,
                  estimateHeight: 100,
                  onMeasureScrollCorrection: corrections.add,
                  messageBuilder: (_, m) => SizedBox(
                    height: heights[m.id]!,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Viewport top at 50 → turn0 (0–100) straddles; must not correct.
    controller.jumpTo(50);
    await tester.pumpAndSettle();
    corrections.clear();

    setHarnessState(() {
      heights['m0'] = 200;
    });
    await tester.pumpAndSettle();

    expect(corrections, isEmpty);
  });

  testWidgets('suppressMeasureScrollCorrection skips fully-above expand', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    final heights = <String, double>{
      for (final m in messages) m.id: 100,
    };
    final corrections = <double>[];

    late void Function(void Function()) setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return SizedBox(
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: VirtualThreadViewport(
                  messages: messages,
                  scrollController: controller,
                  overscan: 3,
                  estimateHeight: 100,
                  suppressMeasureScrollCorrection: true,
                  onMeasureScrollCorrection: corrections.add,
                  messageBuilder: (_, m) => SizedBox(
                    height: heights[m.id]!,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.jumpTo(250);
    await tester.pumpAndSettle();
    corrections.clear();

    setHarnessState(() {
      heights['m0'] = 200;
    });
    await tester.pumpAndSettle();

    expect(corrections, isEmpty);
  });

  testWidgets('mountTurns false builds no messages', (tester) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        mountTurns: false,
        estimateHeight: 100,
      ),
    );
    await tester.pump();

    expect(_mountedMessageIds(tester), isEmpty);
    expect(controller.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('anchorEnd + tiny estimate mounts few turns near end', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(30);
    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 2,
        estimateHeight: 50,
        anchorEnd: true,
        suppressMeasureScrollCorrection: true,
        messageBuilder: (_, m) => SizedBox(
          height: 800,
          width: double.infinity,
          child: Text(m.id, key: ValueKey('msg-${m.id}')),
        ),
      ),
    );
    // First frame at scroll 0 with stick+anchorEnd should still prefer suffix.
    await tester.pump();

    final mounted = _mountedMessageIds(tester);
    expect(mounted.length, lessThanOrEqualTo(4));
    expect(mounted, isNotEmpty);
    final indices = mounted.map((id) {
      final raw = id.startsWith('msg-') ? id.substring(4) : id;
      return int.parse(raw.substring(1));
    }).toList()
      ..sort();
    expect(indices.last, greaterThan(20));
  });

  testWidgets('scroll to top with anchorEnd mounts prefix not blank suffix', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(30);
    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 2,
        estimateHeight: 100,
        anchorEnd: true,
        // Stick released — user scrolled away from bottom.
        suppressMeasureScrollCorrection: false,
      ),
    );
    await tester.pumpAndSettle();

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    final mounted = _mountedMessageIds(tester);
    expect(mounted, isNotEmpty);
    expect(mounted.contains('msg-m0'), isTrue);
    final indices = mounted.map((id) {
      final raw = id.startsWith('msg-') ? id.substring(4) : id;
      return int.parse(raw.substring(1));
    }).toList()
      ..sort();
    expect(indices.first, lessThan(3));
    expect(indices.last, lessThan(15));
  });

  testWidgets('keepAlive retains adjacent scrolled-off turns briefly', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(30);
    var now = DateTime.utc(2026, 7, 18, 12);
    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        estimateHeight: 100,
        keepAliveDuration: const Duration(seconds: 2),
        keepAliveMaxExtra: 8,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();

    expect(_mountedMessageIds(tester), contains('msg-m0'));

    // Scroll just past the first few turns (still near the previous window).
    controller.jumpTo(500);
    await tester.pump();

    // Offstage cache still holds m0 (Finder skips offstage by default).
    final withKeepAlive = find
        .byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.key as ValueKey<String>?)?.value == 'msg-m0',
          skipOffstage: false,
        )
        .evaluate();
    expect(withKeepAlive, isNotEmpty);

    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    final afterExpiry = find
        .byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.key as ValueKey<String>?)?.value == 'msg-m0',
          skipOffstage: false,
        )
        .evaluate();
    expect(afterExpiry, isEmpty);
  });

  testWidgets('retain+fill keeps full data window mounted across long jumps', (
    tester,
  ) async {
    final mounts = <String, int>{};
    final controller = ScrollController();
    final messages = _soloUserMessages(24);

    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        estimateHeight: 100,
        keepAliveDuration: Duration.zero,
        retainMountedTurns: true,
        fillDataWindow: true,
        messageBuilder: (_, m) => _MountCountingBox(
          id: m.id,
          mounts: mounts,
        ),
      ),
    );
    // Chunked fill (~2/frame, one edge) needs several pumps.
    for (var i = 0; i < 40; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(mounts['m0'], 1);
    expect(mounts.length, 24);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(mounts['m0'], 1);
    expect(
      find.byKey(const ValueKey('msg-m0'), skipOffstage: false),
      findsOneWidget,
    );

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(mounts['m0'], 1);
  });

  testWidgets('retain remaps pin across load-older prepend without remount', (
    tester,
  ) async {
    final mounts = <String, int>{};
    final controller = ScrollController();
    var messages = _soloUserMessages(12);

    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        estimateHeight: 100,
        retainMountedTurns: true,
        fillDataWindow: true,
        messageBuilder: (_, m) => _MountCountingBox(
          id: m.id,
          mounts: mounts,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(mounts['m0'], 1);

    // Prepend older page (new ids ahead of existing).
    messages = [
      ..._soloUserMessages(4).map(
        (m) => AiMessage(
          id: 'old-${m.id}',
          role: m.role,
          parts: m.parts,
        ),
      ),
      ...messages,
    ];
    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        estimateHeight: 100,
        retainMountedTurns: true,
        fillDataWindow: true,
        messageBuilder: (_, m) => _MountCountingBox(
          id: m.id,
          mounts: mounts,
        ),
      ),
    );
    await tester.pump();
    expect(mounts['m0'], 1, reason: 'existing turns must not remount on prepend');
  });
}

class _MountCountingBox extends StatefulWidget {
  const _MountCountingBox({required this.id, required this.mounts});

  final String id;
  final Map<String, int> mounts;

  @override
  State<_MountCountingBox> createState() => _MountCountingBoxState();
}

class _MountCountingBoxState extends State<_MountCountingBox> {
  @override
  void initState() {
    super.initState();
    widget.mounts[widget.id] = (widget.mounts[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      width: double.infinity,
      child: Text(widget.id, key: ValueKey('msg-${widget.id}')),
    );
  }
}
