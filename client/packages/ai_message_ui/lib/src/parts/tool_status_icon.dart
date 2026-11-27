import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class AiToolStatusIcon extends StatelessWidget {
  const AiToolStatusIcon({required this.part, this.color, super.key});

  final AiToolCallPart part;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback =
        color ?? AiMessageTheme.of(context).resolveToolTrigger(scheme);
    final statusColor = switch (part) {
      AiToolCallPart(isError: true) => scheme.error,
      AiToolCallPart(isCancelled: true) => scheme.error,
      AiToolCallPart(status: AiToolCallStatus.complete) => AiMessageTheme.of(
        context,
      ).resolveToolSuccess(scheme),
      AiToolCallPart(status: AiToolCallStatus.running) => scheme.primary,
      _ => fallback,
    };
    final icon = switch (part.status) {
      AiToolCallStatus.running => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
      ),
      AiToolCallStatus.complete => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: statusColor,
      ),
      AiToolCallStatus.incomplete => Icon(
        Icons.highlight_off,
        size: 16,
        color: statusColor,
      ),
      AiToolCallStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: statusColor,
      ),
    };
    return SizedBox(
      width: 16,
      height: 16,
      child: part.isError
          ? Icon(Icons.error_outline, size: 16, color: statusColor)
          : icon,
    );
  }
}
