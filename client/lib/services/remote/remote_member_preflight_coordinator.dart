import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import 'remote_preflight_service.dart';

/// Decides whether a member runs on a machine **other than home** and, if so,
/// runs [RemotePreflightService] before launch (P3c §3.5 接入点). Members on
/// home / home-ssh (covered by P3b) return null → the existing launch path is
/// used unchanged.
class RemoteMemberPreflightCoordinator {
  RemoteMemberPreflightCoordinator({
    required this.preflight,
    required this.homeTarget,
    required this.isCredentialOptIn,
  });

  final RemotePreflightService preflight;

  /// The device-local home target (control plane). A member whose work target is
  /// this target — or a non-ssh local target — is *not* off-home.
  final RuntimeTarget Function() homeTarget;

  /// Per-target credential push opt-in (from `targets.json`).
  final Future<bool> Function(String targetId) isCredentialOptIn;

  /// A member is off-home when it runs on an ssh machine that is not the home
  /// target (home-ssh members share the home machine → not off-home).
  bool isOffHome(RuntimeTarget memberTarget) {
    if (memberTarget.kind != RuntimeKind.ssh) return false;
    return memberTarget.id != homeTarget().id;
  }

  /// Runs preflight when [memberTarget] is off-home; otherwise returns null (the
  /// caller keeps the existing local / home-ssh launch path).
  Future<PreflightResult?> prepareIfOffHome({
    required RuntimeTarget memberTarget,
    required CliTool cli,
    required String workspaceId,
    required String memberId,
    PreflightProgress? onProgress,
  }) async {
    if (!isOffHome(memberTarget)) return null;
    final optIn = await isCredentialOptIn(memberTarget.id);
    return preflight.prepare(
      target: memberTarget,
      cli: cli,
      workspaceId: workspaceId,
      memberId: memberId,
      optInCredentials: optIn,
      onProgress: onProgress,
    );
  }
}
