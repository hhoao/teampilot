import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../expert_hub/expert_hub_visuals.dart';
import '../hub_publish/hub_publish_badge.dart';
import '../team_hub/team_hub_cards.dart';
import 'package:shared_ui/shared_ui.dart';

enum MyExpertsCardAction { edit, delete, addToTeam, upload }

class MyExpertsCard extends StatefulWidget {
  const MyExpertsCard({
    super.key,
    required this.member,
    required this.selected,
    required this.onAction,
    this.onTap,
    this.publishRecord,
  });

  final DiscoverableMember member;
  final bool selected;
  final ValueChanged<MyExpertsCardAction> onAction;
  final VoidCallback? onTap;
  final HubPublishRecord? publishRecord;

  @override
  State<MyExpertsCard> createState() => _MyExpertsCardState();
}

class _MyExpertsCardState extends State<MyExpertsCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final member = widget.member;
    final accent = teamAccentColor(member.key, Theme.of(context).brightness);
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? accent.withValues(alpha: 0.55)
        : cs.outlineVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: widget.selected
                ? cs.primary.withValues(alpha: 0.06)
                : cs.workspaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: TeamHubWorkspaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamHubCardHeader(
                  title: member.name,
                  trailing: PopupMenuButton<MyExpertsCardAction>(
                    key: Key('my-experts-overflow-${member.key}'),
                    onSelected: widget.onAction,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: MyExpertsCardAction.edit,
                        child: Text(l10n.myExpertsEdit),
                      ),
                      PopupMenuItem(
                        value: MyExpertsCardAction.upload,
                        child: Text(l10n.myExpertsUpload),
                      ),
                      PopupMenuItem(
                        value: MyExpertsCardAction.addToTeam,
                        child: Text(l10n.expertHubAddToTeam),
                      ),
                      PopupMenuItem(
                        value: MyExpertsCardAction.delete,
                        child: Text(l10n.myExpertsDelete),
                      ),
                    ],
                    icon: Icon(
                      Icons.more_vert,
                      size: context.tpIconSizes.md,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  member.description.trim().isEmpty
                      ? '—'
                      : member.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  member.category.trim().isEmpty
                      ? l10n.expertHubSourceLocal
                      : member.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
                if (widget.publishRecord != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HubPublishBadge(
                      key: Key('hub-publish-badge-expert-${member.key}'),
                      record: widget.publishRecord!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
