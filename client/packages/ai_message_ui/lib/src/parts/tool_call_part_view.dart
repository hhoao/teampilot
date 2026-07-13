import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Collapsible tool-call card (collapsed by default).
class AiToolCallPartView extends StatelessWidget {
  const AiToolCallPartView({required this.part, super.key});

  final AiToolCallPart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = theme.extension<AiMessageTheme>();
    final cardColor = aiTheme?.toolCardColor ??
        scheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final borderColor = aiTheme?.toolCardBorderColor ??
        scheme.outlineVariant.withValues(alpha: 0.6);

    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          leading: Icon(
            Icons.terminal_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(
            part.toolName,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _expandedBody(part),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: part.isError ? scheme.error : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _expandedBody(AiToolCallPart part) {
  final buffer = StringBuffer();
  final argsText = part.argsText?.trim();
  if (argsText != null && argsText.isNotEmpty) {
    buffer.writeln(argsText);
  } else if (part.args != null && part.args!.isNotEmpty) {
    buffer.writeln(
      const JsonEncoder.withIndent('  ').convert(part.args),
    );
  }
  if (part.result != null) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(_stringify(part.result));
  }
  return buffer.toString().trimRight();
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
