import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../ai_message_view.dart';

/// Read-only subagent preview chrome: back bar + message list (no compose).
///
/// Hosts must wrap this widget (or its ancestor) with
/// [AiToolFileActionsScope] / [AiToolSubagentActionsScope] — the scaffold does
/// not invent scopes.
class SubagentPreviewScaffold extends StatelessWidget {
  const SubagentPreviewScaffold({
    required this.title,
    required this.messages,
    required this.onBack,
    required this.emptyLabel,
    this.backTooltip = 'Back',
    this.threadBuilder,
    super.key,
  });

  final String title;
  final List<AiMessage> messages;
  final VoidCallback onBack;
  final String emptyLabel;
  final String backTooltip;

  /// Optional custom thread body. Defaults to a list of [AiMessageView].
  final Widget Function(BuildContext context, List<AiMessage> messages)?
      threadBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: backTooltip,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final custom = threadBuilder;
    if (custom != null) return custom(context, messages);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return AiMessageView(
          message: messages[index],
          showActionBar: false,
        );
      },
    );
  }
}
