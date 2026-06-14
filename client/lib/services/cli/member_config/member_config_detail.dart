import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';

/// Which isolation layer the member's config was read from.
enum MemberConfigSourceLayer { runtime, team, none }

@immutable
class ConfigEntry {
  const ConfigEntry({required this.key, required this.value});
  final String key;
  final String value;
}

@immutable
class SkillEntry {
  const SkillEntry({required this.name, this.description = '', this.path = ''});
  final String name;
  final String description;
  final String path;
}

@immutable
class McpServerEntry {
  const McpServerEntry({required this.name, this.summary = ''});
  final String name;

  /// Human-readable transport/command summary (e.g. `npx ...` or a URL).
  final String summary;
}

@immutable
class PluginEntry {
  const PluginEntry({required this.name, this.version = '', this.source = ''});
  final String name;
  final String version;
  final String source;
}

/// A non-fatal problem reading one section; the rest of the detail still renders.
@immutable
class SectionWarning {
  const SectionWarning({required this.section, required this.message});
  final String section;
  final String message;
}

/// Read-only snapshot of a team member's on-disk CLI configuration.
@immutable
class MemberConfigDetail {
  const MemberConfigDetail({
    required this.cli,
    this.resolvedDir = '',
    this.sourceLayer = MemberConfigSourceLayer.none,
    this.provider = '',
    this.model = '',
    this.settings = const [],
    this.skills = const [],
    this.mcpServers = const [],
    this.plugins = const [],
    this.warnings = const [],
  });

  const MemberConfigDetail.none({required this.cli})
      : resolvedDir = '',
        sourceLayer = MemberConfigSourceLayer.none,
        provider = '',
        model = '',
        settings = const [],
        skills = const [],
        mcpServers = const [],
        plugins = const [],
        warnings = const [];

  final CliTool cli;
  final String resolvedDir;
  final MemberConfigSourceLayer sourceLayer;
  final String provider;
  final String model;
  final List<ConfigEntry> settings;
  final List<SkillEntry> skills;
  final List<McpServerEntry> mcpServers;
  final List<PluginEntry> plugins;
  final List<SectionWarning> warnings;

  bool get hasConfig => sourceLayer != MemberConfigSourceLayer.none;

  MemberConfigDetail copyWith({
    String? resolvedDir,
    MemberConfigSourceLayer? sourceLayer,
    String? provider,
    String? model,
    List<ConfigEntry>? settings,
    List<SkillEntry>? skills,
    List<McpServerEntry>? mcpServers,
    List<PluginEntry>? plugins,
    List<SectionWarning>? warnings,
  }) {
    return MemberConfigDetail(
      cli: cli,
      resolvedDir: resolvedDir ?? this.resolvedDir,
      sourceLayer: sourceLayer ?? this.sourceLayer,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      settings: settings ?? this.settings,
      skills: skills ?? this.skills,
      mcpServers: mcpServers ?? this.mcpServers,
      plugins: plugins ?? this.plugins,
      warnings: warnings ?? this.warnings,
    );
  }
}
