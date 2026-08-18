import 'dart:async';

import '../../../models/hook_entry.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../../io/filesystem.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by hook providers.
class HookProviderContext {
  HookProviderContext({
    required this.cli,
    this.member,
    Map<String, String> endpoints = const {},
    this.filesystem,
    this.hooksDirectory,
    this.scope,
  }) : endpoints = Map.unmodifiable(endpoints);

  final CliTool cli;
  final TeamMemberConfig? member;
  final Map<String, String> endpoints;
  final Filesystem? filesystem;
  final String? hooksDirectory;
  final LaunchProfileScope? scope;
}

/// A hook entry plus the provenance needed for diagnostics and deduplication.
class HookContribution {
  const HookContribution({
    required this.sourceId,
    required this.entry,
    required this.origin,
  });

  final String sourceId;
  final HookEntry entry;
  final ContributionOrigin origin;
}

/// Supplies hook contributions without writing target configuration.
abstract interface class HookContributionProvider {
  String get providerId;

  FutureOr<Iterable<HookContribution>> provide(HookProviderContext context);
}
