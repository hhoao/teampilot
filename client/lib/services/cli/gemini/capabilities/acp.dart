import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';

/// Gemini absorption of ACP protocol quirks (part 1: translator + probe).
///
/// Mirrors Zed's workaround for gemini-cli#6656: gemini-cli surfaces user
/// aborts as JSON-RPC internal errors (`-32603`) whose `data.details` (or
/// message) carries one of two abort phrases. While that upstream bug is
/// open, translate those errors to [acpStopCancelled] so a user-initiated
/// stop is reported as Cancelled rather than a surfaced error.
final class GeminiAcpTranslator implements AcpAgentTranslator {
  const GeminiAcpTranslator();

  @override
  List<String> get flagCandidates => const ['--acp', '--experimental-acp'];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      if (suppressAbort && _isAbortInternalError(error)) {
        return acpStopCancelled;
      }
      return 'ACP error ${error.code}: ${error.message}'
          '${error.data == null ? '' : ' ${error.data}'}';
    }
    return error.toString();
  }

  /// Whether [error] is the gemini-cli abort-shaped internal error.
  static bool _isAbortInternalError(RpcError error) {
    if (error.code != ErrorCode.internalError.code) return false;
    final data = error.data;
    final details = data is Map ? '${data['details']}' : '';
    return error.message.contains(_abortPhraseA) ||
        error.message.contains(_abortPhraseB) ||
        details.contains(_abortPhraseA) ||
        details.contains(_abortPhraseB);
  }

  static const _abortPhraseA = 'This operation was aborted';
  static const _abortPhraseB = 'The user aborted a request';
}
