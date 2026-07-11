import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_text_styles.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../services/expert_hub/local_expert_writer.dart';
import '../../widgets/app_dialog.dart';
import '../team_config/team_config_mcp_section.dart';
import '../team_config/team_config_plugins_section.dart';
import '../team_config/team_config_skills_section.dart';
import 'expert_editor_deps.dart';

/// Shared create/edit dialog for local experts (My Experts + Expert Hub).
Future<DiscoverableMember?> showExpertEditorDialog(
  BuildContext context, {
  LocalExpertWriter? writer,
  DiscoverableMember? initial,
  List<Skill>? skills,
  List<Plugin>? plugins,
  List<McpServer>? mcps,
}) {
  ExpertHubCubit? hub;
  try {
    hub = context.read<ExpertHubCubit>();
  } catch (_) {
    hub = null;
  }
  return showDialog<DiscoverableMember>(
    context: context,
    builder: (ctx) {
      Widget dialog = ExpertEditorDialog(
        writer: writer ?? LocalExpertWriter(),
        initial: initial,
        skills: skills,
        plugins: plugins,
        mcps: mcps,
      );
      if (hub != null) {
        dialog = BlocProvider<ExpertHubCubit>.value(
          value: hub,
          child: dialog,
        );
      }
      return dialog;
    },
  );
}

class ExpertEditorDialog extends StatefulWidget {
  const ExpertEditorDialog({
    super.key,
    required this.writer,
    this.initial,
    this.skills,
    this.plugins,
    this.mcps,
  });

  final LocalExpertWriter writer;
  final DiscoverableMember? initial;

  /// When non-null, used instead of [SkillCubit] (tests / previews).
  final List<Skill>? skills;
  final List<Plugin>? plugins;
  final List<McpServer>? mcps;

  @override
  State<ExpertEditorDialog> createState() => _ExpertEditorDialogState();
}

class _ExpertEditorDialogState extends State<ExpertEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _prompt;
  late final TextEditingController _playbook;
  late final TextEditingController _tags;
  var _saving = false;

  late Set<String> _selectedSkillIds;
  late Set<String> _selectedPluginIds;
  late Set<String> _selectedMcpIds;
  late List<SkillDependencyRef> _existingSkillDeps;
  late List<PluginDependencyRef> _existingPluginDeps;
  late List<McpDependencyRef> _existingMcpDeps;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _category = TextEditingController(text: initial?.category ?? '');
    _prompt = TextEditingController(text: initial?.member.prompt ?? '');
    _playbook = TextEditingController(text: initial?.member.playbook ?? '');
    _tags = TextEditingController(
      text: initial == null || initial.tags.isEmpty
          ? ''
          : initial.tags.join(', '),
    );
    _existingSkillDeps = List.of(initial?.skillDeps ?? const []);
    _existingPluginDeps = List.of(initial?.pluginDeps ?? const []);
    _existingMcpDeps = List.of(initial?.mcpDeps ?? const []);
    _selectedSkillIds = expertEditorSelectedSkillIds(_existingSkillDeps);
    _selectedPluginIds = expertEditorSelectedPluginIds(_existingPluginDeps);
    _selectedMcpIds = expertEditorSelectedMcpIds(_existingMcpDeps);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _prompt.dispose();
    _playbook.dispose();
    _tags.dispose();
    super.dispose();
  }

  Set<String> _parseTags(String raw) {
    return {
      for (final part in raw.split(RegExp(r'[,，]')))
        if (part.trim().isNotEmpty) part.trim(),
    };
  }

  List<Skill> _skills(BuildContext context) {
    if (widget.skills != null) return widget.skills!;
    try {
      return context
          .watch<SkillCubit>()
          .state
          .installed
          .where((s) => s.enabled)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<Plugin> _plugins(BuildContext context) {
    if (widget.plugins != null) return widget.plugins!;
    try {
      return context.watch<PluginCubit>().state.installed;
    } catch (_) {
      return const [];
    }
  }

  List<McpServer> _mcps(BuildContext context) {
    if (widget.mcps != null) return widget.mcps!;
    try {
      return context
          .watch<McpCubit>()
          .state
          .servers
          .where((s) => s.enabled)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = context.l10n;
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    if (name.isEmpty) {
      AppToast.show(
        context,
        message: l10n.expertEditorNameRequired,
        variant: AppToastVariant.error,
      );
      return;
    }
    if (prompt.isEmpty) {
      AppToast.show(
        context,
        message: l10n.expertEditorPromptRequired,
        variant: AppToastVariant.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final initial = widget.initial;
      final skills = _skills(context);
      final plugins = _plugins(context);
      final mcps = _mcps(context);
      final deps = resolveExpertEditorDeps(
        selectedSkillIds: _selectedSkillIds,
        selectedPluginIds: _selectedPluginIds,
        selectedMcpIds: _selectedMcpIds,
        skills: skills,
        plugins: plugins,
        mcps: mcps,
        existingSkillDeps: _existingSkillDeps,
        existingPluginDeps: _existingPluginDeps,
        existingMcpDeps: _existingMcpDeps,
      );
      if (deps.skippedNonPortableIds.isNotEmpty && mounted) {
        AppToast.show(
          context,
          message: l10n.expertEditorNonPortableSkipped(
            deps.skippedNonPortableIds.length,
          ),
          variant: AppToastVariant.info,
        );
      }
      final member = DiscoverableMember(
        key: initial?.key ?? '',
        name: name,
        description: _description.text.trim(),
        category: _category.text.trim(),
        source: ExpertMemberSource.local,
        tags: _parseTags(_tags.text),
        member: DiscoverableTeamMember(
          name: name,
          prompt: prompt,
          playbook: _playbook.text.trim(),
          provider: initial?.member.provider ?? '',
          model: initial?.member.model ?? '',
          agent: initial?.member.agent ?? '',
          agentType: initial?.member.agentType ?? '',
          capabilities: initial?.member.capabilities ?? const {},
          replicas: initial?.member.replicas ?? 1,
          extraArgs: initial?.member.extraArgs ?? '',
        ),
        skillDeps: deps.skillDeps,
        pluginDeps: deps.pluginDeps,
        mcpDeps: deps.mcpDeps,
        author: initial?.author,
        originTeamKey: initial?.originTeamKey,
      );
      final saved = await widget.writer.save(member);
      if (!mounted) return;
      ExpertHubCubit? hub;
      try {
        hub = context.read<ExpertHubCubit>();
      } catch (_) {
        hub = null;
      }
      if (hub != null) {
        try {
          await hub.load(forceRefresh: true);
        } catch (_) {
          // Best-effort refresh; save already succeeded.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(
        context,
        message: l10n.expertHubAddFailed,
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final skills = _skills(context);
    final plugins = _plugins(context);
    final mcps = _mcps(context);
    final skillIds = {for (final s in skills) s.id};
    final pluginIds = {for (final p in plugins) p.id};
    final mcpIds = {for (final m in mcps) m.id};
    final orphanSkills = [
      for (final d in _existingSkillDeps)
        if (_selectedSkillIds.contains(d.expectedLocalId) &&
            !skillIds.contains(d.expectedLocalId))
          d,
    ];
    final orphanPlugins = [
      for (final d in _existingPluginDeps)
        if (_selectedPluginIds.contains(d.expectedLocalId) &&
            !pluginIds.contains(d.expectedLocalId))
          d,
    ];
    final orphanMcps = [
      for (final d in _existingMcpDeps)
        if (_selectedMcpIds.contains(d.id) && !mcpIds.contains(d.id)) d,
    ];

    return AppDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: _isEditing
                ? l10n.expertEditorEditTitle
                : l10n.expertEditorCreateTitle,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('expert-editor-name'),
            controller: _name,
            decoration: InputDecoration(labelText: l10n.name),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expert-editor-description'),
            controller: _description,
            decoration: InputDecoration(
              labelText: l10n.expertEditorDescription,
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expert-editor-category'),
            controller: _category,
            decoration: InputDecoration(labelText: l10n.expertEditorCategory),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expert-editor-prompt'),
            controller: _prompt,
            decoration: InputDecoration(labelText: l10n.expertHubPrompt),
            minLines: 3,
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expert-editor-playbook'),
            controller: _playbook,
            decoration: InputDecoration(labelText: l10n.expertHubPlaybook),
            minLines: 2,
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('expert-editor-tags'),
            controller: _tags,
            decoration: InputDecoration(
              labelText: l10n.expertEditorTags,
              hintText: l10n.expertEditorTagsHint,
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.expertEditorDepsHint, style: styles.sm),
          const SizedBox(height: 12),
          _DepSectionTitle(l10n.expertEditorSkillsSection),
          if (orphanSkills.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanSkills) d.name],
              onRemoveAt: (i) {
                final id = orphanSkills[i].expectedLocalId;
                setState(() => _selectedSkillIds.remove(id));
              },
            ),
          if (skills.isEmpty)
            Text(l10n.skillsNoInstalled, style: styles.sm)
          else
            for (final skill in skills)
              TeamSkillRow(
                key: Key('expert-editor-skill-${skill.id}'),
                skill: skill,
                assigned: _selectedSkillIds.contains(skill.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selectedSkillIds.add(skill.id);
                    } else {
                      _selectedSkillIds.remove(skill.id);
                    }
                  });
                },
              ),
          const SizedBox(height: 12),
          _DepSectionTitle(l10n.expertEditorPluginsSection),
          if (orphanPlugins.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanPlugins) d.name],
              onRemoveAt: (i) {
                final id = orphanPlugins[i].expectedLocalId;
                setState(() => _selectedPluginIds.remove(id));
              },
            ),
          if (plugins.isEmpty)
            Text(l10n.pluginsNoInstalled, style: styles.sm)
          else
            for (final plugin in plugins)
              TeamPluginRow(
                key: Key('expert-editor-plugin-${plugin.id}'),
                plugin: plugin,
                assigned: _selectedPluginIds.contains(plugin.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selectedPluginIds.add(plugin.id);
                    } else {
                      _selectedPluginIds.remove(plugin.id);
                    }
                  });
                },
              ),
          const SizedBox(height: 12),
          _DepSectionTitle(l10n.expertEditorMcpSection),
          if (orphanMcps.isNotEmpty)
            _OrphanDepList(
              title: l10n.expertEditorOrphanDeps,
              labels: [for (final d in orphanMcps) d.name],
              onRemoveAt: (i) {
                final id = orphanMcps[i].id;
                setState(() => _selectedMcpIds.remove(id));
              },
            ),
          if (mcps.isEmpty)
            Text(l10n.mcpNoInstalled, style: styles.sm)
          else
            for (final server in mcps)
              TeamMcpRow(
                key: Key('expert-editor-mcp-${server.id}'),
                server: server,
                assigned: _selectedMcpIds.contains(server.id),
                onAssignedChanged: (assigned) {
                  setState(() {
                    if (assigned) {
                      _selectedMcpIds.add(server.id);
                    } else {
                      _selectedMcpIds.remove(server.id);
                    }
                  });
                },
              ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const Key('expert-editor-submit'),
                onPressed: _saving ? null : _submit,
                child: Text(_isEditing ? l10n.save : l10n.create),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DepSectionTitle extends StatelessWidget {
  const _DepSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: AppTextStyles.of(
          context,
        ).mdBold,
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
