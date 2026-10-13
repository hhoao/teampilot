import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

/// Gemini absorption of ACP protocol quirks (part 1: translator + probe).
///
/// Mirrors Zed's workaround for gemini-cli#6656: gemini-cli surfaces user
/// aborts as JSON-RPC internal errors (`-32603`) whose `data.details` (or
/// message) carries one of two abort phrases. While that upstream bug is
/// open, translate those errors to [acpStopCancelled] so a user-initiated
/// stop is reported as Cancelled rather than a surfaced error.
final class GeminiAcpTranslator extends AcpAgentTranslator {
  const GeminiAcpTranslator();

  @override
  List<String> get flagCandidates => const ['--acp', '--experimental-acp'];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

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

/// Gemini's ACP launch/env declaration (part 2: capability).
///
/// Launch probes `--acp` first, falling back to `--experimental-acp`
/// (gemini-cli renamed the flag); the agent process gets
/// `GEMINI_CONFIG_DIR` equal to the session tool dir (same slot as PTY
/// `contributeLaunch`), an injected `GEMINI_API_KEY` when
/// [credentialSource] yields one, and `SURFACE=teampilot` for upstream
/// telemetry attribution.
final class GeminiAcpCapability implements AcpCapability {
  const GeminiAcpCapability({AcpCredentialSource? credentialSource})
    : _credentialSource = credentialSource;

  final AcpCredentialSource? _credentialSource;

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    for (final flag in translator.flagCandidates) [executable, flag],
  ];

  @override
  AcpAgentTranslator get translator => const GeminiAcpTranslator();

  @override
  String? get authenticateMethodId => null;

  @override
  bool get forwardSessionNewMcpServers => true;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    // Same slot as PTY contributeLaunch: sessionRuntimeToolDir is already
    // `…/runtime/gemini`, so do not nest another `/gemini`.
    env['GEMINI_CONFIG_DIR'] = sessionToolDir;
    final key = _credentialSource?.call();
    if (key != null) {
      env['GEMINI_API_KEY'] = key;
    }
    env['SURFACE'] = 'teampilot';
    return env;
  }
}
