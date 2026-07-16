import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
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
import 'expert_editor_dep_picker_dialog.dart';
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
        dialog = BlocProvider<ExpertHubCubit>.value(value: hub, child: dialog);
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
  final _formKey = GlobalKey<TpFormState>();
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
    _prompt = TextEditingController(
      text: initial?.member.responsibilities ?? '',
    );
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

  List<Skill> _skillsRead(BuildContext context) {
    if (widget.skills != null) return widget.skills!;
    try {
      return context
          .read<SkillCubit>()
          .state
          .installed
          .where((s) => s.enabled)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<Plugin> _pluginsRead(BuildContext context) {
    if (widget.plugins != null) return widget.plugins!;
    try {
      return context.read<PluginCubit>().state.installed;
    } catch (_) {
      return const [];
    }
  }

  List<McpServer> _mcpsRead(BuildContext context) {
    if (widget.mcps != null) return widget.mcps!;
    try {
      return context
          .read<McpCubit>()
          .state
          .servers
          .where((s) => s.enabled)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openDepPicker(ExpertEditorDepCategory category) async {
    final result = await showExpertEditorDepPickerDialog(
      context,
      category: category,
      selectedIds: switch (category) {
        ExpertEditorDepCategory.skills => _selectedSkillIds,
        ExpertEditorDepCategory.plugins => _selectedPluginIds,
        ExpertEditorDepCategory.mcp => _selectedMcpIds,
      },
      skills: _skillsRead(context),
      plugins: _pluginsRead(context),
      mcps: _mcpsRead(context),
      existingSkillDeps: _existingSkillDeps,
      existingPluginDeps: _existingPluginDeps,
      existingMcpDeps: _existingMcpDeps,
    );
    if (!mounted || result == null) return;
    setState(() {
      switch (category) {
        case ExpertEditorDepCategory.skills:
          _selectedSkillIds = result;
        case ExpertEditorDepCategory.plugins:
          _selectedPluginIds = result;
        case ExpertEditorDepCategory.mcp:
          _selectedMcpIds = result;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    final l10n = context.l10n;
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();

    setState(() => _saving = true);
    try {
      final initial = widget.initial;
      final skills = _skillsRead(context);
      final plugins = _pluginsRead(context);
      final mcps = _mcpsRead(context);
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
          variant: TpToastVariant.info,
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
          responsibilities: prompt,
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
        variant: TpToastVariant.error,
      );
    }
  }

  Widget _textField({
    required String id,
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TpFormField<String>(
      id: id,
      initialValue: controller.text,
      label: Text(label),
      validator: validator,
      builder: (state) {
        return TextField(
          key: fieldKey,
          controller: controller,
          focusNode: state.focusNode,
          textInputAction: textInputAction,
          onChanged: state.didChange,
          decoration: InputDecoration(
            hintText: hint,
            errorText: state.hasError ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return TpDialog(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: TpForm(
        key: _formKey,
        child: TpDialogPinnedLayout(
          header: TpDialogHeader(
            title: _isEditing
                ? l10n.expertEditorEditTitle
                : l10n.expertEditorCreateTitle,
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textField(
                id: 'name',
                fieldKey: const Key('expert-editor-name'),
                controller: _name,
                label: l10n.name,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.expertEditorNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              _textField(
                id: 'description',
                fieldKey: const Key('expert-editor-description'),
                controller: _description,
                label: l10n.expertEditorDescription,
              ),
              const SizedBox(height: 12),
              _textField(
                id: 'category',
                fieldKey: const Key('expert-editor-category'),
                controller: _category,
                label: l10n.expertEditorCategory,
              ),
              const SizedBox(height: 12),
              TpTextareaFormField(
                key: const Key('expert-editor-prompt'),
                id: 'prompt',
                controller: _prompt,
                label: Text(l10n.expertHubPrompt),
                decoration: InputDecoration(
                  hintText: l10n.expertEditorPromptHint,
                ),
                minHeight: tpTextareaHeightForLines(bodyStyle, lines: 3),
                maxHeight: tpTextareaHeightForLines(bodyStyle, lines: 6),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.expertEditorPromptRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TpTextareaFormField(
                key: const Key('expert-editor-playbook'),
                id: 'playbook',
                controller: _playbook,
                label: Text(l10n.expertHubPlaybook),
                decoration: InputDecoration(
                  hintText: l10n.expertEditorPlaybookHint,
                ),
                minHeight: tpTextareaHeightForLines(bodyStyle, lines: 2),
                maxHeight: tpTextareaHeightForLines(bodyStyle, lines: 5),
              ),
              const SizedBox(height: 12),
              _textField(
                id: 'tags',
                fieldKey: const Key('expert-editor-tags'),
                controller: _tags,
                label: l10n.expertEditorTags,
                hint: l10n.expertEditorTagsHint,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 20),
              Text(l10n.expertEditorDepsHint, style: styles.sm),
              const SizedBox(height: 12),
              _ExpertEditorDepSummaryRow(
                key: const Key('expert-editor-dep-skills'),
                title: l10n.expertEditorSkillsSection,
                countKey: const Key('expert-editor-skills-count'),
                count: _selectedSkillIds.length,
                configureKey: const Key('expert-editor-configure-skills'),
                onConfigure: () =>
                    _openDepPicker(ExpertEditorDepCategory.skills),
              ),
              _ExpertEditorDepSummaryRow(
                key: const Key('expert-editor-dep-plugins'),
                title: l10n.expertEditorPluginsSection,
                countKey: const Key('expert-editor-plugins-count'),
                count: _selectedPluginIds.length,
                configureKey: const Key('expert-editor-configure-plugins'),
                onConfigure: () =>
                    _openDepPicker(ExpertEditorDepCategory.plugins),
              ),
              _ExpertEditorDepSummaryRow(
                key: const Key('expert-editor-dep-mcp'),
                title: l10n.expertEditorMcpSection,
                countKey: const Key('expert-editor-mcp-count'),
                count: _selectedMcpIds.length,
                configureKey: const Key('expert-editor-configure-mcp'),
                onConfigure: () => _openDepPicker(ExpertEditorDepCategory.mcp),
              ),
            ],
          ),
          footer: TpDialogActions(
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
        ),
      ),
    );
  }
}

class _ExpertEditorDepSummaryRow extends StatelessWidget {
  const _ExpertEditorDepSummaryRow({
    super.key,
    required this.title,
    required this.count,
    required this.countKey,
    required this.configureKey,
    required this.onConfigure,
  });

  final String title;
  final int count;
  final Key countKey;
  final Key configureKey;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(title, style: styles.mdBold),
                const SizedBox(width: 8),
                KeyedSubtree(
                  key: countKey,
                  child: Text('$count', style: styles.sm),
                ),
              ],
            ),
          ),
          TextButton(
            key: configureKey,
            onPressed: onConfigure,
            child: Text(l10n.configure),
          ),
        ],
      ),
    );
  }
}
