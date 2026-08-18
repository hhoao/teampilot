import 'dart:async';

import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/prompt_capability.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../contribution/resource_origin.dart';

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
  }) : additionalDirectories = List.unmodifiable(additionalDirectories);

  final CliTool cli;
  final LaunchProfileScope? scope;
  final TeamMemberConfig? member;
  final bool forceTeamLeadDelegateMode;
  final bool mixed;
  final bool pushDelivery;
  final List<String> additionalDirectories;
  final String? memberHome;
}

/// A target-neutral prompt contribution.
class PromptContribution {
  const PromptContribution({
    required this.id,
    required this.title,
    required this.content,
    this.scope = PromptScope.cli,
    this.mergeRole = PromptMergeRole.replace,
    required this.origin,
  });

  final String id;
  final String title;
  final String content;
  final PromptScope scope;
  final PromptMergeRole mergeRole;
  final ContributionOrigin origin;
}

/// Supplies prompt contributions without writing target configuration.
abstract interface class PromptContributionProvider {
  String get providerId;

  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext context);
}
