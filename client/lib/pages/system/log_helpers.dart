import 'package:flutter/material.dart';

import '../../theme/app_fonts.dart';

TextStyle logMonospaceStyle(BuildContext context, {Color? color}) {
  final cs = Theme.of(context).colorScheme;
  return appMonoTextStyle(
    context,
    base: Theme.of(context).textTheme.bodySmall,
    height: 1.45,
    color: color ?? cs.onSurface.withValues(alpha: 0.92),
  );
}

bool isLogDecorationLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  if (t.startsWith('│ #') ||
      t.startsWith('├') ||
      t.startsWith('└') ||
      t.startsWith('┌')) {
    return true;
  }
  return RegExp(r'^[│┌┐└┘├┤─\s#0-9.:]+$').hasMatch(t);
}

Color? logLineColor(BuildContext context, String line) {
  final upper = line.toUpperCase();
  final cs = Theme.of(context).colorScheme;
  if (upper.contains('ERROR') || upper.contains('EXCEPTION')) {
    return cs.error;
  }
  if (upper.contains('WARNING') || upper.contains('WARN')) {
    return cs.tertiary;
  }
  if (upper.contains('DEBUG')) {
    return cs.onSurfaceVariant;
  }
  return null;
}
