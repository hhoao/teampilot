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

  Future<void> pumpHost(
    WidgetTester tester, {
    bool tickerEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: tickerEnabled,
          child: MultiBlocProvider(
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

  testWidgets(
    'TickerMode off does not rebuild this seat on its own working bit',
    (tester) async {
      await pumpHost(tester, tickerEnabled: false);
      final builds = _host(tester).buildCount;

      chatCubit.updateWorkingSessionsForTest({_sessionId});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(chatCubit.state.workingSessionIds, {_sessionId});

      expect(
        _host(tester).buildCount,
        builds,
        reason:
            'keep-alive background seats must not subscribe to working ticks',
      );
    },
  );

  testWidgets('TickerMode off does not rebuild this seat on its own presence', (
    tester,
  ) async {
    await pumpHost(tester, tickerEnabled: false);
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
      builds,
      reason:
          'keep-alive background seats must not subscribe to presence ticks',
    );
  });

  group('seatSelect', _seatSelectTests);
}

class _IntCubit extends Cubit<int> {
  _IntCubit() : super(0);

  void bump() => emit(state + 1);
}

const _selectHostKey = Key('seat-select-host');

class _SelectHost extends StatefulWidget {
  const _SelectHost({super.key});

  @override
  State<_SelectHost> createState() => _SelectHostState();
}

class _SelectHostState extends State<_SelectHost> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final n = seatSelect<_IntCubit, int>(context, (c) => c.state);
    return Text('$n');
  }
}

_SelectHostState _selectHost(WidgetTester tester) {
  return tester.state<_SelectHostState>(find.byKey(_selectHostKey));
}

void _seatSelectTests() {
  late _IntCubit cubit;

  setUp(() {
    cubit = _IntCubit();
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  Future<void> pumpSelectHost(
    WidgetTester tester, {
    bool tickerEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: tickerEnabled,
          child: BlocProvider<_IntCubit>(
            lazy: false,
            create: (_) => cubit,
            child: const _SelectHost(key: _selectHostKey),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('TickerMode on rebuilds when seatSelect value changes', (
    tester,
  ) async {
    await pumpSelectHost(tester);
    final builds = _selectHost(tester).buildCount;

    cubit.bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_selectHost(tester).buildCount, greaterThan(builds));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('TickerMode off does not subscribe via seatSelect', (
    tester,
  ) async {
    await pumpSelectHost(tester, tickerEnabled: false);
    final builds = _selectHost(tester).buildCount;

    cubit.bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _selectHost(tester).buildCount,
      builds,
      reason: 'keep-alive background seats must read, not select',
    );
    expect(find.text('0'), findsOneWidget);
  });
}
