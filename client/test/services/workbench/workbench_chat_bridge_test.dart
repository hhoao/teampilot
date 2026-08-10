// test/services/workbench/workbench_chat_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';

import '../../support/post_frame_test_harness.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');

void main() {
  late WorkbenchCubit cubit;
  late ChatCubit chat;
  late WorkbenchChatBridge bridge;
  setUp(() {
    cubit = WorkbenchCubit();
    chat = ChatCubit(
      executableResolver: () => '/bin/true',
      automationRepository: testAutomationRepository(),
    );
    bridge = WorkbenchChatBridge(workbench: cubit, chat: chat);
  });
  tearDown(() async {
    await chat.close();
    await cubit.close();
  });

  group('WorkbenchChatBridge.onSessionTabOpened', () {
    test('feeds a session open into the bar and activates it', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: false);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, _s1);
      expect(center.previewIds, isEmpty);
    });

    test('preview: true surfaces the tab as a preview', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: true);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, _s1);
      expect(center.previewIds, {_s1});
    });

    test('activate: false appends without activating', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: false, activate: false);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, isNull);
    });
  });
}
