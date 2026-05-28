import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Metadata for a workspace sidebar section (implemented via enum extensions).
abstract interface class WorkspaceSectionDescriptor {
  String get routeSegment;

  /// Full path, e.g. `/skills/installed`.
  String routePath(String basePath);

  String title(AppLocalizations l10n);

  IconData get icon;
}
