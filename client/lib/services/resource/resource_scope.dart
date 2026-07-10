import 'package:path/path.dart' as p;

import '../../models/config_bundle.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';

/// Describes WHERE a launch is materializing resources to, and WHICH stored
/// enable lists are authoritative for it. Mode lives here and nowhere else.
sealed class ResourceScope {
  const ResourceScope();
}

/// Simple / unteamed mode: enable lists come from a merged [ConfigBundle]
/// (workspace + expert pack).
class SimpleResourceScope extends ResourceScope {
  const SimpleResourceScope({required this.bundle});
  final ConfigBundle bundle;
}

/// Native or mixed team mode: enable lists come from [TeamProfile].
/// Members inherit the team set (there is no per-member skill list), so
/// [member] is carried only for future per-kind needs.
class TeamResourceScope extends ResourceScope {
  const TeamResourceScope({required this.team, this.member});
  final TeamProfile team;
  final TeamMemberConfig? member;
}

/// Workspace project bindings from `project-config.json`.
class WorkspaceResourceScope extends ResourceScope {
  const WorkspaceResourceScope({required this.bundle});
  final ConfigBundle bundle;
}

/// Installed catalogs + source roots needed to turn enabled ids into refs.
/// Skills only for now; plugin/mcp fields are added by their follow-on plans.
class ResourceCatalog {
  const ResourceCatalog({
    required this.skills,
    required this.skillsRoot,
    required this.pathContext,
  });

  final List<Skill> skills;
  final String skillsRoot;
  final p.Context pathContext;
}
