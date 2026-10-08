import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/services/team_config/team_clone_service.dart';
import 'in_memory_filesystem.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/storage/app_paths.dart';

MemberRosterService stubMemberRosterService({
  SkillDepInstaller? installSkill,
  PluginDepInstaller? installPlugin,
  McpDepInstaller? installMcp,
}) => MemberRosterService(
  resolver: ExpertCapabilityResolver(
    installSkill: installSkill ?? (_) async => null,
    installPlugin: installPlugin ?? (_) async => null,
    installMcp: installMcp ?? (_) async => null,
    localStore: LocalExpertStore(
      fs: InMemoryFilesystem(),
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
    ),
  ),
);
