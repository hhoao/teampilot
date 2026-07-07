import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/built_in_tool_capabilities.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_input_screen_probe.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_automation.dart';
import 'package:teampilot/services/terminal/fullscreen_pty_delivery_port.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_fullscreen_pty_delivery_port.dart';

void main() {
  final timing = PtyAutomationTiming.instant();
  final automation = FullscreenPtyAutomation(timing: timing);

  group('deliverPasteAndSubmit', () {
    test('pastes, submits CR, and returns submitted', () async {
      final port = FakeFullscreenPtyDeliveryPort();
      const text = '[teammate-bus] read_messages now';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 1);
      expect(port.crCount, greaterThanOrEqualTo(1));
      expect(port.staged, isNull);
    });

    test('reinjects when paste is not found on grid', () async {
      final port = FakeFullscreenPtyDeliveryPort(pastesBeforeVisible: 2);
      const text = '和你的队员打个招呼吧';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 2);
    });

    test('returns pasteNotFound when needle never appears', () async {
      final port = FakeFullscreenPtyDeliveryPort(visibleAfterPaste: false);
      const text = 'never lands';

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: text,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
    });

    test('accepts cursor submit when transcript keeps the submitted text', () async {
      final port = _CursorTranscriptAfterSubmitPort();

      final outcome = await automation.deliverPasteAndSubmit(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(
        outcome,
        FullscreenPtyDeliveryOutcome.submitted,
        reason:
            'cursor keeps the submitted prompt visible as transcript history '
            'and paints a fresh composer below it',
      );
    });
  });

  group('nudgeCrUntilClear', () {
    test('submits CR when text already visible', () async {
      final port = FakeFullscreenPtyDeliveryPort()..staged = TeamBus.doorbellNotice;

      final outcome = await automation.nudgeCrUntilClear(
        port: port,
        text: TeamBus.doorbellNotice,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 0);
      expect(port.crCount, 1);
    });

    test('returns pasteNotFound when text absent', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.nudgeCrUntilClear(
        port: port,
        text: TeamBus.doorbellNotice,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.pasteNotFound);
    });
  });

  group('retry', () {
    test('repastes when text not visible', () async {
      final port = FakeFullscreenPtyDeliveryPort();

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 1);
    });

    test('nudges CR when text already visible', () async {
      final port = FakeFullscreenPtyDeliveryPort()
        ..staged = TeamBus.doorbellNotice;

      final outcome = await automation.retry(
        port: port,
        text: TeamBus.doorbellNotice,
        pasteSettle: Duration.zero,
      );

      expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
      expect(port.pasteCount, 0);
      expect(port.crCount, 1);
    });
  });

  test('isTextVisible uses PtyAutomationNeedle', () {
    final port = FakeFullscreenPtyDeliveryPort()
      ..staged = '和你的队员打个招呼吧';
    expect(
      automation.isTextVisible(port, '和你的队员打个招呼吧'),
      isTrue,
    );
  });
}

final class _CursorTranscriptAfterSubmitPort
    implements FullscreenPtyDeliveryPort {
  String? _staged;
  bool _submitted = false;
  int crCount = 0;

  @override
  bool get isAborted => false;

  @override
  int get viewportRows => 24;

  @override
  FullscreenCrAckConfig get crAckConfig => FullscreenCrAckConfig(
    strategy: const CursorTerminalBehavior().fullscreenCrAckStrategy,
    composerPrefix: const CursorTerminalBehavior().fullscreenComposerPrefix,
  );

  @override
  Future<void> syncDisplayGrid() async {}

  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) {
    if (_staged == null || !_staged!.contains(needle)) return null;
    return FullscreenPromptAnchor(
      row: 0,
      startCol: _staged!.indexOf(needle),
      needle: needle,
    );
  }

  @override
  bool isAtAnchor(FullscreenPromptAnchor anchor) {
    return _staged != null && _staged!.contains(anchor.needle);
  }

  @override
  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24}) {
    if (!_submitted) return false;
    return switch (crAckConfig.strategy) {
      FullscreenCrAckStrategy.timed => true,
      FullscreenCrAckStrategy.anchorCellClears => !isAtAnchor(anchor),
      FullscreenCrAckStrategy.composerMovesDown =>
        crAckConfig.composerPrefix == '→',
    };
  }

  @override
  Future<void> clearStagedInput() async {
    _staged = null;
    _submitted = false;
  }

  @override
  Future<void> pasteText(String text) async {
    _staged = text;
    _submitted = false;
  }

  @override
  Future<void> submitCr() async {
    crCount++;
    _submitted = true;
  }

  @override
  String describeProbeWindow({int scanRows = 24}) {
    return _submitted
        ? '$_staged\n→ '
        : (_staged == null ? '<empty>' : '→ $_staged');
  }
}
