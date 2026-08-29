import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_working_aggregator.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';

void main() {
  TabWorkingAggregator aggregator({
    required ChatTabStore store,
    bool Function(String sessionId)? deliveryInFlight,
    bool Function(String sessionId)? attention,
  }) {
    return TabWorkingAggregator(
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

  test('delivery in-flight alone puts the open session in compute()', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final inFlight = <String>{'sess'};
    final working = aggregator(
      store: store,
      deliveryInFlight: inFlight.contains,
    ).compute();
    expect(working, {'sess'});
  });

  test('clearing delivery in-flight with no other busy removes the session', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    expect(
      aggregator(store: store, deliveryInFlight: (_) => false).compute(),
      isEmpty,
    );
  });

  test('attention busy still ORs with delivery in-flight', () {
    final store = ChatTabStore();
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final working = aggregator(
      store: store,
      attention: (id) => id == 'sess',
      deliveryInFlight: (_) => false,
    ).compute();
    expect(working, {'sess'});
  });
}
