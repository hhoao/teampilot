import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../cli_session_manifest_store.dart';
import 'cursor_session_lifecycle_paths.dart';

/// Cursor mixed-session lifecycle: warm tier, manifest phases, connect gate.
final class CursorSessionLifecycleCapability
    implements CliSessionLifecycleCapability {
  const CursorSessionLifecycleCapability({
    required CliSessionManifestStore manifestStore,
  }) : _manifestStore = manifestStore;

  final CliSessionManifestStore _manifestStore;

  /// Stable overlay generation from bus idle endpoint binding (port/token).
  static int overlayGenerationForBus(MemberBusIdleEndpoint? busIdle) {
    if (busIdle == null) return 0;
    final url = busIdle.url.trim();
    final token = busIdle.token?.trim() ?? '';
    final sessionId = busIdle.sessionId?.trim() ?? '';
    if (url.isEmpty && token.isEmpty && sessionId.isEmpty) return 0;
    return Object.hash(url, token, sessionId) & 0x7fffffff;
  }

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async =>
      const CliSessionPersistResult(phase: CliSessionPhase.persisted);

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async =>
      const CliSessionInitResult();

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) {
    final manifest = _manifestStore.peek(
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) {
      return const CliSessionGateDecision(allowed: false, reason: 'manifest');
    }

    final member = manifest.members[ctx.memberId];
    final expectedOverlay = overlayGenerationForBus(ctx.busIdle);
    if (member != null && member.overlayGeneration != expectedOverlay) {
      return const CliSessionGateDecision(allowed: false, reason: 'overlay');
    }

    switch (manifest.phase) {
      case CliSessionPhase.ready:
        return const CliSessionGateDecision(allowed: true);
      case CliSessionPhase.degraded:
        return const CliSessionGateDecision(allowed: true);
      case CliSessionPhase.indexing:
        final leader = manifest.index.leaderMemberId;
        if (leader != null && leader == ctx.memberId) {
          return const CliSessionGateDecision(allowed: true);
        }
        return const CliSessionGateDecision(
          allowed: false,
          reason: 'indexing',
        );
      default:
        return CliSessionGateDecision(
          allowed: false,
          reason: manifest.phase.name,
        );
    }
  }
}
