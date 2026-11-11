import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:ai_message_ui/src/default_tool_resolvers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AiMessagePart> _parts() => [
  AiReasoningPart(text: 'think'),
  const AiToolCallPart(
    toolCallId: 't1',
    toolName: 'Read',
    argsText: '{"path":"a.dart"}',
    result: 'ok',
    status: AiToolCallStatus.complete,
  ),
];

/// A rebuilt message with the same content but brand-new part instances.
AiMessage _message() =>
    AiMessage(id: 'm1', role: AiRole.assistant, parts: _parts());

const _actions = AiToolFileActions(
  fileResolver: DefaultAiToolFileTargetResolver(),
  editResolver: NoopEditToolTargetResolver(),
  shellResolver: DefaultAiShellToolTargetResolver(),
);

class _Host extends StatefulWidget {
  const _Host({required this.builder, super.key});

  final Widget Function() builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: widget.builder()));
}

/// Builds a new [AiMessage] (and new parts) on every build.
class _MessageBody extends StatelessWidget {
  const _MessageBody();

  @override
  Widget build(BuildContext context) => AiMessageView(message: _message());
}

void main() {
  setUp(() {
    AiChainOfThoughtView.debugBuildCount = 0;
    AiChainOfThoughtView.debugDirtyCount = 0;
    AiChainOfThoughtView.debugBodyBuilds = 0;
    AiChainOfThoughtView.debugMounts = 0;
    AiChainOfThoughtView.debugMissReasons.clear();
  });

  testWidgets('rebuilt message with unchanged content keeps the chain', (
    tester,
  ) async {
    final hostKey = GlobalKey<_HostState>();

    await tester.pumpWidget(
      _Host(
        key: hostKey,
        builder: () => const AiMessageStringsScope(
          strings: AiMessageStrings(),
          child: AiToolFileActionsScope(
            actions: _actions,
            child: _MessageBody(),
          ),
        ),
      ),
    );
    final mounted = AiChainOfThoughtView.debugBuildCount;
    final dirtyOnMount = AiChainOfThoughtView.debugDirtyCount;
    expect(mounted, greaterThan(0), reason: 'chain must mount');
    expect(AiChainOfThoughtView.debugMounts, 1, reason: 'one element');

    hostKey.currentState!.rebuild();
    await tester.pump();

    expect(
      AiChainOfThoughtView.debugBuildCount,
      mounted,
      reason:
          'the transcript hands in freshly parsed messages on each streamed '
          'chunk; unchanged content must not rebuild the chain',
    );
    expect(
      AiChainOfThoughtView.debugDirtyCount,
      dirtyOnMount,
      reason: 'no inherited scope notified the chain',
    );
    expect(
      AiChainOfThoughtView.debugMounts,
      1,
      reason: 'a rebuild must not remount the element',
    );
  });

  testWidgets('a theme notification with unchanged visuals is absorbed', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    Widget app(ThemeData theme) => MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: const Scaffold(
        body: AiMessageStringsScope(
          strings: AiMessageStrings(),
          child: AiToolFileActionsScope(
            actions: _actions,
            child: _MessageBody(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(ThemeData(colorScheme: scheme)));
    final buildsOnMount = AiChainOfThoughtView.debugBuildCount;
    final bodiesOnMount = AiChainOfThoughtView.debugBodyBuilds;
    expect(bodiesOnMount, greaterThan(0), reason: 'chain chrome must build');

    // Different ThemeData (splash factory only) — same scheme, same markdown
    // tokens, so the chain is dirtied but nothing it paints actually changes.
    await tester.pumpWidget(
      app(
        ThemeData(colorScheme: scheme, dividerColor: const Color(0xFF123456)),
      ),
    );

    expect(
      AiChainOfThoughtView.debugBuildCount,
      greaterThan(buildsOnMount),
      reason: 'a new ThemeData dirties the chain',
    );
    expect(
      AiChainOfThoughtView.debugBodyBuilds,
      bodiesOnMount,
      reason: 'the memo must absorb a rebuild with unchanged paint inputs',
    );
    expect(
      AiChainOfThoughtView.debugMissReasons,
      isEmpty,
      reason: 'nothing changed, so no miss reason may be recorded',
    );
  });
}
