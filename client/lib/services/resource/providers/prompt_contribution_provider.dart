import 'dart:async';

import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/workspace_base_info_capability.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../contribution/prompt_document.dart';

/// Focused inputs needed by prompt providers.
class PromptProviderContext {
  PromptProviderContext({
    required this.cli,
    this.scope,
    this.member,
    this.forceTeamLeadDelegateMode = false,
    this.mixed = false,
    this.pushDelivery = false,
    Iterable<String> additionalDirectories = const [],
    this.memberHome,
    this.sourceId,
    this.workspaceBaseInfo = WorkspaceBaseInfoPromptInputs.empty,
  }) : additionalDirectories = List.unmodifiable(additionalDirectories);

  final CliTool cli;
  final LaunchProfileScope? scope;
  final TeamMemberConfig? member;
  final bool forceTeamLeadDelegateMode;
  final bool mixed;
  final bool pushDelivery;
  final List<String> additionalDirectories;
  final String? memberHome;
  final String? sourceId;
  final WorkspaceBaseInfoPromptInputs workspaceBaseInfo;
}

/// Supplies prompt contributions without writing target configuration.
abstract interface class PromptContributionProvider {
  String get providerId;

  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext context);
}
