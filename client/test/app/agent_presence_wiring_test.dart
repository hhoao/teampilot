import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level pins for the presence-events app-shell wiring.
///
/// The full bootstrap path is not widget-testable: `buildAppShell` wires the
/// entire production app (storage, SSH, cubits) behind ~90 required AppShell
/// dependencies. So, like `app_shell_bootstrap_retry_test.dart`, the wiring is
/// pinned at the source level while its behaviour (one registration carrying
/// all three kinds) is covered by
/// `test/services/event/agent_presence_family_registration_test.dart`.
void main() {
  final src = File('lib/app/app_shell.dart').readAsStringSync();

  group('presence-events app-shell wiring', () {
    test('exactly one app-lifetime projection exists in lib/', () {
      final constructions = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        final count = RegExp(r'AgentPresenceProjection\(\)').allMatches(text).length;
        if (count > 0) constructions.add('${f.path}: $count');
      }
      expect(
        constructions,
        ['lib/app/app_shell.dart: 1'],
        reason:
            'the projection must be created once, by the bootstrap state '
            '(not per bootstrap retry)',
      );
      expect(
        RegExp(
          r'AgentPresenceProjection\s+_presenceProjection\s*=\s*AgentPresenceProjection\(\)',
        ).hasMatch(src),
        isTrue,
        reason: 'the single projection lives beside the app-lifetime dispatcher',
      );
    });

    test('one family registration covers the whole AgentPresenceKind family', () {
      expect(
        RegExp(
          r'registerFamily<AgentPresenceKind>\s*\(\s*AgentPresenceKind\.working\.runtimeType',
        ).hasMatch(src),
        isTrue,
        reason:
            'routing keys on event.eventKind.runtimeType, so one registration '
            'per family (keyed by any member) covers booting/working/idle',
      );
    });

    test('projection and sink are threaded from the state into the cubit', () {
      // State -> buildAppShell.
      expect(src.contains('presenceProjection: _presenceProjection,'), isTrue);
      expect(src.contains('presenceSink: _presenceSink,'), isTrue);
      expect(
        src.contains('DispatcherAgentPresenceSink(') &&
            src.contains('_eventDispatcher,'),
        isTrue,
        reason: 'the sink publishes onto the same app-lifetime dispatcher',
      );
      // buildAppShell -> MemberPresenceCubit (bridge built per shell, so the
      // discarded-shell teardown can dispose it without killing a shared edge).
      expect(src.contains('presenceProjection: presenceProjection,'), isTrue);
      expect(src.contains('PresenceEventBridge(sink: presenceSink)'), isTrue);
    });

    test('dispose closes the projection only after the dispatcher drains', () {
      expect(
        RegExp(
          r'_eventDispatcher\.stop\(\)\.then\(\(_\) => _presenceProjection\.close\(\)\)',
        ).hasMatch(src),
        isTrue,
        reason:
            'stop() resolves after the consume loop drains, so chaining keeps '
            'the close strictly after the last delivery',
      );
    });

    test('ssh home does not construct PresenceEventBridge', () {
      expect(
        src.contains('connectionModeService.isSshMode'),
        isTrue,
      );
      expect(
        RegExp(
          r'presenceBridge:\s*presenceSink == null\s*\|\|\s*connectionModeService\.isSshMode',
        ).hasMatch(src),
        isTrue,
        reason: 'consumer-only ssh home must not publish presence back',
      );
    });

    test('home swap rebinds the presence producer via setPresenceBridge', () {
      expect(
        src.contains('setPresenceBridge'),
        isTrue,
        reason:
            'reloadAllAppData does not recreate the cubit; applyHomeEventTransport '
            'must replace the producer edge when the home role changes',
      );
    });
  });
}
