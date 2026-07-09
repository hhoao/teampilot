import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../services/expert_hub/local_expert_writer.dart';
import '../../widgets/app_dialog.dart';

/// Shared create/edit dialog for local experts (My Experts + Expert Hub).
Future<DiscoverableMember?> showExpertEditorDialog(
  BuildContext context, {
  LocalExpertWriter? writer,
  DiscoverableMember? initial,
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
  });

  final LocalExpertWriter writer;
  final DiscoverableMember? initial;

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
        skillDeps: initial?.skillDeps ?? const [],
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
