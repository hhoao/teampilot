import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';

typedef TeamGenerateCallback = void Function(String description);

/// "Generate with AI" block inside the new-team dialog: a description field and
/// a generate button. Stateless about the result; the dialog owns generation,
/// the mode selection, and draft application.
class HomeWorkspaceTeamGenerateSection extends StatefulWidget {
  const HomeWorkspaceTeamGenerateSection({
    required this.cli,
    required this.providerId,
    required this.generating,
    required this.onGenerate,
    this.enabled = true,
    super.key,
  });

  final CliTool cli;
  final String providerId;
  final bool generating;
  final bool enabled;
  final TeamGenerateCallback onGenerate;

  @override
  State<HomeWorkspaceTeamGenerateSection> createState() =>
      _HomeWorkspaceTeamGenerateSectionState();
}

class _HomeWorkspaceTeamGenerateSectionState
    extends State<HomeWorkspaceTeamGenerateSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.teamGenTitle,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('team-gen-description'),
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          enabled: widget.enabled && !widget.generating,
          decoration: InputDecoration(
            hintText: l10n.teamGenDescriptionHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('team-gen-button'),
          onPressed: !widget.enabled || widget.generating
              ? null
              : () => widget.onGenerate(_controller.text.trim()),
          icon: widget.generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 16),
          label: Text(l10n.teamGenButton),
        ),
      ],
    );
  }
}
