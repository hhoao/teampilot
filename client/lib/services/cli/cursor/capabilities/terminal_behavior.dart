import 'dart:typed_data';

import '../../../agent_status/agent_attention_state.dart';
import '../../../agent_status/agent_status_event.dart';
import '../../../terminal/fullscreen_cr_ack_config.dart';
import '../../../terminal/fullscreen_input_readiness.dart';
import '../../../terminal/observation/terminal_observation_bus.dart';
import '../../../terminal/observation/terminal_observation_events.dart';
import '../../../terminal/observation/terminal_observation_seat.dart';
import '../../../terminal/terminal_color_scheme_report.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/terminal_observation_contributor.dart';

/// Classifies Cursor PTY OSC titles into permission attention.
///
/// Bare native title `"Cursor Agent"` is a no-op (null) — cursor-agent re-emits
/// it constantly and it carries no permission signal. Titles containing
/// `action required` / `permission` / `waiting` map to [AgentSeatAttention.waiting].
AgentSeatAttention? detectCursorTitleAttention(String title) {
  if (title.isEmpty) return null;
  final trimmed = title.trim();
  if (trimmed.toLowerCase() == 'cursor agent') return null;

  final lower = trimmed.toLowerCase();
  if (lower.contains('action required') ||
      lower.contains('permission') ||
      lower.contains('waiting')) {
    return AgentSeatAttention.waiting;
  }
  return null;
}

/// True when [title] is cursor-agent's bare native OSC title (case-insensitive).
bool isCursorNativeTitle(String title) =>
    title.trim().toLowerCase() == 'cursor agent';

final class CursorTerminalBehavior
    implements TerminalBehaviorCapability, TerminalObservationContributor {
  const CursorTerminalBehavior();
  @override
  bool get supportsTurnInterrupt => true;
  @override
  TurnInterruptPlan get interruptPlan =>
      const TurnInterruptPlan(steps: ['\x03']);
  @override
  bool get usesFullScreenInput => true;
  @override
  Duration get fullScreenPasteSettleDelay => const Duration(milliseconds: 150);
  // Cursor echoes staged input, then keeps submitted text in transcript while
  // repainting a fresh composer below it; ACK on composer movement, not clear.
  @override
  bool get usesGridPasteAck => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
  @override
  FullscreenCrAckStrategy get fullscreenCrAckStrategy =>
      FullscreenCrAckStrategy.composerMovesDown;
  @override
  String? get fullscreenComposerPrefix => '→';
  @override
  FullscreenInputReadiness get inputReadiness =>
      const FullscreenInputReadiness(readyNeedles: ['→']);
  @override
  Duration get startupDeadline => const Duration(seconds: 45);

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    var titleWaiting = false;
    final titleSub = bus.subscribe<OscTitle>((event) {
      final attention = seat.attention;
      final skipPermissions = seat.skipPermissions;
      if (attention == null || skipPermissions == null) return;

      final title = event.title;
      // Bare native title is a no-op so per-turn re-emissions cannot clear sticky
      // waiting (Orca rule). Clear only on a non-native title that is not waiting.
      if (isCursorNativeTitle(title)) return;

      final classified = detectCursorTitleAttention(title);
      if (classified == AgentSeatAttention.waiting) {
        final skip = skipPermissions();
        attention.applyEvent(
          sessionId: seat.sessionId,
          memberId: seat.memberId,
          event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
          skipPermissions: skip,
        );
        if (!skip) titleWaiting = true;
        return;
      }

      if (titleWaiting) {
        attention.applyEvent(
          sessionId: seat.sessionId,
          memberId: seat.memberId,
          event: const AgentStatusEvent(state: AgentSeatAttention.done),
          skipPermissions: skipPermissions(),
        );
        titleWaiting = false;
      }
    });
    final transformSub = bus.addInputTransform(
      const _StripColorSchemeReportTransform(),
    );
    return CallbackObservationBinding(() {
      titleSub.cancel();
      transformSub.cancel();
    });
  }
}

final class _StripColorSchemeReportTransform implements TerminalInputTransform {
  const _StripColorSchemeReportTransform();

  @override
  int get order => 200;

  @override
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat) =>
      stripColorSchemeReport(bytes);
}
