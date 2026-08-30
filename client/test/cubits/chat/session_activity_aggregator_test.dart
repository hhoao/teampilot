import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/session_activity_aggregator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  SessionActivityAggregator aggregator({
    required ChatTabStore store,
    bool Function(String sessionId)? deliveryInFlight,
    bool Function(String sessionId)? attention,
  }) {
    return SessionActivityAggregator(
      tabStore: store,
      sessionWorking: SessionWorkingResolver(),
      globalPresets: () => const [],
      activeTeam: () => null,
      activeSessionId: () => null,
      presence: () => const {},
      sessionBusyFromAttention: attention,
      sessionBusyFromDeliveryInFlight: deliveryInFlight,
    );
  }

  test('delivery in-flight alone yields delivering only, not inTurn', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      deliveryInFlight: (id) => id == 'sess',
    ).computeReasons();
    expect(reasons['sess'], {SessionBusyReason.delivering});
    expect(reasons['sess']!.contains(SessionBusyReason.inTurn), isFalse);
  });

  test(
    'clearing delivery in-flight with no other busy yields empty reasons',
    () {
      final store = ChatTabStore();
      store.registerSession(
        ChatTab(
          info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
          cliTeamName: 'ct',
        ),
      );
      expect(
        aggregator(store: store, deliveryInFlight: (_) => false)
            .computeReasons()['sess'],
        isEmpty,
      );
    },
  );

  test('attention busy alone yields attention only', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'sess',
    ).computeReasons();
    expect(reasons['sess'], {SessionBusyReason.attention});
  });

  test('delivery and attention together yield both, not inTurn', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'sess',
      deliveryInFlight: (id) => id == 'sess',
    ).computeReasons();
    expect(
      reasons['sess'],
      {SessionBusyReason.delivering, SessionBusyReason.attention},
    );
    expect(reasons['sess']!.contains(SessionBusyReason.inTurn), isFalse);
  });

  ChatTab personalInTurnTab() {
    final shell = _ConnectedShell()
      ..activityTracker.latchBootFrameReadyForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      )
      ..markUserTurnStarted();

    return ChatTab(
      info: const ChatTabInfo(id: 'personal-1', title: 'P', subtitle: ''),
      cliTeamName: '',
    )
      ..persistedSession = AppSession(
        sessionId: 'personal-1',
        workspaceId: 'ws',
        folders: const [],
        createdAt: 0,
      )
      ..memberShells['agent'] = shell;
  }

  test('inTurn from member working yields inTurn only', () {
    final store = ChatTabStore();
    store.registerSession(personalInTurnTab());
    expect(
      aggregator(store: store).computeReasons()['personal-1'],
      {SessionBusyReason.inTurn},
    );
  });

  test('all three reasons when inTurn plus attention and delivery', () {
    final store = ChatTabStore();
    store.registerSession(personalInTurnTab());
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'personal-1',
      deliveryInFlight: (id) => id == 'personal-1',
    ).computeReasons();
    expect(
      reasons['personal-1'],
      {
        SessionBusyReason.delivering,
        SessionBusyReason.inTurn,
        SessionBusyReason.attention,
      },
    );
  });

  test('two tabs: idle and delivering both appear in map', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'idle', title: 'i', subtitle: ''),
        cliTeamName: 'ct',
      ),
    );
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'busy', title: 'b', subtitle: ''),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      deliveryInFlight: (id) => id == 'busy',
    ).computeReasons();
    expect(reasons.containsKey('idle'), isTrue);
    expect(reasons['idle'], isEmpty);
    expect(reasons.containsKey('busy'), isTrue);
    expect(reasons['busy'], {SessionBusyReason.delivering});
  });
}

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'true');

  @override
  bool get isRunning => true;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}
