import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../storage/runtime_context.dart';
import '../team_bus/remote/member_bus_mcp_config.dart';

/// Stage labels surfaced via [PreflightProgress].
enum PreflightStage { connecting, locating, materializing, busBinding }

typedef PreflightProgress = void Function(PreflightStage stage, String message);

/// Connects to (or reuses) the work machine, returning its work-plane context.
typedef PreflightConnect = Future<RuntimeContext> Function(RuntimeTarget target);

/// Ensures the member's CLI is present on the work machine, returning its path.
typedef PreflightEnsureCli = Future<String> Function({
  required RuntimeTarget target,
  required CliTool cli,
  void Function(String message)? onCliProgress,
});

/// Materializes app-data (ancestry+skills/plugins+relay+(opt-in)creds) to the
/// work machine.
typedef PreflightMaterialize = Future<void> Function({
  required RuntimeTarget target,
  required RuntimeContext workContext,
  required CliTool cli,
  required String workspaceId,
  required bool optInCredentials,
});

/// Binds the member's bus over a reverse tunnel (P3b); null for non-coordinated.
typedef PreflightBindBus = Future<RemoteBusBinding?> Function({
  required RuntimeTarget target,
  required CliTool cli,
  required String memberId,
});

class PreflightResult {
  const PreflightResult({
    required this.remoteCliPath,
    required this.workContext,
    required this.busBinding,
  });
  final String remoteCliPath;
  final RuntimeContext workContext;
  final RemoteBusBinding? busBinding;
}

/// Thrown when the work machine can't be reached (connect stage).
class PreflightTargetUnavailableException implements Exception {
  PreflightTargetUnavailableException(this.target, this.cause);
  final RuntimeTarget target;
  final Object cause;
  @override
  String toString() =>
      'Work machine "${target.id}" is unavailable: $cause. The member cannot '
      'launch there (control plane / project list stay readable).';
}

/// Orchestrates the remote preflight checklist (P3c §3.5) for a member landing on
/// a machine **other than home**: connect → CLI ready → app-data materialize →
/// bus reachable. Strictly sequential — any step's failure short-circuits the
/// rest with a clear error. Steps are injected so the ordering/short-circuit is
/// unit-tested without real SSH (only the real step impls touch SSH on-device).
class RemotePreflightService {
  const RemotePreflightService({
    required this.connect,
    required this.ensureCli,
    required this.materialize,
    required this.bindBus,
  });

  final PreflightConnect connect;
  final PreflightEnsureCli ensureCli;
  final PreflightMaterialize materialize;
  final PreflightBindBus bindBus;

  Future<PreflightResult> prepare({
    required RuntimeTarget target,
    required CliTool cli,
    required String workspaceId,
    required String memberId,
    required bool optInCredentials,
    PreflightProgress? onProgress,
  }) async {
    onProgress?.call(PreflightStage.connecting, 'Connecting to ${target.id}');
    final RuntimeContext workContext;
    try {
      workContext = await connect(target);
    } on Object catch (e) {
      throw PreflightTargetUnavailableException(target, e);
    }

    onProgress?.call(PreflightStage.locating, 'Locating ${cli.value}');
    final remoteCliPath = await ensureCli(
      target: target,
      cli: cli,
      onCliProgress: (message) =>
          onProgress?.call(PreflightStage.locating, message),
    );

    onProgress?.call(PreflightStage.materializing, 'Materializing app data');
    await materialize(
      target: target,
      workContext: workContext,
      cli: cli,
      workspaceId: workspaceId,
      optInCredentials: optInCredentials,
    );

    onProgress?.call(PreflightStage.busBinding, 'Binding the bus');
    final busBinding =
        await bindBus(target: target, cli: cli, memberId: memberId);

    return PreflightResult(
      remoteCliPath: remoteCliPath,
      workContext: workContext,
      busBinding: busBinding,
    );
  }
}
