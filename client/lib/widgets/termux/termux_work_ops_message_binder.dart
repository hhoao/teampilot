import 'package:flutter/widgets.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/termux/termux_work_ops_message.dart';

/// Keeps [TermuxWorkOpsMessage] in sync with the active locale under MaterialApp.
class TermuxWorkOpsMessageBinder extends StatelessWidget {
  const TermuxWorkOpsMessageBinder({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    TermuxWorkOpsMessage.bind(context.l10n);
    return child;
  }
}
