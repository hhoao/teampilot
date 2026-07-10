import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

MemberRosterService stubMemberRosterService({
  SkillDepInstaller? installSkill,
  PluginDepInstaller? installPlugin,
  McpDepInstaller? installMcp,
}) => MemberRosterService(
  resolver: ExpertCapabilityResolver(
    installSkill: installSkill ?? (_) async => null,
    installPlugin: installPlugin ?? (_) async => null,
    installMcp: installMcp ?? (_) async => null,
  ),
);
