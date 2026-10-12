import '../../../acp/acp_agent_translator.dart';
import '../cli_capability.dart';

/// Credential source injected at construction (tests pass fakes; production
/// wires the credential store). Returning null means "no key configured" and
/// the ACP env simply omits it.
typedef AcpCredentialSource = String? Function();

/// Declares how a CLI is launched as an ACP agent.
///
/// Each ACP-capable CLI exposes: the argv candidates to probe (preference
/// order — the runtime tries the first, falls back on failure), its
/// per-agent translator, and the isolated environment for the agent process.
abstract interface class AcpCapability implements CliCapability {
  /// Binary that speaks ACP on stdio. Gemini returns [cliExecutable].
  String agentExecutable(String cliExecutable);

  /// Full argv candidates (executable + one ACP flag each), probe order.
  List<List<String>> launchArgCandidates(String executable);

  /// Per-agent absorption of ACP protocol quirks.
  AcpAgentTranslator get translator;

  /// ACP `authenticate` methodId after initialize, or null to skip.
  String? get authenticateMethodId;

  /// Spawn-time authenticate method. Default: [authenticateMethodId].
  ///
  /// Cursor returns null when isolated-home `auth.json` already has tokens.
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  /// Env for the agent process: [baseEnv] preserved plus isolated config
  /// dir, injected credentials, and surface identification.
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv,
  });
}
