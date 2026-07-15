import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_text_styles.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import 'package:shared_ui/shared_ui.dart';
import '../team_config/team_config_mcp_section.dart';
import '../team_config/team_config_plugins_section.dart';
import '../team_config/team_config_skills_section.dart';

enum ExpertEditorDepCategory { skills, plugins, mcp }

/// Returns updated selection on Done, or `null` if Cancel / dismissed.
Future<Set<String>?> showExpertEditorDepPickerDialog(
  BuildContext context, {
  required ExpertEditorDepCategory category,
  required Set<String> selectedIds,
  List<Skill> skills = const [],
  List<Plugin> plugins = const [],
  List<McpServer> mcps = const [],
  List<SkillDependencyRef> existingSkillDeps = const [],
  List<PluginDependencyRef> existingPluginDeps = const [],
  List<McpDependencyRef> existingMcpDeps = const [],
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => ExpertEditorDepPickerDialog(
      category: category,
      initialSelectedIds: selectedIds,
      skills: skills,
      plugins: plugins,
      mcps: mcps,
      existingSkillDeps: existingSkillDeps,
      existingPluginDeps: existingPluginDeps,
      existingMcpDeps: existingMcpDeps,
    ),
  );
}

class ExpertEditorDepPickerDialog extends StatefulWidget {
  const ExpertEditorDepPickerDialog({
    super.key,
    required this.category,
    required this.initialSelectedIds,
    this.skills = const [],
    this.plugins = const [],
    this.mcps = const [],
    this.existingSkillDeps = const [],
    this.existingPluginDeps = const [],
    this.existingMcpDeps = const [],
  });

  final ExpertEditorDepCategory category;
  final Set<String> initialSelectedIds;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final List<McpServer> mcps;
  final List<SkillDependencyRef> existingSkillDeps;
  final List<PluginDependencyRef> existingPluginDeps;
  final List<McpDependencyRef> existingMcpDeps;

  @override
  State<ExpertEditorDepPickerDialog> createState() =>
      _ExpertEditorDepPickerDialogState();
}

class _ExpertEditorDepPickerDialogState
    extends State<ExpertEditorDepPickerDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initialSelectedIds);
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.category) {
      ExpertEditorDepCategory.skills => l10n.expertEditorConfigureSkillsTitle,
      ExpertEditorDepCategory.plugins => l10n.expertEditorConfigurePluginsTitle,
      ExpertEditorDepCategory.mcp => l10n.expertEditorConfigureMcpTitle,
    };
  }

  List<Widget> _categoryBody(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);

    switch (widget.category) {
      case ExpertEditorDepCategory.skills:
        final skillIds = {for (final s in widget.skills) s.id};
        final orphanSkills = [
          for (final d in widget.existingSkillDeps)
            if (_selected.contains(d.expectedLocalId) &&
                !skillIds.contains(d.expectedLocalId))
              d,
        ];
        return [
          if (orphanSkills.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanSkills) d.name],
              onRemoveAt: (i) {
                final id = orphanSkills[i].expectedLocalId;
                setState(() => _selected.remove(id));
              },
            ),
          if (widget.skills.isEmpty)
            Text(l10n.skillsNoInstalled, style: styles.sm)
          else
            for (final skill in widget.skills)
              TeamSkillRow(
                key: Key('expert-editor-skill-${skill.id}'),
                skill: skill,
                assigned: _selected.contains(skill.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selected.add(skill.id);
                    } else {
                      _selected.remove(skill.id);
                    }
                  });
                },
              ),
        ];
      case ExpertEditorDepCategory.plugins:
        final pluginIds = {for (final p in widget.plugins) p.id};
        final orphanPlugins = [
          for (final d in widget.existingPluginDeps)
            if (_selected.contains(d.expectedLocalId) &&
                !pluginIds.contains(d.expectedLocalId))
              d,
        ];
        return [
          if (orphanPlugins.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanPlugins) d.name],
              onRemoveAt: (i) {
                final id = orphanPlugins[i].expectedLocalId;
                setState(() => _selected.remove(id));
              },
            ),
          if (widget.plugins.isEmpty)
            Text(l10n.pluginsNoInstalled, style: styles.sm)
          else
            for (final plugin in widget.plugins)
              TeamPluginRow(
                key: Key('expert-editor-plugin-${plugin.id}'),
                plugin: plugin,
                assigned: _selected.contains(plugin.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selected.add(plugin.id);
                    } else {
                      _selected.remove(plugin.id);
                    }
                  });
                },
              ),
        ];
      case ExpertEditorDepCategory.mcp:
        final mcpIds = {for (final m in widget.mcps) m.id};
        final orphanMcps = [
          for (final d in widget.existingMcpDeps)
            if (_selected.contains(d.id) && !mcpIds.contains(d.id)) d,
        ];
        return [
          if (orphanMcps.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanMcps) d.name],
              onRemoveAt: (i) {
                final id = orphanMcps[i].id;
                setState(() => _selected.remove(id));
              },
            ),
          if (widget.mcps.isEmpty)
            Text(l10n.mcpNoInstalled, style: styles.sm)
          else
            for (final server in widget.mcps)
              TeamMcpRow(
                key: Key('expert-editor-mcp-${server.id}'),
                server: server,
                assigned: _selected.contains(server.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selected.add(server.id);
                    } else {
                      _selected.remove(server.id);
                    }
                  });
                },
              ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return TpDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: _title(context)),
          const SizedBox(height: 16),
          ..._categoryBody(context),
          TpDialogActions(
            children: [
              TextButton(
                key: const Key('expert-editor-dep-picker-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const Key('expert-editor-dep-picker-done'),
                onPressed: () =>
                    Navigator.of(context).pop(Set<String>.of(_selected)),
                child: Text(l10n.expertEditorDepPickerDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrphanDepList extends StatelessWidget {
  const _OrphanDepList({
    required this.title,
    required this.labels,
    required this.onRemoveAt,
  });

  final String title;
  final List<String> labels;
  final ValueChanged<int> onRemoveAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: styles.xs),
          for (var i = 0; i < labels.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(labels[i]),
              trailing: TextButton(
                onPressed: () => onRemoveAt(i),
                child: Text(l10n.expertEditorOrphanRemove),
              ),
            ),
        ],
      ),
    );
  }
}
