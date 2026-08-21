import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Authenticated / unauthenticated pill for registry sources that need a token.
class CatalogRegistryAuthBadge extends StatelessWidget {
  const CatalogRegistryAuthBadge({super.key, required this.authenticated});

  final bool authenticated;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpStatusBadge(
      label: authenticated
          ? l10n.providerCredentialsAuthenticated
          : l10n.providerCredentialsUnauthenticated,
      icon: authenticated
          ? Icons.verified_user_outlined
          : Icons.lock_outline,
      tone: authenticated
          ? TpStatusBadgeTone.success
          : TpStatusBadgeTone.warning,
    );
  }
}

/// Explicit edit affordance for registry / marketplace rows.
class CatalogRegistryEditButton extends StatelessWidget {
  const CatalogRegistryEditButton({
    super.key,
    required this.onPressed,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip ?? context.l10n.edit,
      onPressed: onPressed,
      icon: Icon(Icons.edit_outlined, size: context.tpIconSizes.md),
    );
  }
}
