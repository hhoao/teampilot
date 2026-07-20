import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';

void main() {
  late TerminalEngine engine;
  late AgentAttentionCubit attention;
  late TerminalLaunchController controller;

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    attention = AgentAttentionCubit(pruneInterval: null);
    controller = TerminalLaunchController(
      engine: engine,
      activityTracker: TerminalActivityTracker(),
      defaultExecutable: 'cursor-agent',
      startupDeadline: const Duration(seconds: 5),
      confirmFallback: const Duration(milliseconds: 50),
      validateLaunch: false,
    );
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
    attention.close();
  });

  Uint8List osc(String title) =>
      Uint8List.fromList(utf8.encode('\x1b]0;$title\x07'));

  test('Cursor seat: action-required OSC title → waiting', () {
    controller.bindCursorTitleAttention(
      sessionId: 's1',
      memberId: 'm1',
      attention: attention,
      skipPermissions: () => false,
    );

    controller.feedPtyBytes(osc('Cursor - action required'));

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('Cursor seat: bare Cursor Agent never marks waiting', () {
    controller.bindCursorTitleAttention(
      sessionId: 's1',
      memberId: 'm1',
      attention: attention,
      skipPermissions: () => false,
    );

    controller.feedPtyBytes(osc('Cursor Agent'));

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );
  });

  test('Cursor seat: non-matching title after waiting clears to done', () {
    controller.bindCursorTitleAttention(
      sessionId: 's1',
      memberId: 'm1',
      attention: attention,
      skipPermissions: () => false,
    );

    controller.feedPtyBytes(osc('Cursor - action required'));
    controller.feedPtyBytes(osc('Cursor ready'));

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.done,
    );
  });

  test('Cursor seat: bare title after waiting does not clear', () {
    controller.bindCursorTitleAttention(
      sessionId: 's1',
      memberId: 'm1',
      attention: attention,
      skipPermissions: () => false,
    );

    controller.feedPtyBytes(osc('Cursor - action required'));
    controller.feedPtyBytes(osc('Cursor Agent'));

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('YOLO skipPermissions does not surface waiting', () {
    controller.bindCursorTitleAttention(
      sessionId: 's1',
      memberId: 'm1',
      attention: attention,
      skipPermissions: () => true,
    );

    controller.feedPtyBytes(osc('Cursor - action required'));

    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );
  });

  test('unbound controller ignores OSC titles', () {
    controller.feedPtyBytes(osc('Cursor - action required'));
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      isNull,
    );
  });
}
