import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// Resolves [AppLocalizations.termuxDisconnectedWorkOpsBlocked] outside widget
/// trees (session launch, run service). Updated by [TermuxWorkOpsMessageBinder].
class TermuxWorkOpsMessage {
  TermuxWorkOpsMessage._();

  static AppLocalizations? _l10n;

  static void bind(AppLocalizations l10n) => _l10n = l10n;

  @visibleForTesting
  static void resetForTesting() => _l10n = null;

  static String disconnectedBlocked() =>
      _l10n?.termuxDisconnectedWorkOpsBlocked ??
      'Termux is disconnected. Reconnect from the banner, then try again.';
}
