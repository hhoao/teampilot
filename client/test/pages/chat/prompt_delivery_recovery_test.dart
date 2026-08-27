import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/prompt_delivery_status_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/prompt_delivery_recovery_strip.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/agent_runtime/agent_runtime.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_runtime/runtime_event_journal.dart';
import 'package:teampilot/services/agent_runtime/seat_event_stream.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

const seat = RuntimeSeatKey(sessionId: 'sess-1', memberId: 'member-1');

void main() {
  test('status cubit surfaces the latest submittedUnknown record for a seat',
      () async {
    final harness = _RecoveryHarness();
    addTearDown(harness.dispose);
    await harness.seedDelivery(state: PromptDeliveryState.confirmed, text: 'old');
    await harness.seedDelivery(
      state: PromptDeliveryState.submittedUnknown,
      text: 'latest unknown',
    );

    await harness.cubit.refreshSession(seat.sessionId);

    final recovery = harness.cubit.state.recoveryFor(
      seat.sessionId,
      seat.memberId,
    );
    expect(recovery, isNotNull);
    expect(recovery!.text, 'latest unknown');
  });

  test('a newer delivery hides an older submittedUnknown recovery', () async {
    final harness = _RecoveryHarness();
    addTearDown(harness.dispose);
    await harness.seedDelivery(
      state: PromptDeliveryState.submittedUnknown,
      text: 'stale unknown',
    );
    await harness.seedDelivery(state: PromptDeliveryState.created, text: 'new');

    await harness.cubit.refreshSession(seat.sessionId);

    expect(
      harness.cubit.state.recoveryFor(seat.sessionId, seat.memberId),
      isNull,
    );
  });

  testWidgets(
    'submittedUnknown offers review and retry without automatic PTY write',
    (tester) async {
      final harness = _RecoveryHarness();
      addTearDown(harness.dispose);
      await harness.seedDelivery(
        state: PromptDeliveryState.submittedUnknown,
        text: 'the lost prompt',
      );
      // No manual cubit refresh: the mount primes recovery on session open.
      harness.ptyWrites.clear();

      await tester.pumpWidget(harness.widget());
      await tester.pumpAndSettle();

      expect(find.text('Delivery status unknown'), findsOneWidget);
      expect(harness.ptyWrites, isEmpty);

      // Review reveals the retained prompt without touching the terminal.
      await tester.tap(find.text('Review message'));
      await tester.pumpAndSettle();
      expect(find.text('the lost prompt'), findsOneWidget);
      expect(harness.ptyWrites, isEmpty);

      // Explicit retry creates a NEW durable delivery id; the seeded record
      // stays submittedUnknown and is never resumed.
      await tester.tap(find.text('Resend'));
      await tester.pumpAndSettle();

      expect(harness.resubmits, [
        (seat.sessionId, seat.memberId, 'the lost prompt'),
      ]);
      expect(harness.createdIds, hasLength(2));
      expect(
        harness.createdIds.last,
        isNot(harness.createdIds.first),
      );
      expect(
        (await harness.store.read(harness.createdIds.first))!.state,
        PromptDeliveryState.submittedUnknown,
      );
      // The explicit retry performs the only PTY write, through the fenced
      // submit path.
      expect(harness.ptyWrites, ['the lost prompt']);
    },
  );

  testWidgets(
    'mount primes recovery on session open: strip appears from the durable store',
    (tester) async {
      final harness = _RecoveryHarness();
      addTearDown(harness.dispose);
      await harness.seedDelivery(
        state: PromptDeliveryState.submittedUnknown,
        text: 'primed on mount',
      );
      harness.ptyWrites.clear();

      // Mount the recovery surface BEFORE any refreshSession call. The mount
      // runs the post-frame refresh itself, so the strip must appear without
      // a manual cubit call (the D-C1 restart-recovery dead-surface fix).
      await tester.pumpWidget(harness.widget());
      await tester.pumpAndSettle();

      expect(find.text('Delivery status unknown'), findsOneWidget);
      expect(find.text('primed on mount'), findsNothing); // not revealed yet
      expect(harness.ptyWrites, isEmpty);

      // The strip is reachable for a real retry.
      await tester.tap(find.text('Review message'));
      await tester.pumpAndSettle();
      expect(find.text('primed on mount'), findsOneWidget);
    },
  );

  testWidgets('strip stays hidden when the seat has no recoverable delivery',
      (tester) async {
    final harness = _RecoveryHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget());
    await tester.pumpAndSettle();

    expect(find.text('Delivery status unknown'), findsNothing);
  });
}

class _RecoveryHarness {
  final journal = MemoryRuntimeEventJournal();
  final stream = SeatEventStream();
  final attentionCubit = AgentAttentionCubit(pruneInterval: null);
  final ptyWrites = <String>[];
  final resubmits = <(String, String, String)>[];

  /// Every delivery id the coordinator minted, observed through durable
  /// saves (no production hooks required).
  final createdIds = <String>[];
  var _ids = 0;

  late final MemoryPromptDeliveryStore store = MemoryPromptDeliveryStore();

  late final PromptDeliveryCoordinator coordinator = PromptDeliveryCoordinator(
    store: _RecordingPromptDeliveryStore(store, createdIds),
    commands: _RecordingRecoveryCommands(ptyWrites),
    idGenerator: () => 'delivery-${_ids++}',
    clock: () => DateTime.utc(2026, 8, 25, 12),
  );

  late final AgentRuntime runtime = AgentRuntime(
    gateway: AgentEventGateway(
      journal: journal,
      stream: stream,
      resolveCli: (_, __) => CliTool.claude,
    ),
    promptDeliveries: coordinator,
  );

  late final PromptDeliveryStatusCubit cubit = PromptDeliveryStatusCubit(
    runtime: runtime,
    resubmit: (sessionId, memberId, text) async {
      resubmits.add((sessionId, memberId, text));
      // Real fenced path: mint a NEW durable delivery and issue its submit.
      final delivery = await coordinator.submit(
        PromptDeliveryRequest(seat: seat, cli: CliTool.claude, text: text),
      );
      await coordinator.issueSubmit(delivery.id);
      return true;
    },
  );

  Future<void> seedDelivery({
    required PromptDeliveryState state,
    required String text,
  }) async {
    final delivery = await coordinator.submit(
      PromptDeliveryRequest(seat: seat, cli: CliTool.claude, text: text),
    );
    switch (state) {
      case PromptDeliveryState.created:
      case PromptDeliveryState.waitingForInputSurface:
      case PromptDeliveryState.staged:
        break;
      case PromptDeliveryState.submitIssued:
        await coordinator.issueSubmit(delivery.id);
      case PromptDeliveryState.confirmed:
        await coordinator.issueSubmit(delivery.id);
        await coordinator.onRuntimeEvent(_promptSubmitted(text));
      case PromptDeliveryState.submittedUnknown:
        await coordinator.issueSubmit(delivery.id);
        await coordinator.markSubmittedUnknown(delivery.id);
      case PromptDeliveryState.failed:
        await coordinator.failBeforeSubmit(delivery.id);
    }
  }

  RuntimeEventEnvelope _promptSubmitted(String text) => RuntimeEventEnvelope(
        seat: seat,
        cli: CliTool.claude,
        kind: RuntimeEventKind.promptSubmitted,
        occurredAt: DateTime.utc(2026, 8, 25, 12),
        prompt: text,
        sequence: 1,
      );

  Widget widget() {
    final theme = ThemeData(useMaterial3: true);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          theme.colorScheme,
          scale: 1.0,
          controlScale: AppTypographyScale.standard.multiplier,
        ),
        child: BlocProvider<PromptDeliveryStatusCubit>.value(
          value: cubit,
          child: Scaffold(
            body: BlocBuilder<PromptDeliveryStatusCubit,
                PromptDeliveryStatusState>(
              bloc: cubit,
              builder: (context, state) {
                return PromptDeliveryRecoveryMount(
                  key: const ValueKey('recovery-mount'),
                  recovery: state.recoveryFor(
                    seat.sessionId,
                    seat.memberId,
                  ),
                  onRetry: () => unawaited(
                    cubit.retry(
                      sessionId: seat.sessionId,
                      memberId: seat.memberId,
                    ),
                  ),
                  onRefresh: () => cubit.refreshSession(seat.sessionId),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    await runtime.dispose();
    await attentionCubit.close();
    await stream.close();
    await cubit.close();
  }
}

final class _RecordingPromptDeliveryStore implements PromptDeliveryStore {
  _RecordingPromptDeliveryStore(this._inner, this.createdIds);

  final PromptDeliveryStore _inner;
  final List<String> createdIds;

  @override
  Future<void> save(PromptDelivery delivery) async {
    // Record each distinct id once (every state transition re-saves).
    if (!createdIds.contains(delivery.id)) createdIds.add(delivery.id);
    await _inner.save(delivery);
  }

  @override
  Future<PromptDelivery?> read(String id) => _inner.read(id);

  @override
  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) =>
      _inner.activeFor(seat);

  @override
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat) =>
      _inner.forSeat(seat);

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) =>
      _inner.seatsForSession(sessionId);
}

final class _RecordingRecoveryCommands implements PromptDeliveryCommands {
  _RecordingRecoveryCommands(this.ptyWrites);

  final List<String> ptyWrites;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    if (!canExecute()) return PromptSubmissionResult.dropped;
    ptyWrites.add(delivery.text);
    return PromptSubmissionResult.submitted;
  }
}
