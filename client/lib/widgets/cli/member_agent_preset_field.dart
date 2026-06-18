import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/capabilities/member_agent_preset_capability.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import '../../pages/team_config/team_config_helpers.dart';

/// Agent preset field for team members and personal workspaces.
///
/// Rendered only when [cli] registers [MemberAgentPresetCapability].
class MemberAgentPresetField extends StatelessWidget {
  const MemberAgentPresetField({
    super.key,
    required this.cli,
    required this.agent,
    required this.userAgentIds,
    required this.onAgentChanged,
    this.customAgentController,
    this.fieldKeyPrefix = 'member',
  });

  final CliTool cli;
  final String agent;
  final List<String> userAgentIds;
  final ValueChanged<String> onAgentChanged;
  final TextEditingController? customAgentController;
  final String fieldKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final registry = CliToolRegistryScope.of(context);
    final style = registry.memberAgentPresetStyle(cli);
    if (style == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    return switch (style) {
      MemberAgentPresetStyle.flashskyaiCatalog => _FlashskyaiCatalogField(
        agent: agent,
        userAgentIds: userAgentIds,
        customAgentController: customAgentController,
        onAgentChanged: onAgentChanged,
        fieldKeyPrefix: fieldKeyPrefix,
        hintText: l10n.selectAgent,
        customIdHint: l10n.agentCustomIdHint,
      ),
      MemberAgentPresetStyle.claudeAgentType => TextField(
        controller: customAgentController,
        decoration: InputDecoration(
          hintText: l10n.agentClaudeTypeHint,
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        onChanged: onAgentChanged,
      ),
    };
  }
}

class _FlashskyaiCatalogField extends StatelessWidget {
  const _FlashskyaiCatalogField({
    required this.agent,
    required this.userAgentIds,
    required this.onAgentChanged,
    required this.fieldKeyPrefix,
    required this.hintText,
    required this.customIdHint,
    this.customAgentController,
  });

  final String agent;
  final List<String> userAgentIds;
  final ValueChanged<String> onAgentChanged;
  final TextEditingController? customAgentController;
  final String fieldKeyPrefix;
  final String hintText;
  final String customIdHint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final showCustomAgentField =
        FlashskyaiAgentCatalog.activeDropdownValue(
          agent,
          userAgentIds: userAgentIds,
        ) ==
        FlashskyaiAgentCatalog.customDropdownValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<String>(
          key: ValueKey(
            '$fieldKeyPrefix-agent-dd-$agent-${userAgentIds.join(",")}',
          ),
          items: FlashskyaiAgentCatalog.dropdownValues(
            userAgentIds: userAgentIds,
          ),
          initialItem: FlashskyaiAgentCatalog.activeDropdownValue(
            agent,
            userAgentIds: userAgentIds,
          ),
          hintText: hintText,
          decoration: dropdownDeco,
          headerMaxLines: 2,
          listItemMaxLines: 2,
          itemLabel: (value) => memberAgentDropdownItemLabel(
            context,
            l10n,
            value,
            userAgentIds: userAgentIds,
          ),
          onChanged: (value) {
            final v = value ?? FlashskyaiAgentCatalog.noneDropdownValue;
            if (v == FlashskyaiAgentCatalog.noneDropdownValue) {
              customAgentController?.clear();
              onAgentChanged('');
            } else if (v == FlashskyaiAgentCatalog.customDropdownValue) {
              final current = agent.trim();
              final next =
                  FlashskyaiAgentCatalog.isKnownAgentId(
                    current,
                    userAgentIds: userAgentIds,
                  )
                  ? ''
                  : current;
              if (customAgentController != null) {
                customAgentController!.text = next;
              }
              onAgentChanged(next);
            } else {
              if (customAgentController != null) {
                customAgentController!.text = v;
              }
              onAgentChanged(v);
            }
          },
        ),
        if (showCustomAgentField) ...[
          const SizedBox(height: 8),
          TextField(
            controller: customAgentController,
            decoration: InputDecoration(
              hintText: customIdHint,
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: onAgentChanged,
          ),
        ],
      ],
    );
  }
}

String memberAgentPresetSubtitle(
  AppLocalizations l10n,
  MemberAgentPresetStyle style,
) {
  return switch (style) {
    MemberAgentPresetStyle.flashskyaiCatalog => l10n.agentFlashskyaiPresetSubtitle,
    MemberAgentPresetStyle.claudeAgentType => l10n.agentClaudeTypeSubtitle,
  };
}
