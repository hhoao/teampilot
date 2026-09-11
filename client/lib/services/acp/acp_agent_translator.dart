/// Sentinel returned when an agent error should become a Cancelled stop
/// reason instead of a surfaced error.
const String acpStopCancelled = '__acp_stop_cancelled__';

/// Per-agent absorption of protocol quirks. One implementation per ACP CLI,
/// declared by its AcpCapability — never an if (cli == …) at call sites.
abstract interface class AcpAgentTranslator {
  /// Candidate ACP flags in preference order (probed at launch).
  List<String> get flagCandidates;

  /// Map a prompt-phase error to a display string, or [acpStopCancelled].
  String translateStopError(Object error, {required bool suppressAbort});
}
