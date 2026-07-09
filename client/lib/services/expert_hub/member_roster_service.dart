import '../../cubits/launch_profile_cubit.dart';
import '../../models/discoverable_member.dart';
import '../team/team_clone_service.dart';

class MemberAddResult {
  const MemberAddResult({
    required this.memberId,
    required this.expertKey,
    required this.installedSkillIds,
    required this.failedDeps,
  });

  final String memberId;
  final String expertKey;
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

/// Adds an expert **reference** to an existing team roster (no persona copy).
class MemberRosterService {
  MemberRosterService({required this.installSkill});

  final SkillDepInstaller installSkill;

  Future<MemberAddResult> addExpertToTeam({
    required String teamId,
    required DiscoverableMember expert,
    required LaunchProfileCubit launchProfiles,
    void Function(CloneProgress)? onProgress,
  }) async {
    final failed = <DependencyFailure>[];
    final total = expert.skillDeps.length;
    var done = 0;

    void progress(String msg) {
      done++;
      onProgress?.call(CloneProgress(msg, done, total));
    }

    final installedSkillIds = <String>[];
    for (final dep in expert.skillDeps) {
      final id = await installSkill(dep);
      if (id != null) {
        installedSkillIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.skill, dep.name));
      }
      progress(dep.name);
    }

    final added = await launchProfiles.addExpertToTeam(
      teamId,
      expert.key,
      slotIdHint: expert.member.name,
    );
    if (added == null) {
      throw MemberAddException(
        'failed to add "${expert.name}" to team $teamId',
      );
    }

    return MemberAddResult(
      memberId: added.id,
      expertKey: expert.key,
      installedSkillIds: installedSkillIds,
      failedDeps: failed,
    );
  }
}
