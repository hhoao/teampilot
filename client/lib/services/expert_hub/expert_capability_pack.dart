import '../../models/config_bundle.dart';
import '../../models/team_config.dart';
import '../team/team_clone_service.dart';

/// Resolved expert capability pack: persona + installed global-library ids.
class ExpertCapabilityPack {
  const ExpertCapabilityPack({
    required this.member,
    required this.bundle,
    this.failedDeps = const [],
  });

  final TeamMemberConfig member;
  final ConfigBundle bundle;
  final List<DependencyFailure> failedDeps;

  bool get hasFailures => failedDeps.isNotEmpty;
}
