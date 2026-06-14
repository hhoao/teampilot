import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../member_config/member_config_detail.dart';
import '../cli_capability.dart';
import 'plugin_manifest_capability.dart';

/// Inputs for [MemberConfigInspectionCapability.inspect], resolved by
/// `MemberConfigInspector` before delegating to the CLI.
@immutable
class MemberConfigContext {
  const MemberConfigContext({
    required this.cli,
    required this.configDir,
    required this.sourceLayer,
    required this.mcpSnapshotPath,
    required this.provider,
    required this.model,
    required this.fs,
  });

  final CliTool cli;
  final String configDir;
  final MemberConfigSourceLayer sourceLayer;

  /// Aggregated team MCP snapshot (`config-profiles/teams/{id}/mcp/servers.json`).
  final String mcpSnapshotPath;
  final String provider;
  final String model;
  final Filesystem fs;
}

/// Reads a member's on-disk config for a single CLI. Default behaviour lives in
/// [DefaultMemberConfigInspection]; CLIs whose layout differs register a subclass.
abstract interface class MemberConfigInspectionCapability
    implements CliCapability {
  Future<MemberConfigDetail> inspect(MemberConfigContext ctx);
}

/// Reads the layout common to all CLIs: `skills/`, `plugins/`, an aggregated MCP
/// `servers.json`, and a top-level `settings.json`.
class DefaultMemberConfigInspection
    implements MemberConfigInspectionCapability {
  const DefaultMemberConfigInspection();

  @override
  Future<MemberConfigDetail> inspect(MemberConfigContext ctx) async {
    final warnings = <SectionWarning>[];
    final skills = await _readSkills(ctx, warnings);
    final plugins = await _readPlugins(ctx, warnings);
    final mcp = await _readMcp(ctx, warnings);
    final settings = await _readSettings(ctx, warnings);
    return MemberConfigDetail(
      cli: ctx.cli,
      resolvedDir: ctx.configDir,
      sourceLayer: ctx.sourceLayer,
      provider: ctx.provider,
      model: ctx.model,
      skills: skills,
      plugins: plugins,
      mcpServers: mcp,
      settings: settings,
      warnings: warnings,
    );
  }

  p.Context _pc(MemberConfigContext ctx) => ctx.fs.pathContext;

  Future<List<SkillEntry>> _readSkills(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final dir = _pc(ctx).join(ctx.configDir, 'skills');
    if (!(await ctx.fs.stat(dir)).isDirectory) return const [];
    final out = <SkillEntry>[];
    try {
      for (final entry in await ctx.fs.listDir(dir)) {
        if (!entry.isDirectory) continue;
        final skillDir = _pc(ctx).join(dir, entry.name);
        var name = entry.name;
        var description = '';
        for (final manifest in const ['SKILL.md', 'skill.md']) {
          final raw =
              await ctx.fs.readString(_pc(ctx).join(skillDir, manifest));
          if (raw == null) continue;
          final fm = _frontMatter(raw);
          name = fm['name']?.trim().isNotEmpty == true
              ? fm['name']!.trim()
              : name;
          description = fm['description']?.trim() ?? '';
          break;
        }
        out.add(SkillEntry(name: name, description: description, path: skillDir));
      }
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'skills', message: '$e'));
    }
    return out;
  }

  Future<List<PluginEntry>> _readPlugins(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final dir = _pc(ctx).join(ctx.configDir, 'plugins');
    if (!(await ctx.fs.stat(dir)).isDirectory) return const [];
    final candidates = (pluginManifestPathsForTool(ctx.cli) ??
            claudePluginManifestPaths)
        .manifestCandidates()
        .toList();
    final out = <PluginEntry>[];
    try {
      for (final entry in await ctx.fs.listDir(dir)) {
        if (!entry.isDirectory) continue;
        final bundleDir = _pc(ctx).join(dir, entry.name);
        var name = entry.name;
        var version = '';
        for (final rel in candidates) {
          final raw =
              await ctx.fs.readString(_pc(ctx).join(bundleDir, rel));
          if (raw == null) continue;
          try {
            final json = jsonDecode(raw) as Map<String, Object?>;
            name = (json['name'] as String?)?.trim().isNotEmpty == true
                ? (json['name'] as String).trim()
                : name;
            version = (json['version'] as String?)?.trim() ?? '';
          } on Object {
            // fall through to directory-name defaults
          }
          break;
        }
        out.add(PluginEntry(name: name, version: version, source: bundleDir));
      }
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'plugins', message: '$e'));
    }
    return out;
  }

  Future<List<McpServerEntry>> _readMcp(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final raw = await ctx.fs.readString(ctx.mcpSnapshotPath);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final servers = json['mcpServers'] as Map<String, Object?>? ??
          const <String, Object?>{};
      return [
        for (final e in servers.entries)
          McpServerEntry(
            name: e.key,
            summary: _mcpSummary(e.value),
          ),
      ];
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'mcp', message: '$e'));
      return const [];
    }
  }

  Future<List<ConfigEntry>> _readSettings(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final raw = await ctx.fs
        .readString(_pc(ctx).join(ctx.configDir, 'settings.json'));
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return [
        for (final e in json.entries)
          ConfigEntry(key: e.key, value: '${e.value}'),
      ];
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'settings', message: '$e'));
      return const [];
    }
  }

  String _mcpSummary(Object? value) {
    if (value is! Map) return '';
    final url = value['url'];
    if (url is String && url.isNotEmpty) return url;
    final command = value['command'];
    final args = value['args'];
    if (command is String && command.isNotEmpty) {
      final argList = args is List ? args.join(' ') : '';
      return argList.isEmpty ? command : '$command $argList';
    }
    final type = value['type'];
    return type is String ? type : '';
  }

  /// Minimal YAML front-matter reader (`---` fenced `key: value` lines).
  Map<String, String> _frontMatter(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final out = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') break;
      final idx = lines[i].indexOf(':');
      if (idx <= 0) continue;
      final key = lines[i].substring(0, idx).trim();
      final value = lines[i].substring(idx + 1).trim();
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }
}
