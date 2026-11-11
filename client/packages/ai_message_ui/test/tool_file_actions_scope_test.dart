import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/default_tool_resolvers.dart';
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Consumer that records how often it rebuilds and exposes the callback.
class _Consumer extends StatelessWidget {
  const _Consumer({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    final actions = AiToolFileActions.of(context);
    return TextButton(
      onPressed: () => actions.onOpenFile?.call(
        const AiToolFileTarget(path: '/tmp/x'),
      ),
      child: Text(actions.onOpenFile == null ? 'none' : 'open'),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host({
    required this.probe,
    required this.actionsBuilder,
    super.key,
  });

  final VoidCallback probe;
  final AiToolFileActions Function() actionsBuilder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  // Kept identical across rebuilds so the test measures inherited
  // notifications only, never a rebuilt child widget instance.
  late final Widget _child = _Consumer(onBuild: widget.probe);

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AiToolFileActionsScope(
        actions: widget.actionsBuilder(),
        child: _child,
      ),
    );
  }
}

void main() {
  const fileResolver = DefaultAiToolFileTargetResolver();
  const editResolver = NoopEditToolTargetResolver();
  const shellResolver = DefaultAiShellToolTargetResolver();

  testWidgets('recreated callback alone does not dirty consumers', (
    tester,
  ) async {
    var builds = 0;
    final hostKey = GlobalKey<_HostState>();
    final opened = <String>[];

    await tester.pumpWidget(
      _Host(
        key: hostKey,
        probe: () => builds++,
        actionsBuilder: () => AiToolFileActions(
          fileResolver: fileResolver,
          editResolver: editResolver,
          shellResolver: shellResolver,
          onOpenFile: (target) async => opened.add('first:${target.path}'),
        ),
      ),
    );

    final mounted = builds;
    expect(mounted, greaterThan(0), reason: 'consumer must mount');

    // Same resolvers, brand-new closure — the common per-frame host rebuild.
    hostKey.currentState!.rebuild();
    await tester.pump();
    expect(
      builds,
      mounted,
      reason: 'a fresh onOpenFile closure must not rebuild dependents',
    );

    // The forwarded callback must still run the newest host closure.
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(opened, ['first:/tmp/x']);
  });

  testWidgets('changing a resolver notifies consumers', (tester) async {
    var builds = 0;
    final hostKey = GlobalKey<_HostState>();
    AiToolFileTargetResolver resolver = fileResolver;

    await tester.pumpWidget(
      _Host(
        key: hostKey,
        probe: () => builds++,
        actionsBuilder: () => AiToolFileActions(
          fileResolver: resolver,
          editResolver: editResolver,
          shellResolver: shellResolver,
        ),
      ),
    );

    final mounted = builds;
    resolver = const _OtherFileResolver();
    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(
      builds,
      greaterThan(mounted),
      reason: 'a different resolver must republish the actions',
    );
  });

  testWidgets('callback presence flips are published', (tester) async {
    var builds = 0;
    final hostKey = GlobalKey<_HostState>();
    var withCallback = false;

    await tester.pumpWidget(
      _Host(
        key: hostKey,
        probe: () => builds++,
        actionsBuilder: () => AiToolFileActions(
          fileResolver: fileResolver,
          editResolver: editResolver,
          shellResolver: shellResolver,
          onOpenFile: withCallback ? (target) async {} : null,
        ),
      ),
    );

    expect(find.text('none'), findsOneWidget);
    final mounted = builds;

    withCallback = true;
    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(find.text('open'), findsOneWidget);
    expect(builds, greaterThan(mounted));
  });

  testWidgets('fresh equivalent resolver instances do not republish', (
    tester,
  ) async {
    var builds = 0;
    final hostKey = GlobalKey<_HostState>();

    await tester.pumpWidget(
      _Host(
        key: hostKey,
        probe: () => builds++,
        actionsBuilder: () => AiToolFileActions(
          fileResolver: _FreshFileResolver(),
          editResolver: editResolver,
          shellResolver: shellResolver,
        ),
      ),
    );
    final mounted = builds;
    expect(mounted, greaterThan(0));

    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(
      builds,
      mounted,
      reason: 'a new instance of the same resolver type must be absorbed',
    );
  });

  testWidgets('recreating the scope element keeps one published instance', (
    tester,
  ) async {
    final seen = <AiToolFileActions>[];

    Widget scope() => AiToolFileActionsScope(
      scopeId: 'session-a',
      actions: AiToolFileActions(
        fileResolver: fileResolver,
        editResolver: editResolver,
        shellResolver: shellResolver,
        onOpenFile: (target) async {},
      ),
      child: _Probe(onValue: seen.add),
    );

    await tester.pumpWidget(MaterialApp(home: scope()));
    expect(seen, hasLength(1), reason: 'probe must mount');
    final first = seen.first;

    // A different widget type at `home` recreates the scope's element (the
    // message area does this routinely while keyed transcript rows survive).
    await tester.pumpWidget(
      MaterialApp(home: SizedBox(child: scope())),
    );

    expect(seen, hasLength(2), reason: 'probe rebuilt under the new scope');
    expect(
      identical(seen.last, first),
      isTrue,
      reason: 'a remounted scope must not publish a new actions object',
    );
  });

  testWidgets('disposing the scope releases the retained callback', (
    tester,
  ) async {
    var opened = 0;
    final seen = <AiToolFileActions>[];

    await tester.pumpWidget(
      MaterialApp(
        home: AiToolFileActionsScope(
          scopeId: 'dispose-probe',
          actions: AiToolFileActions(
            fileResolver: fileResolver,
            editResolver: editResolver,
            shellResolver: shellResolver,
            onOpenFile: (target) async => opened++,
          ),
          child: _Probe(onValue: seen.add),
        ),
      ),
    );
    final captured = seen.last;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await captured.onOpenFile!(const AiToolFileTarget(path: '/tmp/x'));

    expect(
      opened,
      0,
      reason:
          'a closed session must not keep its BuildContext alive through the '
          'published callback',
    );
  });

  testWidgets('scopes without an owner id never share implicitly', (
    tester,
  ) async {
    final seenA = <AiToolFileActions>[];
    final seenB = <AiToolFileActions>[];

    Widget scope(ValueChanged<AiToolFileActions> onValue) =>
        AiToolFileActionsScope(
          actions: AiToolFileActions(
            fileResolver: fileResolver,
            editResolver: editResolver,
            shellResolver: shellResolver,
            onOpenFile: (target) async {},
          ),
          child: _Probe(onValue: onValue),
        );

    await tester.pumpWidget(
      MaterialApp(home: Column(children: [scope(seenA.add), scope(seenB.add)])),
    );

    expect(seenA, hasLength(1));
    expect(seenB, hasLength(1));
    expect(
      identical(seenA.first, seenB.first),
      isFalse,
      reason: 'no owner id means per-element identity, never a shared callback',
    );
  });

  testWidgets('different owners never share a published callback', (
    tester,
  ) async {
    final seenA = <AiToolFileActions>[];
    final seenB = <AiToolFileActions>[];

    Widget scope(String owner, ValueChanged<AiToolFileActions> onValue) =>
        AiToolFileActionsScope(
          scopeId: owner,
          actions: AiToolFileActions(
            fileResolver: fileResolver,
            editResolver: editResolver,
            shellResolver: shellResolver,
            onOpenFile: (target) async {},
          ),
          child: _Probe(onValue: onValue),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [scope('session-a', seenA.add), scope('session-b', seenB.add)],
        ),
      ),
    );

    expect(seenA, hasLength(1));
    expect(seenB, hasLength(1));
    expect(
      identical(seenA.first, seenB.first),
      isFalse,
      reason: 'two sessions must not share one onOpenFile callback',
    );
  });
}

class _OtherFileResolver implements AiToolFileTargetResolver {
  const _OtherFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

/// Non-const: every construction is a distinct instance of the same type.
class _FreshFileResolver implements AiToolFileTargetResolver {
  _FreshFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _Probe extends StatelessWidget {
  const _Probe({required this.onValue});

  final ValueChanged<AiToolFileActions> onValue;

  @override
  Widget build(BuildContext context) {
    onValue(AiToolFileActions.of(context));
    return const SizedBox.shrink();
  }
}
