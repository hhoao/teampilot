import '../../../../models/team_config.dart';
import '../../../storage/runtime_layout.dart';
import '../../cli_tool_adapter.dart';
import 'cli_session_capability.dart';

/// Default session capability for CLIs without a tool-specific implementation.
base class NoopCliSessionCapability implements CliSessionCapability {
  const NoopCliSessionCapability();

  static const _ready = CliSessionPersistResult();
  static const _initReady = CliSessionInitResult();
  static const _allow = CliSessionGateDecision(allowed: true);

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async =>
      _ready;

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async =>
      _initReady;

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) => _allow;

  @override
  CliSessionPhase? peekSessionPhase(CliSessionGateContext ctx) => null;

  @override
  Future<void> afterManifestFlush(PostManifestFlushContext ctx) async {}

  @override
  List<String> buildArguments(CliLaunchContext context) => const [];

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => const DefaultCliConfigLayout().sessionConfigDir(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
}
