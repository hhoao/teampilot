import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/member_state.dart';
import 'package:teampilot/services/team_bus/state/bus_effect.dart';
import 'package:teampilot/services/team_bus/state/bus_event.dart';
import 'package:teampilot/services/team_bus/state/presence.dart';
import 'package:teampilot/services/team_bus/state/presence_reducer.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

PresenceTransition _run(
  Presence s,
  BusEvent e, {
  bool hasUnread = false,
  bool doorbelled = false,
}) =>
    PresenceReducer.reduce(
      s,
      e,
      PresenceContext(
        memberId: 'm',
        hasUnread: hasUnread,
        doorbelled: doorbelled,
      ),
    );

const _declared = Presence.declared();
const _atPrompt =
    Presence(MemberLifecycle.running, MemberActivity.turnDoneReady);
const _active = Presence(MemberLifecycle.running, MemberActivity.active);
const _parked =
    Presence(MemberLifecycle.running, MemberActivity.turnDoneBusWait);

void main() {
  test('PtySpawned → running + turnDoneReady, no effect', () {
    final t = _run(_declared, const PtySpawned());
    expect(t.presence, _atPrompt);
    expect(t.effects, isEmpty);
  });

  test('MaterializeStarted from declared → materializing + Materialize effect', () {
    final msg = TeamMessage(id: '1', from: 'l', to: 'm', content: 'go');
    final t = _run(_declared, MaterializeStarted(msg));
    expect(t.presence.lifecycle, MemberLifecycle.materializing);
    expect(t.effects.single, isA<MaterializeEffect>());
    expect((t.effects.single as MaterializeEffect).bootstrap, msg);
  });

  test('MaterializeStarted is a no-op when not declared', () {
    final t = _run(_active, MaterializeStarted(
      TeamMessage(id: '1', from: 'l', to: 'm', content: 'go'),
    ));
    expect(t.presence, _active);
    expect(t.effects, isEmpty);
  });

  test('MaterializeCompleted → running + active + Doorbell', () {
    final t = _run(
      const Presence(MemberLifecycle.materializing, MemberActivity.active),
      const MaterializeCompleted(),
    );
    expect(t.presence, _active);
    expect(t.effects.single, isA<DoorbellEffect>());
  });

  group('MailArrived', () {
    test('declared + unread → mailQueued, no doorbell', () {
      final t = _run(_declared, const MailArrived(), hasUnread: true);
      expect(t.presence.activity, MemberActivity.mailQueued);
      expect(t.effects, isEmpty);
    });

    test('parked → no doorbell (waiter delivers)', () {
      final t = _run(_parked, const MailArrived(eager: true), hasUnread: true);
      expect(t.presence, _parked);
      expect(t.effects, isEmpty);
    });

    test('non-eager + at-prompt → doorbell, stays at prompt', () {
      final t = _run(_atPrompt, const MailArrived(), hasUnread: true);
      expect(t.presence, _atPrompt);
      expect(t.effects.single, isA<DoorbellEffect>());
    });

    test('non-eager + active (mid-turn) → no doorbell (do not interrupt)', () {
      final t = _run(_active, const MailArrived(), hasUnread: true);
      expect(t.presence, _active);
      expect(t.effects, isEmpty);
    });

    test('eager + active (mid-turn) → doorbell', () {
      final t = _run(_active, const MailArrived(eager: true), hasUnread: true);
      expect(t.effects.single, isA<DoorbellEffect>());
    });

    test('no unread → no doorbell', () {
      final t = _run(_atPrompt, const MailArrived(eager: true));
      expect(t.effects, isEmpty);
    });

    test('non-eager + at-prompt but already doorbelled → no re-ring', () {
      // Back-to-back messages to an idle worker that has not yet consumed must
      // not inject a second "go read_messages" notice (the duplicate the user
      // sees). Lost-CR redelivery is the watchdog's job, not a re-ring per msg.
      final t =
          _run(_atPrompt, const MailArrived(), hasUnread: true, doorbelled: true);
      expect(t.presence, _atPrompt);
      expect(t.effects, isEmpty);
    });

    test('eager overrides doorbelled suppression', () {
      // idle-notify / explicit user command still ring even if already nudged.
      final t = _run(_atPrompt, const MailArrived(eager: true),
          hasUnread: true, doorbelled: true);
      expect(t.effects.single, isA<DoorbellEffect>());
    });
  });

  group('wait lifecycle', () {
    test('WaitEntered while running → parked', () {
      expect(_run(_atPrompt, const WaitEntered()).presence, _parked);
    });
    test('WaitEntered while declared → no change', () {
      expect(_run(_declared, const WaitEntered()).presence, _declared);
    });
    test('WaitExited from parked → active', () {
      expect(_run(_parked, const WaitExited()).presence, _active);
    });
  });

  group('TurnEnded', () {
    test('running + no unread → turnDoneReady, no doorbell', () {
      final t = _run(_active, const TurnEnded());
      expect(t.presence, _atPrompt);
      expect(t.effects, isEmpty);
    });
    test('running + unread → turnDoneReady, doorbell via onMemberIdle mail path',
        () {
      final t = _run(_active, const TurnEnded(), hasUnread: true);
      expect(t.presence, _atPrompt);
      expect(t.effects, isEmpty);
    });
    test('running + unread but already doorbelled → idle, no re-ring', () {
      final t = _run(_active, const TurnEnded(),
          hasUnread: true, doorbelled: true);
      expect(t.presence, _atPrompt);
      expect(t.effects, isEmpty);
    });
    test('parked → no change (guarded)', () {
      expect(_run(_parked, const TurnEnded(), hasUnread: true).presence, _parked);
    });
  });
}
