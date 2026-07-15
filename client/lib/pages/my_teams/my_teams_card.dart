import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/hub_publish/hub_publish_record_store.dart';
import '../hub_publish/hub_publish_badge.dart';
import '../team_hub/team_hub_cards.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

String formatMyTeamsTimestamp(int ms) {
  if (ms <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

class MyTeamsCard extends StatefulWidget {
  const MyTeamsCard({
    super.key,
    required this.team,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
    this.onUpload,
    this.publishRecord,
  });

  final TeamProfile team;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onUpload;
  final HubPublishRecord? publishRecord;

  @override
  State<MyTeamsCard> createState() => _MyTeamsCardState();
}

class _MyTeamsCardState extends State<MyTeamsCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final team = widget.team;
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final def = registry.tryGet(team.cli);
    final cliLabel = def == null ? team.cli.value : cliDisplayName(def, l10n);
    final modeLabel = switch (team.teamMode) {
      TeamMode.native => l10n.teamModeNative,
      TeamMode.mixed => l10n.teamModeMixed,
    };
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
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
                  title: team.name,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onUpload != null)
                        IconButton(
                          key: Key('my-teams-upload-${team.id}'),
                          tooltip: l10n.myTeamsUpload,
                          onPressed: widget.onUpload,
                          icon: Icon(
                            Icons.upload_outlined,
                            size: context.tpIconSizes.md,
                          ),
                        ),
                      IconButton(
                        key: Key('my-teams-delete-${team.id}'),
                        tooltip: l10n.deleteTeam,
                        onPressed: widget.onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: context.tpIconSizes.md,
                          color: cs.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.myTeamsMemberCount(team.roster.length),
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '$cliLabel · $modeLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
                if (widget.publishRecord != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HubPublishBadge(
                      key: Key('hub-publish-badge-team-${team.id}'),
                      record: widget.publishRecord!,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  l10n.myTeamsCreatedAt(formatMyTeamsTimestamp(team.createdAt)),
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
