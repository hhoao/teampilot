import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/hook_entry.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../../io/filesystem.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by hook providers.
@immutable
class HookProviderContext {
  HookProviderContext({
    required this.cli,
    this.member,
    Map<String, String> endpoints = const {},
    this.filesystem,
    this.hooksDirectory,
    this.scope,
    this.sourceId,
  }) : endpoints = Map.unmodifiable(endpoints);

  final CliTool cli;
  final TeamMemberConfig? member;
  final Map<String, String> endpoints;
  final Filesystem? filesystem;
  final String? hooksDirectory;
  final LaunchProfileScope? scope;
  final String? sourceId;
}

/// A hook entry plus the provenance needed for diagnostics and deduplication.
@immutable
class HookContribution {
  HookContribution({
    required this.sourceId,
    required this.entry,
    required this.origin,
    int? effectiveLayer,
  }) : effectiveLayer = effectiveLayer ?? hookContributionLayer(origin.kind);

  final String sourceId;
  final HookEntry entry;
  final ContributionOrigin origin;
  final int effectiveLayer;
}

/// Stable precedence values used only for hook diagnostics and provenance.
/// Hook identity conflicts are never silently resolved by this value.
abstract final class HookContributionLayer {
  static const cliBuiltIn = 0;
  static const catalog = 1;
  static const plugin = 2;
  static const extension = 2;
  static const workspace = 3;
  static const expert = 4;
  static const team = 5;
  static const managed = 6;
}

int hookContributionLayer(ResourceOriginKind kind) => switch (kind) {
  ResourceOriginKind.cliBuiltIn => HookContributionLayer.cliBuiltIn,
  ResourceOriginKind.catalog => HookContributionLayer.catalog,
  ResourceOriginKind.plugin => HookContributionLayer.plugin,
  ResourceOriginKind.extension => HookContributionLayer.extension,
  ResourceOriginKind.workspace => HookContributionLayer.workspace,
  ResourceOriginKind.expert => HookContributionLayer.expert,
  ResourceOriginKind.team => HookContributionLayer.team,
  ResourceOriginKind.managed => HookContributionLayer.managed,
};

/// Supplies hook contributions without writing target configuration.
abstract interface class HookContributionProvider {
  String get providerId;

  FutureOr<Iterable<HookContribution>> provide(HookProviderContext context);
}

/// Optional sources (currently extensions and plugins) may fail closed locally
/// while allowing required user and managed hooks to continue to materialize.
abstract interface class HookContributionProviderOptional {
  bool get optional;
}

/// Optional diagnostics emitted while a provider reads and filters its source.
abstract interface class HookContributionProviderDiagnostics {
  List<ResourceAssemblyDiagnostic> get diagnostics;
}
