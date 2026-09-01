import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/terminal_input_command_queue.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);

  test('unconfirmed first send does not block a later direct retry', () async {
    final harness = _DeliveryHarness();

    await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'first',
      directToPty: true,
    );
    final id = await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'retry',
      directToPty: true,
    );

    expect(id, isNotEmpty);
    expect(
      (harness.pty! as _RecordingPromptCommands).submittedPrompts,
      ['first', 'retry'],
    );
  });

  test('one landing send with delayed Codex confirmation has one submit', () async {
    final harness = _DeliveryHarness();

    final id = await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );
    await harness.publishCodexPromptSubmitted('inspect this');
    await harness.flushQueuedAutomation();

    expect(id, isNotEmpty);
    expect(
      (harness.pty! as _RecordingPromptCommands).submittedPrompts,
      ['inspect this'],
    );
  });

  test('tracked workflow delivery id reuses one PTY submission', () async {
    final harness = _DeliveryHarness();

    final first = await harness.delivery.deliverTrackedUserCommandToMember(
      's',
      'm',
      'Build the optimal TeamPilot team',
      deliveryId: 'teamgen-kickoff-workflow-123',
    );
    final repeated = await harness.delivery.deliverTrackedUserCommandToMember(
      's',
      'm',
      'Build the optimal TeamPilot team',
      deliveryId: 'teamgen-kickoff-workflow-123',
    );

    expect(first.submitted, isTrue);
    expect(repeated.submitted, isTrue);
    expect(repeated.deliveryId, first.deliveryId);
    expect(
      (harness.pty! as _RecordingPromptCommands).submittedPrompts,
      ['Build the optimal TeamPilot team'],
    );
  });

  test('interrupt invalidates a queued direct prompt before its PTY write',
      () async {
    final commands = _BlockedQueuedPromptCommands();
    final harness = _DeliveryHarness.withCommands(commands);

    final send = harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );
    await commands.submitStarted.future;
    harness.delivery.abortMemberInject('s', 'm');
    commands.release.complete();
    await send;

    expect(commands.ptyWrites, isEmpty);
  });

  test('successful direct submit latches the operator turn once', () async {
    final shell = await ConnectedRecordingShell.connect();
    addTearDown(shell.dispose);
    final afterTurn = <String>[];
    final commands = _RecordingPromptCommands();
    final harness = _DeliveryHarness.connected(
      shell: shell,
      commands: commands,
      onAfterTurnLatched: (sessionId, memberId) {
        afterTurn.add('$sessionId:$memberId');
      },
    );

    await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );

    expect(shell.session.userTurnActive, isTrue);
    expect(afterTurn, ['s:m']);
  });

  test('direct fullscreen submit waits for the grid submit ACK', () async {
    final shell = await ConnectedRecordingShell.connect();
    addTearDown(shell.dispose);
    final tabStore = _DeliveryHarness._connectedTabStore(shell);
    final commands = TabPromptDeliveryCommands(
      tabStore,
      automation: FullscreenPtyAutomation(
        // Non-zero CR poll window: ConnectedRecordingShell paints the submit
        // frame asynchronously after CR, which races instant()'s one-shot ACK
        // check on slower CI hosts (seen on macOS).
        timing: const PtyAutomationTiming(
          afterClear: Duration.zero,
          afterPaste: Duration.zero,
          afterCr: Duration.zero,
          afterReinject: Duration.zero,
          crMaxAttempts: 2,
          reinjectMaxAttempts: 1,
          nudgeMaxAttempts: 2,
          scanRows: 24,
          pollTimeout: Duration(seconds: 2),
          pollInterval: Duration(milliseconds: 5),
        ),
      ),
    );
    const text = 'inspect this';
    final delivery = PromptDelivery(
      id: 'delivery-direct-grid-ack',
      seat: const RuntimeSeatKey(sessionId: 's', memberId: 'm'),
      cli: CliTool.codex,
      text: text,
      normalizedText: text,
      promptEpoch: 1,
      state: PromptDeliveryState.submitIssued,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    await shell.emitPtyOutput('gpt-5.6-luna default · /tmp\r\n›\r\n');
    var completed = false;
    final submit = commands.submit(delivery, canExecute: () => true).then((
      result,
    ) {
      completed = true;
      return result;
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      completed,
      isFalse,
      reason: 'PTY writes alone are not proof that Codex accepted the prompt',
    );

    await shell.emitPtyOutput('› $text\r\n');
    unawaited(_emitCodexSubmitFrameAfterCr(shell, text));

    expect(await submit, PromptSubmissionResult.submitted);
  });

  test('unconfirmed direct submit does not return a successful delivery id',
      () async {
    final harness = _DeliveryHarness.withCommands(
      _UnconfirmedPromptCommands(),
    );

    final id = await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );

    expect(id, isNull);
  });

  test('interrupt racing delivery creation prevents any direct PTY write',
      () async {
    final commands = _RecordingPromptCommands();
    final store = _GatedCreationStore();
    final harness = _DeliveryHarness.withCommands(commands, store: store);

    final send = harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );
    await store.started.future;
    // The interrupt lands while creation is still awaiting, before any
    // delivery id is registered for the seat.
    harness.delivery.abortMemberInject('s', 'm');
    store.release.complete();

    final id = await send;

    expect(id, isNull);
    expect(commands.submittedPrompts, isEmpty);
    final records = await store.recordsFor(
      const RuntimeSeatKey(sessionId: 's', memberId: 'm'),
    );
    expect(records.single.state, PromptDeliveryState.failed);
  });

  test('no-shell direct submit does not latch the operator turn', () async {
    final afterTurn = <String>[];
    final harness = _DeliveryHarness.shellLess(
      onAfterTurnLatched: (sessionId, memberId) {
        afterTurn.add('$sessionId:$memberId');
      },
    );

    await harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );

    expect(afterTurn, isEmpty);
  });

  test('fence-dropped direct submit does not latch the operator turn',
      () async {
    final shell = await ConnectedRecordingShell.connect();
    addTearDown(shell.dispose);
    final afterTurn = <String>[];
    final harness = _DeliveryHarness.connectedReal(
      shell: shell,
      onAfterTurnLatched: (sessionId, memberId) {
        afterTurn.add('$sessionId:$memberId');
      },
    );

    final send = harness.delivery.deliverUserCommandToMember(
      's',
      'm',
      'inspect this',
      directToPty: true,
    );
    const pasteMarker = '\x1b[200~';
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!shell.ptyInputJoined.contains(pasteMarker)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('paste never reached the PTY');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Confirming mid-submit drops the pending CR through the delivery fence.
    await harness.publishCodexPromptSubmitted('inspect this');
    await send;

    expect(afterTurn, isEmpty);
    expect(shell.ptyInputJoined.endsWith('\r'), isFalse);
  });
}

Future<void> _emitCodexSubmitFrameAfterCr(
  ConnectedRecordingShell shell,
  String text,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!shell.ptyInputJoined.contains('\r')) {
    if (DateTime.now().isAfter(deadline)) {
      fail('direct fullscreen submit never wrote CR');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  // The staged row is row 4 in the synthetic screen. Replace that row with
  // transcript text and paint a fresh composer below it.
  await shell.emitPtyOutput('\x1b[4;1H\x1b[2K$text\r\n›\r\n');
}

final class _DeliveryHarness {
  factory _DeliveryHarness() {
    final pty = _RecordingPromptCommands();
    return _DeliveryHarness.withCommands(pty);
  }

  factory _DeliveryHarness.withCommands(
    PromptDeliveryCommands pty, {
    PromptDeliveryStore? store,
  }) {
    final coordinator = PromptDeliveryCoordinator(
      store: store ?? MemoryPromptDeliveryStore(),
      commands: pty,
    );
    final tabStore = ChatTabStore();
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      promptDeliveries: coordinator,
    );
    return _DeliveryHarness._(coordinator, pty, delivery);
  }

  factory _DeliveryHarness.connected({
    required ConnectedRecordingShell shell,
    required PromptDeliveryCommands commands,
    required void Function(String sessionId, String memberId) onAfterTurnLatched,
  }) {
    final tabStore = _connectedTabStore(shell);
    final coordinator = PromptDeliveryCoordinator(
      store: MemoryPromptDeliveryStore(),
      commands: commands,
    );
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      promptDeliveries: coordinator,
      onAfterTurnLatched: onAfterTurnLatched,
    );
    return _DeliveryHarness._(coordinator, commands, delivery);
  }

  factory _DeliveryHarness.connectedReal({
    required ConnectedRecordingShell shell,
    required void Function(String sessionId, String memberId) onAfterTurnLatched,
  }) {
    final tabStore = _connectedTabStore(shell);
    final coordinator = PromptDeliveryCoordinator(
      store: MemoryPromptDeliveryStore(),
      commands: TabPromptDeliveryCommands(tabStore),
    );
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      promptDeliveries: coordinator,
      onAfterTurnLatched: onAfterTurnLatched,
    );
    return _DeliveryHarness._(coordinator, coordinator.commands, delivery);
  }

  factory _DeliveryHarness.shellLess({
    required void Function(String sessionId, String memberId) onAfterTurnLatched,
  }) {
    final tabStore = ChatTabStore();
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      onAfterTurnLatched: onAfterTurnLatched,
    );
    return _DeliveryHarness._(null, null, delivery);
  }

  static ChatTabStore _connectedTabStore(ConnectedRecordingShell shell) {
    final tabStore = ChatTabStore();
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's', title: 'S', subtitle: ''),
      cliTeamName: '',
    )..persistedSession = AppSession(
        sessionId: 's',
        workspaceId: 'workspace',
        sessionTeam: '',
        cli: CliTool.codex,
        createdAt: 0,
      );
    tab.memberShells['m'] = shell.session;
    tabStore.registerSession(tab);
    return tabStore;
  }

  _DeliveryHarness._(this.coordinator, this.pty, this.delivery);

  final PromptDeliveryCoordinator? coordinator;
  final PromptDeliveryCommands? pty;
  final TabMemberPtyDelivery delivery;

  Future<void> publishCodexPromptSubmitted(String prompt) =>
      coordinator!.onRuntimeEvent(
        RuntimeEventEnvelope(
          seat: const RuntimeSeatKey(sessionId: 's', memberId: 'm'),
          cli: CliTool.codex,
          kind: RuntimeEventKind.promptSubmitted,
          occurredAt: DateTime.utc(2026, 8, 25),
          prompt: prompt,
          sequence: 1,
        ),
      );

  Future<void> flushQueuedAutomation() => Future<void>.delayed(Duration.zero);
}

final class _BlockedQueuedPromptCommands implements PromptDeliveryCommands {
  final submitStarted = Completer<void>();
  final release = Completer<void>();
  final ptyWrites = <String>[];
  late final TerminalInputCommandQueue _queue =
      TerminalInputCommandQueue(write: ptyWrites.add);

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
    submitStarted.complete();
    await release.future;
    final result = await _queue.enqueue(
      TerminalInputCommand.bytes(delivery.text, canExecute: canExecute),
    );
    return result == TerminalInputCommandResult.written
        ? PromptSubmissionResult.submitted
        : PromptSubmissionResult.dropped;
  }
}

final class _RecordingPromptCommands implements PromptDeliveryCommands {
  final List<String> submittedPrompts = [];

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
    submittedPrompts.add(delivery.text);
    return PromptSubmissionResult.submitted;
  }
}

final class _UnconfirmedPromptCommands implements PromptDeliveryCommands {
  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async =>
      PromptSubmissionResult.unconfirmed;
}

final class _GatedCreationStore implements PromptDeliveryStore {
  _GatedCreationStore() : _inner = MemoryPromptDeliveryStore();

  final MemoryPromptDeliveryStore _inner;
  final started = Completer<void>();
  final release = Completer<void>();

  Future<List<PromptDelivery>> recordsFor(RuntimeSeatKey seat) =>
      _inner.forSeat(seat);

  @override
  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) =>
      _inner.activeFor(seat);

  @override
  Future<PromptDelivery?> read(String id) => _inner.read(id);

  @override
  Future<void> save(PromptDelivery delivery) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await _inner.save(delivery);
  }

  @override
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat) =>
      _inner.forSeat(seat);

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) =>
      _inner.seatsForSession(sessionId);
}
