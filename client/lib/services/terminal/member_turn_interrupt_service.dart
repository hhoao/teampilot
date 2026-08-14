import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../cli/registry/capabilities/terminal_behavior_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'terminal_session.dart';

typedef MemberPtyWriter = void Function(TerminalSession shell, String text);

/// Orchestrates per-member turn interrupt: abort pending inject, then PTY steps
/// from [TerminalBehaviorCapability].
final class MemberTurnInterruptService {
  MemberTurnInterruptService({
    required CliToolRegistry cliToolRegistry,
    required void Function(String sessionId, String memberId) abortMemberInject,
    Future<void> Function(Duration delay)? delay,
    MemberPtyWriter? writePty,
  }) : _cliToolRegistry = cliToolRegistry,
       _abortMemberInject = abortMemberInject,
       _delay = delay ?? Future<void>.delayed,
       _writePty = writePty ?? ((shell, text) => shell.input.writeToPty(text));

  final CliToolRegistry _cliToolRegistry;
  final void Function(String sessionId, String memberId) _abortMemberInject;
  final Future<void> Function(Duration delay) _delay;
  final MemberPtyWriter _writePty;

  Future<void> interrupt({
    required String sessionId,
    required String memberId,
    required TerminalSession? shell,
    required CliTool cli,
  }) async {
    if (shell == null || !shell.isConnected) {
      appLogger.d(
        '[turn-interrupt] skip $sessionId:$memberId — shell not connected',
      );
      return;
    }

    _abortMemberInject(sessionId, memberId);

    final cap = _cliToolRegistry.capability<TerminalBehaviorCapability>(cli);
    if (cap == null || !cap.supportsTurnInterrupt) {
      appLogger.d(
        '[turn-interrupt] skip $sessionId:$memberId — no turn interrupt for $cli',
      );
      return;
    }

    final plan = cap.interruptPlan;
    for (var i = 0; i < plan.steps.length; i++) {
      _writePty(shell, plan.steps[i]);
      final isLast = i == plan.steps.length - 1;
      if (!isLast && plan.gapBetweenSteps > Duration.zero) {
        await _delay(plan.gapBetweenSteps);
      }
    }
  }
}
