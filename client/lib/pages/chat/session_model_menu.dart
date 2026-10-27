import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/acp/acp_session.dart';

/// A menu pick that switches the live ACP agent model.
///
/// Kept as a value object so [TpActionMenuSpec] routing cannot confuse an
/// agent model id with a CLI preset id (both are plain strings on the wire).
final class AcpModelPick {
  const AcpModelPick(this.modelId);

  final String modelId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpModelPick && modelId == other.modelId;

  @override
  int get hashCode => modelId.hashCode;
}

/// Builds the single session-model menu.
///
/// Agent models come first and apply immediately through
/// `session/set_config_option`; the existing launch-identity menu (provider /
/// model / preset) moves into a submenu because switching it needs a restart.
/// Returns [launchSpecs] unchanged when the agent advertises no model option.
List<TpActionMenuSpec> buildSessionModelMenuSpecs({
  required List<TpActionMenuSpec> launchSpecs,
  required AcpModelState modelState,
  required String agentSectionLabel,
  required String launchSectionLabel,
}) {
  return [
    TpActionMenuSpec.item(label: agentSectionLabel, enabled: false),
    for (final option in modelState.options)
      TpActionMenuSpec.item(
        value: AcpModelPick(option.id),
        label: option.name,
        subtitle: option.description == null ? null : Text(option.description!),
        selected: option.id == modelState.currentId,
      ),
    if (launchSpecs.isNotEmpty) ...[
      TpActionMenuSpec.divider(),
      TpActionMenuSpec.submenu(
        label: launchSectionLabel,
        children: launchSpecs,
      ),
    ],
  ];
}
