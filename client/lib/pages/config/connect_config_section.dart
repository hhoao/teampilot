import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../connect/connect_section.dart';

class ConnectConfigWorkspace extends StatelessWidget {
  const ConnectConfigWorkspace({
    this.showHeading = true,
    bool? isAndroid,
    super.key,
  }) : _isAndroid = isAndroid;

  final bool showHeading;
  final bool? _isAndroid;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroid = _isAndroid ?? Platform.isAndroid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          WorkspacePaneHeader(
            title: l10n.connectSettingsTitle,
            subtitle: l10n.connectSettingsSubtitle,
            showSubtitle: true,
          ),
        Expanded(
          child: isAndroid
              ? Center(child: Text(l10n.connectAndroidScanHint))
              : const ConnectSection(),
        ),
      ],
    );
  }
}
