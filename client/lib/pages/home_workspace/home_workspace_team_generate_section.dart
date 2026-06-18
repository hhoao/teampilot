import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

typedef TeamDescriptionChanged = void Function(String description);

/// AI description input inside the new-team dialog. The dialog owns generation,
/// mode selection, and the primary "生成" action; this widget only collects the
/// description and renders streaming progress.
class HomeTeamGenerateSection extends StatefulWidget {
  const HomeTeamGenerateSection({
    required this.onDescriptionChanged,
    this.enabled = true,
    this.progress,
    super.key,
  });

  final bool enabled;

  /// Non-null while generating: 0..1 value for the progress bar.
  final double? progress;
  final TeamDescriptionChanged onDescriptionChanged;

  @override
  State<HomeTeamGenerateSection> createState() =>
      _HomeTeamGenerateSectionState();
}

class _HomeTeamGenerateSectionState
    extends State<HomeTeamGenerateSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final generating = widget.progress != null;
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
          enabled: widget.enabled && !generating,
          onChanged: widget.onDescriptionChanged,
          decoration: InputDecoration(
            hintText: l10n.teamGenDescriptionHint,
            isDense: true,
          ),
        ),
        if (generating) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const ValueKey('team-gen-progress'),
              value: widget.progress,
              minHeight: 6,
            ),
          ),
        ],
      ],
    );
  }
}
