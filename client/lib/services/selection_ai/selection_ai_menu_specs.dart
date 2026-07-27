import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/app_localizations.dart';

List<TpActionMenuSpec> selectionAiMenuSpecs({
  required AppLocalizations l10n,
  required bool enabled,
  required VoidCallback onCopyAsAiContext,
  required VoidCallback onAskAi,
}) {
  return [
    TpActionMenuSpec.item(
      icon: Icons.auto_awesome_outlined,
      label: l10n.editorCopyAsAiContext,
      enabled: enabled,
      onAction: onCopyAsAiContext,
    ),
    TpActionMenuSpec.item(
      icon: Icons.chat_outlined,
      label: l10n.selectionAskAi,
      enabled: enabled,
      onAction: onAskAi,
    ),
  ];
}
