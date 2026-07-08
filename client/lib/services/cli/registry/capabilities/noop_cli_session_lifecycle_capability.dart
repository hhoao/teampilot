import 'cli_session_lifecycle_capability.dart';

/// Default lifecycle for CLIs without a tool-specific implementation.
final class NoopCliSessionLifecycleCapability
    implements CliSessionLifecycleCapability {
  const NoopCliSessionLifecycleCapability();

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
}
