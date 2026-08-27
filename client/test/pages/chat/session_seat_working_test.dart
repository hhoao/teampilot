import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/pages/chat/session_seat_working.dart';

import '../../support/post_frame_test_harness.dart';

const _hostKey = Key('session-seat-working-host');
const _sessionId = 'mine';
const _memberId = 'lead';

class _PresenceCubit extends MemberPresenceCubit {
  void replace(Map<String, MemberPresence> presence) {
    emit(MemberPresenceState(presence: presence));
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final bits = watchSessionSeatWorking(
      context,
      workspaceId: 'ws-1',
      sessionId: _sessionId,
      memberId: _memberId,
    );
    return Text('${bits.sessionWorking}:${bits.presence.isWorking}');
  }
}

_HostState _host(WidgetTester tester) {
  return tester.state<_HostState>(find.byKey(_hostKey));
}

void main() {
  late ChatCubit chatCubit;
  late _PresenceCubit presenceCubit;
  late WorkbenchCubit workbenchCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
    presenceCubit = _PresenceCubit();
    workbenchCubit = WorkbenchCubit();
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!presenceCubit.isClosed) await presenceCubit.close();
    if (!workbenchCubit.isClosed) await workbenchCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>(lazy: false, create: (_) => chatCubit),
            BlocProvider<MemberPresenceCubit>(
              lazy: false,
              create: (_) => presenceCubit,
            ),
            BlocProvider<WorkbenchCubit>(
              lazy: false,
              create: (_) => workbenchCubit,
            ),
          ],
          child: const _Host(key: _hostKey),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('other session working does not rebuild this seat', (
    tester,
  ) async {
    await pumpHost(tester);
    final builds = _host(tester).buildCount;

    chatCubit.updateWorkingSessionsForTest({'other'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chatCubit.state.workingSessionIds, {'other'});

    expect(
      _host(tester).buildCount,
      builds,
      reason: 'idle-watch ticks for other sessions must not rebuild this seat',
    );
  });

  testWidgets('this session working rebuilds this seat', (tester) async {
    await pumpHost(tester);
    final builds = _host(tester).buildCount;

    chatCubit.updateWorkingSessionsForTest({_sessionId});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chatCubit.state.workingSessionIds, {_sessionId});

    expect(
      _host(tester).buildCount,
      greaterThan(builds),
      reason: 'this seat must rebuild when its own working bit changes',
    );
  });

  testWidgets('other member presence does not rebuild this seat', (
    tester,
  ) async {
    await pumpHost(tester);
    final builds = _host(tester).buildCount;

    presenceCubit.replace({
      'other-member': const MemberPresence(
        connection: MemberConnection.connected,
        availability: MemberAvailability.working,
      ),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _host(tester).buildCount,
      builds,
      reason: 'presence for other members must not rebuild this seat',
    );
  });

  testWidgets('this member presence rebuilds this seat', (tester) async {
    await pumpHost(tester);
    final builds = _host(tester).buildCount;

    presenceCubit.replace({
      _memberId: const MemberPresence(
        connection: MemberConnection.connected,
        availability: MemberAvailability.working,
      ),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _host(tester).buildCount,
      greaterThan(builds),
      reason: 'this seat must rebuild when its own presence changes',
    );
  });
}
