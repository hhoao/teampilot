import 'package:flutter/material.dart';

import '../../../../l10n/l10n_extensions.dart';
import 'package:shared_ui/shared_ui.dart';

/// OpenCode-only provider form fields (subscription namespace for staging).
class OpencodeProviderFormSection extends StatefulWidget {
  const OpencodeProviderFormSection({
    required this.subscription,
    required this.onSubscriptionChanged,
    super.key,
  });

  final String subscription;
  final ValueChanged<String> onSubscriptionChanged;

  @override
  State<OpencodeProviderFormSection> createState() =>
      _OpencodeProviderFormSectionState();
}

class _OpencodeProviderFormSectionState extends State<OpencodeProviderFormSection> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.subscription);
  }

  @override
  void didUpdateWidget(covariant OpencodeProviderFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subscription != widget.subscription &&
        _ctl.text != widget.subscription) {
      _ctl.text = widget.subscription;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpInput(
          key: const ValueKey('opencode-provider-subscription'),
          controller: _ctl,
          onChanged: widget.onSubscriptionChanged,
          decoration: InputDecoration(
            labelText: l10n.appProviderOpencodeSubscription,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.appProviderOpencodeSubscriptionHint, style: styles.mutedSm),
      ],
    );
  }
}
