import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Mechanism-level benchmark: current session keep-alive (Offstage + global
/// selects + parent-driven rebuild cascade) vs proposed (per-host
/// TpKeepAliveLayer + cached host slots + per-host selects).
///
/// Counts build / layout calls per host per scenario:
///  1. session switch            (s0 → s3)
///  2. background working change (workingSessionIds gains s2)
///  3. background message emit   (messageVersion bumps for s2 only)
///  4. window resize             (global relayout)
class _PerfState {
  const _PerfState({
    required this.activeSessionId,
    this.workingSessionIds = const {},
    this.structuralVersion = 0,
    this.messageVersionBySession = const {},
  });

  final String? activeSessionId;
  final Set<String> workingSessionIds;

  /// Bumped on switch / session add-remove / selectedMember / launchError —
  /// mirrors the [ChatPageStructuralSignal] gate of ChatPageShell.
  final int structuralVersion;

  /// Per-session chat emit counter; a bump rebuilds only that session's view.
  final Map<String, int> messageVersionBySession;
}

class _PerfCubit extends Cubit<_PerfState> {
  _PerfCubit() : super(const _PerfState(activeSessionId: 's0'));

  void switchSession(String id) => emit(_PerfState(
        activeSessionId: id,
        workingSessionIds: state.workingSessionIds,
        structuralVersion: state.structuralVersion + 1,
        messageVersionBySession: state.messageVersionBySession,
      ));

  void setWorking(Set<String> ids) => emit(_PerfState(
        activeSessionId: state.activeSessionId,
        workingSessionIds: ids,
        structuralVersion: state.structuralVersion,
        messageVersionBySession: state.messageVersionBySession,
      ));

  void emitMessage(String id) => emit(_PerfState(
        activeSessionId: state.activeSessionId,
        workingSessionIds: state.workingSessionIds,
        structuralVersion: state.structuralVersion,
        messageVersionBySession: {
          ...state.messageVersionBySession,
          id: (state.messageVersionBySession[id] ?? 0) + 1,
        },
      ));
}

class _Counters {
  final Map<String, int> builds = {};
  final Map<String, int> layouts = {};

  void build(String id) => builds[id] = (builds[id] ?? 0) + 1;
  void layout(String id) => layouts[id] = (layouts[id] ?? 0) + 1;

  int totalBuilds() => builds.values.fold(0, (a, b) => a + b);
  int totalLayouts() => layouts.values.fold(0, (a, b) => a + b);
}

/// Heavy synthetic chat host: header + 150 message bubbles. Mirrors the
/// layout/build weight of a ChatWorkbench transcript.
class _HeavyHost extends StatelessWidget {
  const _HeavyHost({
    required this.id,
    required this.counters,
    required this.selectScope,
    super.key,
  });

  final String id;
  final _Counters counters;

  /// `global` → watch (activeSessionId, workingSessionIds) like the current
  /// session_chat_view / compose selects. `own` → own-session booleans only.
  final String selectScope;

  @override
  Widget build(BuildContext context) {
    counters.build(id);
    if (selectScope == 'global') {
      final _ = context.select<_PerfCubit, (String?, Set<String>)>(
        (c) => (c.state.activeSessionId, c.state.workingSessionIds),
      );
    } else {
      final _ = context.select<_PerfCubit, bool>(
        (c) =>
            c.state.activeSessionId == id ||
            c.state.workingSessionIds.contains(id),
      );
    }
    final messageVersion = context.select<_PerfCubit, int>(
      (c) => c.state.messageVersionBySession[id] ?? 0,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        counters.layout(id);
        return Column(
          children: [
            const SizedBox(height: 32, child: Text('header')),
            Expanded(
              child: ListView.builder(
                itemCount: 150,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    's$id msg $i v$messageVersion — '
                    'some reasonably long chat bubble text to make paragraph '
                    'layout non-trivial across many hosts',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Current implementation shape: Offstage + TickerMode; hosts are rebuilt on
/// every parent build (parallel lists, no caching). The parent only rebuilds
/// on structural changes — mirroring ChatPageShell's buildWhen gate.
class _Shell extends StatelessWidget {
  const _Shell({
    required this.sessionIds,
    required this.counters,
    required this.stackBuilder,
  });

  final List<String> sessionIds;
  final _Counters counters;
  final Widget Function(List<String> sessionIds, _Counters counters)
      stackBuilder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<_PerfCubit, _PerfState>(
      buildWhen: (p, n) =>
          p.activeSessionId != n.activeSessionId ||
          p.structuralVersion != n.structuralVersion,
      builder: (context, state) => stackBuilder(sessionIds, counters),
    );
  }
}

class _BaselineStack extends StatelessWidget {
  const _BaselineStack({
    required this.sessionIds,
    required this.counters,
  });

  final List<String> sessionIds;
  final _Counters counters;

  @override
  Widget build(BuildContext context) {
    final state = context.read<_PerfCubit>().state;
    final activeSessionId = state.activeSessionId;
    final activeIndex = activeSessionId == null
        ? -1
        : sessionIds.indexOf(activeSessionId);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < sessionIds.length; i++)
          Offstage(
            offstage: i != activeIndex,
            child: TickerMode(
              enabled: i == activeIndex,
              child: _HeavyHost(
                key: ValueKey('host-${sessionIds[i]}'),
                id: sessionIds[i],
                counters: counters,
                selectScope: 'global',
              ),
            ),
          ),
      ],
    );
  }
}

/// Proposed shape: TpKeepAliveLayer per host (skip layout/paint) + cached
/// stateful slots that rebuild only when their own routeActive changes.
class _ProposedStack extends StatelessWidget {
  const _ProposedStack({
    required this.sessionIds,
    required this.counters,
  });

  final List<String> sessionIds;
  final _Counters counters;

  @override
  Widget build(BuildContext context) {
    final state = context.read<_PerfCubit>().state;
    final activeSessionId = state.activeSessionId;
    final activeIndex = activeSessionId == null
        ? -1
        : sessionIds.indexOf(activeSessionId);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < sessionIds.length; i++)
          TpKeepAliveLayer(
            active: i == activeIndex,
            child: TickerMode(
              enabled: i == activeIndex,
              child: _HostSlot(
                key: ValueKey('slot-${sessionIds[i]}'),
                id: sessionIds[i],
                counters: counters,
                routeActive: i == activeIndex,
              ),
            ),
          ),
      ],
    );
  }
}

class _HostSlot extends StatefulWidget {
  const _HostSlot({
    required this.id,
    required this.counters,
    required this.routeActive,
    super.key,
  });

  final String id;
  final _Counters counters;
  final bool routeActive;

  @override
  State<_HostSlot> createState() => _HostSlotState();
}

class _HostSlotState extends State<_HostSlot> {
  Widget? _cachedChild;
  bool? _cachedRouteActive;

  @override
  Widget build(BuildContext context) {
    if (_cachedChild == null || _cachedRouteActive != widget.routeActive) {
      _cachedChild = _HeavyHost(
        key: ValueKey('host-${widget.id}'),
        id: widget.id,
        counters: widget.counters,
        selectScope: 'own',
      );
      _cachedRouteActive = widget.routeActive;
    }
    return _cachedChild!;
  }
}

class _RunResult {
  _RunResult({
    required this.buildDeltas,
    required this.layoutDeltas,
    required this.durationMs,
  });

  final List<int> buildDeltas;
  final List<int> layoutDeltas;
  final double durationMs;
}

Future<_RunResult> _run(
  WidgetTester tester,
  Widget Function(List<String>, _Counters) stackBuilder,
  List<void Function(_PerfCubit)> steps,
) async {
  const sessionIds = ['s0', 's1', 's2', 's3', 's4', 's5'];
  final counters = _Counters();
  final cubit = _PerfCubit();
  await tester.pumpWidget(
    BlocProvider<_PerfCubit>(
      create: (_) => cubit,
      child: MaterialApp(
        home: Scaffold(
          body: _Shell(
            sessionIds: sessionIds,
            counters: counters,
            stackBuilder: stackBuilder,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Fresh view state per run so the resize scenario always changes constraints.
  tester.view.reset();
  await tester.pump();
  // Run every scenario in one session so state is shared between variants;
  // counters are snapshotted per step below.
  final buildDeltas = <int>[];
  final layoutDeltas = <int>[];
  final sw = Stopwatch()..start();
  for (final step in steps) {
    final beforeB = counters.totalBuilds();
    final beforeL = counters.totalLayouts();
    step(cubit);
    // Cubit stream events are delivered on a microtask after the current
    // frame; pump once to flush the listener, once to build the rebuild.
    await tester.pump();
    await tester.pump();
    buildDeltas.add(counters.totalBuilds() - beforeB);
    layoutDeltas.add(counters.totalLayouts() - beforeL);
  }
  sw.stop();
  return _RunResult(
    buildDeltas: buildDeltas,
    layoutDeltas: layoutDeltas,
    durationMs: sw.elapsedMicroseconds / 1000,
  );
}

Future<void> _pumpEmpty(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets(
      'proposed shape does strictly less build/layout work per scenario',
      (tester) async {
    final steps = <void Function(_PerfCubit)>[
      (c) => c.switchSession('s3'),
      (c) => c.setWorking({'s2'}),
      (c) => c.emitMessage('s2'),
      (c) {
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
      },
    ];

    final baseline = await _run(
      tester,
      (ids, c) => _BaselineStack(sessionIds: ids, counters: c),
      steps,
    );
    await _pumpEmpty(tester);

    final proposed = await _run(
      tester,
      (ids, c) => _ProposedStack(sessionIds: ids, counters: c),
      steps,
    );
    await _pumpEmpty(tester);

    // Scenario expectations (6 hosts, active s0):
    // 1 switch s0→s3: baseline cascades into all 6 hosts; proposed rebuilds
    //   only the 2 hosts whose routeActive flips.
    // 2 working change: baseline's global set select fires on all 6 hosts;
    //   proposed only on s2 (per-host contains).
    // 3 message emit to s2: identical per-session cost — no regression.
    // 4 resize: Offstage lays out all 6 hosts; TpKeepAliveLayer skips layout
    //   for the 5 inactive ones.
    expect(baseline.buildDeltas[0], 6);
    expect(proposed.buildDeltas[0], 2);
    expect(baseline.buildDeltas[1], 6);
    expect(proposed.buildDeltas[1], 1);
    expect(baseline.buildDeltas[2], 1);
    expect(proposed.buildDeltas[2], 1);
    expect(baseline.layoutDeltas[3], 6);
    expect(proposed.layoutDeltas[3], 1);

    debugPrint(
      'baseline: builds ${baseline.buildDeltas} layouts ${baseline.layoutDeltas} '
      '${baseline.durationMs.toStringAsFixed(1)}ms',
    );
    debugPrint(
      'proposed: builds ${proposed.buildDeltas} layouts ${proposed.layoutDeltas} '
      '${proposed.durationMs.toStringAsFixed(1)}ms',
    );

    // Total work must be strictly smaller in the proposed shape.
    expect(
      proposed.buildDeltas.fold<int>(0, (a, b) => a + b),
      lessThan(baseline.buildDeltas.fold<int>(0, (a, b) => a + b)),
    );
    expect(
      proposed.layoutDeltas.fold<int>(0, (a, b) => a + b),
      lessThan(baseline.layoutDeltas.fold<int>(0, (a, b) => a + b)),
    );
  });
}
