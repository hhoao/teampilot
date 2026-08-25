import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/config_bundle.dart';
import '../cli/registry/capabilities/native_command_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';

enum ComposeSlashCandidateKind { skill, command }

enum ComposeSlashCandidateSource { native, plugin }

class ComposeSlashCandidate {
  const ComposeSlashCandidate({
    required this.insertText,
    required this.label,
    required this.kind,
    this.subtitle,
    this.source,
    this.description,
    this.availability = NativeCommandAvailability.stable,
  });

  final String insertText;
  final String label;
  final String? subtitle;
  final ComposeSlashCandidateKind kind;
  final ComposeSlashCandidateSource? source;
  final NativeCommandDescription? description;
  final NativeCommandAvailability availability;
}

List<ComposeSlashCandidate> buildComposeSlashCandidates({
  required List<Skill> skills,
  required List<Plugin> plugins,
  required ConfigBundle enabledBundle,
  required String query,
  SkillCapability? syntax,
  List<NativeCommand> nativeCommands = const [],
  int limit = 20,
}) {
  final needle = query.trim().toLowerCase();
  final out = <ComposeSlashCandidate>[];
  final seen = <String>{};
  final enabledSkillIds = enabledBundle.skillIds.toSet();
  final enabledPluginIds = enabledBundle.pluginIds.toSet();

  void add(ComposeSlashCandidate candidate) {
    if (out.length >= limit) return;
    if (!seen.add(candidate.insertText)) return;
    if (needle.isNotEmpty &&
        !candidate.label.toLowerCase().contains(needle) &&
        !(candidate.description?.name.contains(needle) ?? false)) {
      return;
    }
    out.add(candidate);
  }

  for (final skill in skills) {
    if (!skill.enabled) continue;
    if (!enabledSkillIds.contains(skill.id)) continue;
    final name = skill.directory.trim();
    if (name.isEmpty) continue;
    add(
      ComposeSlashCandidate(
        insertText: syntax?.skillInvocationText(name) ?? '/$name',
        label: name,
        subtitle: skill.name.trim().isNotEmpty ? skill.name.trim() : null,
        kind: ComposeSlashCandidateKind.skill,
      ),
    );
  }

  for (final command in nativeCommands) {
    final name = command.name.trim();
    if (name.isEmpty) continue;
    add(
      ComposeSlashCandidate(
        insertText: command.insertText,
        label: name,
        kind: ComposeSlashCandidateKind.command,
        source: ComposeSlashCandidateSource.native,
        description: command.description,
        availability: command.availability,
      ),
    );
  }

  for (final plugin in plugins) {
    if (!enabledPluginIds.contains(plugin.id)) continue;
    final pluginLabel = plugin.name.trim().isNotEmpty
        ? plugin.name.trim()
        : null;
    for (final command in plugin.capabilities.commands) {
      final name = command.name.trim();
      if (name.isEmpty) continue;
      add(
        ComposeSlashCandidate(
          insertText: '/$name',
          label: name,
          subtitle: pluginLabel,
          kind: ComposeSlashCandidateKind.command,
          source: ComposeSlashCandidateSource.plugin,
        ),
      );
    }
    // Plugin bundles carry skills too — surface them as slash candidates so
    // a skills-only plugin (e.g. superpowers) is usable from the `/` menu.
    // Plugin skills get the plugin name as the namespace when the target CLI
    // expects one (Codex: `$superpowers:using-git-worktrees`).
    for (final skill in plugin.capabilities.skills) {
      final name = skill.name.trim();
      if (name.isEmpty) continue;
      add(
        ComposeSlashCandidate(
          insertText:
              syntax?.skillInvocationText(name, namespace: plugin.name) ??
              '/$name',
          label: name,
          subtitle: pluginLabel,
          kind: ComposeSlashCandidateKind.skill,
          source: ComposeSlashCandidateSource.plugin,
        ),
      );
    }
  }

  out.sort((a, b) {
    final kindOrder = a.kind.index.compareTo(b.kind.index);
    if (kindOrder != 0) return kindOrder;
    if (a.kind == ComposeSlashCandidateKind.command) {
      final sourceOrder = _commandSourceOrder(
        a.source,
      ).compareTo(_commandSourceOrder(b.source));
      if (sourceOrder != 0) return sourceOrder;
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}

int _commandSourceOrder(ComposeSlashCandidateSource? source) {
  return switch (source) {
    ComposeSlashCandidateSource.native => 0,
    ComposeSlashCandidateSource.plugin => 1,
    null => 2,
  };
}
