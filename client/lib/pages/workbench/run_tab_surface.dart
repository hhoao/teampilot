import 'package:flutter/material.dart';

import '../../widgets/run/run_panel.dart';

/// Center workbench body for one Run session (no dock chrome).
class RunTabSurface extends StatelessWidget {
  const RunTabSurface({
    required this.sessionId,
    super.key,
  });

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return RunPanel(
      showChrome: false,
      activeSessionId: sessionId,
    );
  }
}
