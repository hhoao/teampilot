import 'package:flutter/material.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../opencode_go_layer.dart';

/// OpenCode-only provider form fields.
///
/// The catalog row is a single "OpenCode" provider; the Go plan is a boolean
/// binding that switches the paid layer on, not a separate provider.
class OpencodeProviderFormSection extends StatelessWidget {
  const OpencodeProviderFormSection({
    required this.subscription,
    required this.onSubscriptionChanged,
    super.key,
  });

  final String subscription;
  final ValueChanged<String> onSubscriptionChanged;

  bool get _goBound => OpencodeGoLayer.isNamespace(subscription);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SwitchListTile(
      key: const ValueKey('opencode-provider-go-subscription'),
      contentPadding: EdgeInsets.zero,
      value: _goBound,
      onChanged: (value) =>
          onSubscriptionChanged(value ? OpencodeGoLayer.namespace : ''),
      title: Text(l10n.appProviderOpencodeSubscription),
      subtitle: Text(
        _goBound
            ? l10n.appProviderOpencodeSubscriptionOn
            : l10n.appProviderOpencodeSubscriptionOff,
      ),
      secondary: const Icon(Icons.workspace_premium_outlined),
    );
  }
}
