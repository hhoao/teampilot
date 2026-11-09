import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../utils/session/session_display_title.dart';
import '../../widgets/cli/cli_brand_icon.dart';

/// Returns the selected session id, or null when dismissed.
Future<String?> showAutomationSessionPicker(
  BuildContext context, {
  required List<AppSession> sessions,
  required String? selectedId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => AutomationSessionPickerDialog(
      sessions: sessions,
      selectedId: selectedId,
    ),
  );
}

/// Lightweight picker for rebinding a launch-prompt automation.
class AutomationSessionPickerDialog extends StatelessWidget {
  const AutomationSessionPickerDialog({
    required this.sessions,
    required this.selectedId,
    super.key,
  });

  final List<AppSession> sessions;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 420,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.automations.sessionPickerTitle),
        body: sessions.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.automations.sessionPickerEmpty,
                    style: TpTextStyles.of(context).sm,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final session in sessions)
                    ListTile(
                      key: ValueKey('automation-session-${session.sessionId}'),
                      leading: session.cli == null
                          ? null
                          : CliBrandIcon(cli: session.cli!, size: 22),
                      title: Text(sessionListDisplayTitle(session, l10n)),
                      selected: session.sessionId == selectedId,
                      onTap: () => Navigator.of(context).pop(session.sessionId),
                    ),
                ],
              ),
        footer: TpDialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
