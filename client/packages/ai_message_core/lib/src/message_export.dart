import 'dart:convert';

import 'message.dart';

/// Plain-text export for action-bar Copy (assistant-ui Copy semantics).
String plainTextForCopy(AiMessage message) {
  final chunks = <String>[];
  for (final part in message.parts) {
    switch (part) {
      case AiTextPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) chunks.add(t);
      case AiReasoningPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) chunks.add(t);
      case AiToolCallPart(:final toolName, :final isError, :final status):
        final suffix = isError
            ? ' (error)'
            : (status == AiToolCallStatus.incomplete ? ' (incomplete)' : '');
        chunks.add('Used tool: $toolName$suffix');
    }
  }
  return chunks.join('\n\n');
}

/// Markdown export for action-bar Export (assistant-ui ExportMarkdown).
String markdownForExport(AiMessage message) {
  final chunks = <String>[];
  for (final part in message.parts) {
    switch (part) {
      case AiTextPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) chunks.add(t);
      case AiReasoningPart(:final text):
        final t = text.trim();
        if (t.isNotEmpty) {
          chunks.add(
            '<details>\n<summary>Reasoning</summary>\n\n$t\n\n</details>',
          );
        }
      case AiToolCallPart(
        :final toolName,
        :final args,
        :final argsText,
        :final result,
        :final isError,
        :final status,
      ):
        final title = isError
            ? '**Used tool: $toolName** _(error)_'
            : status == AiToolCallStatus.incomplete
            ? '**Used tool: $toolName** _(incomplete)_'
            : '**Used tool: $toolName**';
        final buf = StringBuffer('$title\n');
        final argsBlock = _jsonOrText(argsText, args);
        if (argsBlock != null) {
          buf.writeln('\n```json\n$argsBlock\n```');
        }
        if (result != null) {
          final resultBlock = _stringifyExport(result);
          buf.writeln('\nResult:\n\n```\n$resultBlock\n```');
        }
        chunks.add(buf.toString().trim());
    }
  }
  return chunks.join('\n\n');
}

String? _jsonOrText(String? argsText, Map<String, Object?>? args) {
  final trimmed = argsText?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  if (args == null || args.isEmpty) return null;
  return _stringifyExport(args);
}

String _stringifyExport(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
