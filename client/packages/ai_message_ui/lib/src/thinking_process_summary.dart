import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';

/// Aggregated activity counts for a chain-of-thought trigger line.
@immutable
class AiThinkingProcessSummary {
  const AiThinkingProcessSummary({
    this.editedFiles = 0,
    this.exploredFiles = 0,
    this.searches = 0,
    this.commands = 0,
    this.added = 0,
    this.removed = 0,
  });

  /// Unique files from edit/write tool calls.
  final int editedFiles;

  /// Unique files from read tool calls (excluding grep).
  final int exploredFiles;

  /// Grep calls plus [AiToolCallCategory.search] (web fetch/search).
  final int searches;

  /// [AiToolCallCategory.command] calls.
  final int commands;

  /// Sum of edit-hunk additions.
  final int added;

  /// Sum of edit-hunk deletions.
  final int removed;

  bool get hasActivity =>
      editedFiles > 0 || exploredFiles > 0 || searches > 0 || commands > 0;

  @override
  bool operator ==(Object other) =>
      other is AiThinkingProcessSummary &&
      editedFiles == other.editedFiles &&
      exploredFiles == other.exploredFiles &&
      searches == other.searches &&
      commands == other.commands &&
      added == other.added &&
      removed == other.removed;

  @override
  int get hashCode => Object.hash(
    editedFiles,
    exploredFiles,
    searches,
    commands,
    added,
    removed,
  );
}

/// Host-injected formatter for the CoT activity summary (package stays l10n-free).
typedef AiThinkingProcessSummaryFormatter =
    String Function(AiThinkingProcessSummary summary);

/// Counts unique files / tool calls in [parts] for the CoT header.
///
/// File uniqueness uses resolver paths when available, otherwise the tool
/// call id so unresolved calls still appear. Grep is treated as a search
/// even though its stored category is [AiToolCallCategory.read].
AiThinkingProcessSummary summarizeThinkingProcess(
  List<AiMessagePart> parts, {
  AiToolFileTargetResolver? fileResolver,
  AiEditToolTargetResolver? editResolver,
}) {
  final edited = <String>{};
  final explored = <String>{};
  var searches = 0;
  var commands = 0;
  var added = 0;
  var removed = 0;

  for (final part in parts) {
    if (part is! AiToolCallPart) continue;
    if (_isGrepTool(part.toolName) &&
        (part.category == AiToolCallCategory.read ||
            part.category == AiToolCallCategory.search)) {
      searches++;
      continue;
    }
    switch (part.category) {
      case AiToolCallCategory.edit:
      case AiToolCallCategory.write:
        edited.add(
          _resolvedPath(part, fileResolver, editResolver) ??
              'edit:${part.toolCallId}',
        );
        final hunk = editResolver?.resolve(part)?.hunk;
        if (hunk != null) {
          added += hunk.addedCount;
          removed += hunk.removedCount;
        }
      case AiToolCallCategory.read:
        explored.add(
          _resolvedPath(part, fileResolver, editResolver) ??
              'read:${part.toolCallId}',
        );
      case AiToolCallCategory.search:
        searches++;
      case AiToolCallCategory.command:
        commands++;
      case AiToolCallCategory.browser:
      case AiToolCallCategory.subagent:
      case AiToolCallCategory.askUser:
      case AiToolCallCategory.plan:
      case AiToolCallCategory.task:
      case AiToolCallCategory.mcp:
      case AiToolCallCategory.other:
        break;
    }
  }

  return AiThinkingProcessSummary(
    editedFiles: edited.length,
    exploredFiles: explored.length,
    searches: searches,
    commands: commands,
    added: added,
    removed: removed,
  );
}

/// Default English trigger phrase (package stays l10n-free).
String defaultThinkingProcessSummaryLabel(AiThinkingProcessSummary summary) {
  final parts = <String>[
    if (summary.editedFiles > 0)
      summary.editedFiles == 1
          ? 'edited 1 file'
          : 'edited ${summary.editedFiles} files',
    if (summary.exploredFiles > 0)
      summary.exploredFiles == 1
          ? 'explored 1 file'
          : 'explored ${summary.exploredFiles} files',
    if (summary.searches > 0)
      summary.searches == 1 ? '1 search' : '${summary.searches} searches',
    if (summary.commands > 0)
      summary.commands == 1
          ? 'ran 1 command'
          : 'ran ${summary.commands} commands',
  ];
  if (parts.isEmpty) return '';
  final joined = parts.join(', ');
  return '${joined[0].toUpperCase()}${joined.substring(1)}';
}

bool _isGrepTool(String toolName) => toolName.toLowerCase().contains('grep');

String? _resolvedPath(
  AiToolCallPart part,
  AiToolFileTargetResolver? fileResolver,
  AiEditToolTargetResolver? editResolver,
) {
  final hunkPath = editResolver?.resolve(part)?.hunk.path.trim();
  if (hunkPath != null && hunkPath.isNotEmpty) return hunkPath;
  final filePath = fileResolver?.resolve(part)?.path.trim();
  if (filePath != null && filePath.isNotEmpty) return filePath;
  return null;
}
