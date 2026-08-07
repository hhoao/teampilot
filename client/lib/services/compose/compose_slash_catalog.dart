import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/config_bundle.dart';

enum ComposeSlashCandidateKind { skill, command }

class ComposeSlashCandidate {
  const ComposeSlashCandidate({
    required this.insertText,
    required this.label,
    required this.kind,
    this.subtitle,
  });

  final String insertText;
  final String label;
  final String? subtitle;
  final ComposeSlashCandidateKind kind;
}

List<ComposeSlashCandidate> buildComposeSlashCandidates({
  required List<Skill> skills,
  required List<Plugin> plugins,
  required ConfigBundle enabledBundle,
  required String query,
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
    if (needle.isNotEmpty && !candidate.label.toLowerCase().contains(needle)) {
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
        insertText: '/$name',
        label: name,
        subtitle: skill.name.trim().isNotEmpty ? skill.name.trim() : null,
        kind: ComposeSlashCandidateKind.skill,
      ),
    );
  }

  for (final plugin in plugins) {
    if (!enabledPluginIds.contains(plugin.id)) continue;
    final pluginLabel = plugin.name.trim().isNotEmpty ? plugin.name.trim() : null;
    for (final command in plugin.capabilities.commands) {
      final name = command.name.trim();
      if (name.isEmpty) continue;
      add(
        ComposeSlashCandidate(
          insertText: '/$name',
          label: name,
          subtitle: pluginLabel,
          kind: ComposeSlashCandidateKind.command,
        ),
      );
    }
    // Plugin bundles carry skills too — surface them as slash candidates so
    // a skills-only plugin (e.g. superpowers) is usable from the `/` menu.
    for (final skill in plugin.capabilities.skills) {
      final name = skill.name.trim();
      if (name.isEmpty) continue;
      add(
        ComposeSlashCandidate(
          insertText: '/$name',
          label: name,
          subtitle: pluginLabel,
          kind: ComposeSlashCandidateKind.skill,
        ),
      );
    }
  }

  out.sort((a, b) {
    final kindOrder = a.kind.index.compareTo(b.kind.index);
    if (kindOrder != 0) return kindOrder;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}
