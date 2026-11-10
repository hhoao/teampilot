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

  /// Advertise `clientCapabilities._meta.subagents` during `initialize`.
  ///
  /// Cursor only keeps the prompt open — and runs a follow-up parent turn when
  /// a background child finishes — if the client negotiated this. Without it
  /// the parent turn ends as soon as the child is launched.
  bool get advertisesBackgroundSubagents => false;

  /// Map a prompt-phase error to a display string, or a sentinel
  /// ([acpStopCancelled] / [acpStopAuthRequired]).
  String translateStopError(Object error, {required bool suppressAbort});

  /// Map a non-error stop carrying agent-private `_meta` to a display string
  /// / sentinel, or null to keep the plain stop reason.
  ///
  /// CodeBuddy reports authentication failures as `stopReason: refusal` with
  /// `_meta["codebuddy.ai/errorMessage"]` instead of a JSON-RPC error.
  String? translateStopMeta(StopReason reason, Map<String, Object?> meta) =>
      null;

  /// True when this agent reports the end of a run it started on its own —
  /// e.g. the follow-up turn it drains for a finished background task. No
  /// client `session/prompt` request is open for that run, so without this
  /// report the out-of-turn watch cannot tell "the agent resumed" from "the
  /// agent is idle again".
  bool get reportsOutOfTurnRunEnd => false;

  /// Recognizes the CLI-private notification that ends such a run, returning
  /// its stop reason, or null when [update] is some other frame.
  ///
  /// [update] is the inner `session/update` payload (already unwrapped from
  /// `{sessionId, update}`).
  StopReason? translateOutOfTurnRunEnd(Map<String, Object?> update) => null;

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
