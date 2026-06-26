import '../../models/cli_preset.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';

/// Resolved personal identity + preset + stand-in member for session launch.
class PersonalLaunchContext {
  const PersonalLaunchContext({
    required this.personalIdentity,
    required this.personalPreset,
    required this.personalMember,
  });

  final PersonalProfile personalIdentity;
  final CliPreset? personalPreset;
  final TeamMemberConfig personalMember;
}
