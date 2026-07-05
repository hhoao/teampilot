import '../../cubits/launch_profile_cubit.dart';
import '../../models/discoverable_member.dart';
import '../team/team_clone_service.dart';

class MemberAddResult {
  const MemberAddResult({
    required this.memberId,
    required this.installedSkillIds,
    required this.failedDeps,
  });

  final String memberId;
  final List<String> installedSkillIds;
  final List<DependencyFailure> failedDeps;

  bool get hasFailures => failedDeps.isNotEmpty;
}

class MemberAddException implements Exception {
  MemberAddException(this.message);
  final String message;
  @override
  String toString() => 'MemberAddException: $message';
}

/// Adds a [DiscoverableMember] to an existing team: installs skill deps (each
/// failure is non-blocking) then persists via [LaunchProfileCubit.addMemberToTeam].
class MemberCloneService {
  MemberCloneService({required this.installSkill});

  final SkillDepInstaller installSkill;

  Future<MemberAddResult> addToTeam({
    required String teamId,
    required DiscoverableMember member,
    required LaunchProfileCubit launchProfiles,
    void Function(CloneProgress)? onProgress,
  }) async {
    final failed = <DependencyFailure>[];
    final total = member.skillDeps.length;
    var done = 0;

    void progress(String msg) {
      done++;
      onProgress?.call(CloneProgress(msg, done, total));
    }

    final installedSkillIds = <String>[];
    for (final dep in member.skillDeps) {
      final id = await installSkill(dep);
      if (id != null) {
        installedSkillIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.skill, dep.name));
      }
      progress(dep.name);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final config = member.toMemberConfig(joinedAt: now);

    final added = await launchProfiles.addMemberToTeam(teamId, config);
    if (added == null) {
      throw MemberAddException(
        'failed to add "${member.name}" to team $teamId',
      );
    }

    return MemberAddResult(
      memberId: added.id,
      installedSkillIds: installedSkillIds,
      failedDeps: failed,
    );
  }
}
