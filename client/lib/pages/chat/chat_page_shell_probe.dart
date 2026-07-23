import 'package:flutter/material.dart';

/// Key for the structural workbench body rebuild probe (widget tests).
const chatPageStructuralBodyProbeKey = Key(
  'chat-page-structural-body-probe',
);

/// Keys for widget tests that assert chat page shell rebuild isolation.
@visibleForTesting
class ChatPageShellKeys {
  const ChatPageShellKeys._();

  static const structuralBodyProbe = chatPageStructuralBodyProbeKey;
}

/// Counts [build] invocations for rebuild-isolation widget tests.
@visibleForTesting
class ChatPageStructuralBodyProbe extends StatefulWidget {
  const ChatPageStructuralBodyProbe({required this.child, super.key});

  final Widget child;

  @override
  State<ChatPageStructuralBodyProbe> createState() =>
      ChatPageStructuralBodyProbeState();
}

@visibleForTesting
class ChatPageStructuralBodyProbeState extends State<ChatPageStructuralBodyProbe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return widget.child;
  }
}
