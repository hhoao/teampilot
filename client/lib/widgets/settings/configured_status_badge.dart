import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// TeamPilot copy for [TpStatusBadge] configured / not-configured states.
Widget configuredStatusBadge(BuildContext context, {required bool configured}) {
  final l10n = context.l10n;
  return TpStatusBadge(
    label: configured
        ? l10n.workspaceCliConfigured
        : l10n.workspaceCliNotConfigured,
    tone: configured
        ? TpStatusBadgeTone.success
        : TpStatusBadgeTone.neutral,
    icon: configured
        ? Icons.check_circle_outline
        : Icons.radio_button_unchecked,
  );
}
