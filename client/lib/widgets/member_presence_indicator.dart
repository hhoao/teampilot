import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/member_presence.dart';

/// Theme-adaptive 12px dot for member list presence (no Semantics here —
/// parent [ListTile] owns accessibility).
class MemberPresenceIndicator extends StatelessWidget {
  const MemberPresenceIndicator({
    required this.presence,
    super.key,
  });

  final MemberPresence presence;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _dotColor(cs),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
    );
  }

  Color _dotColor(ColorScheme cs) {
    if (presence.isWorking) {
      return cs.primary;
    }
    if (presence.isIdle) {
      return cs.secondary;
    }
    if (presence.isConnecting) {
      return cs.onSurfaceVariant.withValues(alpha: 0.75);
    }
    return cs.onSurfaceVariant.withValues(alpha: 0.55);
  }
}

String memberPresenceStatusLabel(
  AppLocalizations l10n,
  MemberPresence presence,
) {
  if (presence.isWorking) return l10n.memberPresenceWorking;
  if (presence.isIdle) return l10n.memberPresenceIdle;
  if (presence.isConnecting) return l10n.memberPresenceConnecting;
  return l10n.memberPresenceOffline;
}
