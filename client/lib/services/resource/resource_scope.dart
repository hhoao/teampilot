import 'package:path/path.dart' as p;

import '../../models/config_bundle.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';

/// Describes WHERE a launch is materializing resources to, and WHICH stored
/// enable lists are authoritative for it. Mode lives here and nowhere else.
sealed class ResourceScope {
  const ResourceScope();

  List<String> get skillIds;

  List<String> get pluginIds;
}

/// Simple / unteamed mode: enable lists come from a merged [ConfigBundle]
/// (workspace + expert pack).
class SimpleResourceScope extends ResourceScope {
  const SimpleResourceScope({required this.bundle});
  final ConfigBundle bundle;

  @override
  List<String> get skillIds => bundle.skillIds;

  @override
  List<String> get pluginIds => bundle.pluginIds;
}

/// Native or mixed team mode: enable lists come from [TeamProfile].
/// Members inherit the team set (there is no per-member skill list), so
/// [member] is carried only for future per-kind needs.
class TeamResourceScope extends ResourceScope {
  const TeamResourceScope({required this.team, this.member});
  final TeamProfile team;
  final TeamMemberConfig? member;

  @override
  List<String> get skillIds => team.skillIds;

  @override
  List<String> get pluginIds => team.pluginIds;
}

/// Workspace project bindings from `project-config.json`.
class WorkspaceResourceScope extends ResourceScope {
  const WorkspaceResourceScope({required this.bundle});
  final ConfigBundle bundle;

  @override
  List<String> get skillIds => bundle.skillIds;

  @override
  List<String> get pluginIds => bundle.pluginIds;
}

/// Installed catalogs + source roots needed by resource contribution providers.
class ResourceCatalog {
  const ResourceCatalog({
    required this.skills,
    required this.skillsRoot,
    required this.pathContext,
    this.plugins = const [],
    this.pluginsRoot,
  });

  final List<Skill> skills;
  final String skillsRoot;
  final p.Context pathContext;
  final List<Plugin> plugins;
  final String? pluginsRoot;
}
