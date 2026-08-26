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
import 'package:teampilot/services/terminal/terminal_input_command_queue.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);

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
      (harness.pty as _RecordingPromptCommands).submittedPrompts,
      ['inspect this'],
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
}

final class _DeliveryHarness {
  factory _DeliveryHarness() {
    final pty = _RecordingPromptCommands();
    return _DeliveryHarness.withCommands(pty);
  }

  factory _DeliveryHarness.withCommands(PromptDeliveryCommands pty) {
    final coordinator = PromptDeliveryCoordinator(
      store: MemoryPromptDeliveryStore(),
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

  _DeliveryHarness._(this.coordinator, this.pty, this.delivery);

  final PromptDeliveryCommands pty;
  final PromptDeliveryCoordinator coordinator;
  final TabMemberPtyDelivery delivery;

  Future<void> publishCodexPromptSubmitted(String prompt) =>
      coordinator.onRuntimeEvent(
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
  Future<void> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    submitStarted.complete();
    await release.future;
    await _queue.enqueue(
      TerminalInputCommand.bytes(delivery.text, canExecute: canExecute),
    );
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
  Future<void> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    if (canExecute()) submittedPrompts.add(delivery.text);
  }
}
