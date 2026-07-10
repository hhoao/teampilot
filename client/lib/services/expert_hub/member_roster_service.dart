import '../../cubits/launch_profile_cubit.dart';
import '../../models/discoverable_member.dart';
import '../team/team_clone_service.dart';
import 'expert_capability_resolver.dart';

class MemberAddResult {
  const MemberAddResult({
    required this.memberId,
    required this.expertKey,
    required this.installedSkillIds,
    required this.installedPluginIds,
    required this.installedMcpServerIds,
    required this.failedDeps,
  });

  final String memberId;
  final String expertKey;
  final List<String> installedSkillIds;
  final List<String> installedPluginIds;
  final List<String> installedMcpServerIds;
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
  MemberRosterService({required ExpertCapabilityResolver resolver})
    : _resolver = resolver;

  final ExpertCapabilityResolver _resolver;

  Future<MemberAddResult> addExpertToTeam({
    required String teamId,
    required DiscoverableMember expert,
    required LaunchProfileCubit launchProfiles,
    void Function(CloneProgress)? onProgress,
  }) async {
    final total =
        expert.skillDeps.length +
        expert.pluginDeps.length +
        expert.mcpDeps.length;
    var done = 0;

    void progress(String msg) {
      done++;
      onProgress?.call(CloneProgress(msg, done, total));
    }

    final pack = await _resolver.resolve(
      expert,
      onDepProgress: progress,
    );

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
      installedSkillIds: pack.bundle.skillIds,
      installedPluginIds: pack.bundle.pluginIds,
      installedMcpServerIds: pack.bundle.mcpServerIds,
      failedDeps: pack.failedDeps,
    );
  }
}
