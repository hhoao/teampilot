import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/acp/acp_model_ref.dart';
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

/// The live agent model id for a launch-config [namespace] / [model] pair.
///
/// Agents advertise their own ids. Most use the bare model id; OpenCode
/// qualifies it with the upstream namespace (`opencode-go/<model>`).
///
/// Returns null when the agent does not advertise the pair — the caller must
/// then restart the seat instead of switching the live session.
String? acpModelIdForLaunch({
  required AcpModelState state,
  required String namespace,
  required String model,
}) => acpModelIdForLaunchRef(
  state: state,
  provider: namespace,
  model: model,
  // An explicit namespace is the pick's own decision: never fall back to the
  // other layer's same-named model.
  allowSuffix: namespace.trim().isEmpty,
);

/// The agent's advertised ids grouped by namespace prefix.
///
/// `opencode-go/x` → `{'opencode-go': ['x']}`; a bare `sonnet` → `{'': ['sonnet']}`.
/// Used to build the launch picker from what the running agent actually serves.
Map<String, List<String>> acpLiveModelsByNamespace(AcpModelState state) {
  final byNamespace = <String, List<String>>{};
  for (final option in state.options) {
    final id = option.id;
    final slash = id.indexOf('/');
    final namespace = slash > 0 ? id.substring(0, slash) : '';
    final model = slash > 0 ? id.substring(slash + 1) : id;
    if (model.isEmpty) continue;
    (byNamespace[namespace] ??= <String>[]).add(model);
  }
  return byNamespace;
}
