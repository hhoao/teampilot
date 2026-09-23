import '../../agent_status/agent_attention_port.dart';
import '../../../models/team_config.dart';

/// Seat identity passed into [TerminalSession.connect] so observation modules
/// and CLI contributors can bind without the session knowing any [CliTool] UI.
final class TerminalObservationAttach {
  const TerminalObservationAttach({
    required this.sessionId,
    required this.memberId,
    this.cli,
    this.attention,
    this.skipPermissions,
  });

  final String sessionId;
  final String memberId;
  final CliTool? cli;
  final AgentAttentionPort? attention;
  final bool Function()? skipPermissions;
}
