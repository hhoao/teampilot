import 'package:acpd/acpd.dart';

/// Sentinel returned when an agent error should become a Cancelled stop
/// reason instead of a surfaced error.
const String acpStopCancelled = '__acp_stop_cancelled__';

/// Sentinel returned when the agent reports ACP `auth_required` (-32000).
/// Cubit surfaces the generic not-logged-in copy instead of the raw RPC error.
const String acpStopAuthRequired = '__acp_stop_auth_required__';

/// Per-agent absorption of protocol quirks. One implementation per ACP CLI,
/// declared by its AcpCapability — never an if (cli == …) at call sites.
abstract class AcpAgentTranslator {
  const AcpAgentTranslator();

  /// Candidate ACP flags in preference order (probed at launch).
  List<String> get flagCandidates;

  /// Client JSON-RPC methods that block until the client replies.
  List<String> get blockingClientMethods;

  /// Client JSON-RPC methods sent as notifications (no reply).
  List<String> get notificationClientMethods;

  /// Map a prompt-phase error to a display string, or a sentinel
  /// ([acpStopCancelled] / [acpStopAuthRequired]).
  String translateStopError(Object error, {required bool suppressAbort});

  /// Wire JSON for `session/request_permission`.
  ///
  /// ACP nests the outcome: `{outcome: {outcome, optionId}}` (see
  /// `RequestPermissionResponse` in the ACP schema). Agents read the inner
  /// discriminator (`response.outcome.outcome`); a flat `{outcome, optionId}`
  /// reply decodes as "not selected", so the agent aborts the tool call with
  /// "Tool use aborted". acpd's `RequestPermissionResponse.toJson` flattens,
  /// hence the explicit wrap here.
  Map<String, Object?> encodePermissionResponse(
    RequestPermissionOutcome outcome,
  ) {
    return {'outcome': RequestPermissionResponse(outcome: outcome).toJson()};
  }
}
