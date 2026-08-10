import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import 'package:logger/logger.dart';
import '../../../../../utils/logging/logger.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/session_history_context.dart';
import 'terminal_file.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';

final class CursorTerminalToolResultEnricher implements ToolResultEnricher {
  const CursorTerminalToolResultEnricher({
    required this.shellResolver,
  });

  final AiShellToolTargetResolver shellResolver;

  @override
  bool get requiresFilesystem => true;

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async {
    final fs = ctx?.fs;
    if (fs == null) return messages;

    final transcriptPath = rootTranscriptPath?.trim();
    if (transcriptPath == null || transcriptPath.isEmpty) return messages;

    final terminalsDir = _cursorTerminalsDirFor(
      transcriptPath,
      pathContext: fs.pathContext,
    );
    if (terminalsDir == null) return messages;

    try {
      final terminalFiles = await _loadTerminalFiles(fs, terminalsDir);
      if (terminalFiles.isEmpty) return messages;

      final pool = List<_TerminalCandidate>.from(terminalFiles);
      final updated = List<AiMessage>.from(messages);

      for (var i = 0; i < updated.length; i++) {
        final message = updated[i];
        final parts = List<AiMessagePart>.from(message.parts);
        var changed = false;

        for (var j = 0; j < parts.length; j++) {
          final part = parts[j];
          if (part is! AiToolCallPart || !_isResultMissing(part.result)) continue;

          final target = shellResolver.resolve(part);
          if (target == null) continue;

          final matchIndex = _pickTerminalIndex(
            pool: pool,
            target: target,
            referenceTime: message.createdAt,
          );
          if (matchIndex == null) continue;

          final terminal = pool.removeAt(matchIndex);
          parts[j] = part.copyWith(
            result: terminal.file.body,
            status: AiToolCallStatus.complete,
            isError: part.isError ||
                (terminal.file.exitCode != null && terminal.file.exitCode != 0),
          );
          changed = true;
        }

        if (changed) {
          updated[i] = message.copyWith(parts: parts);
        }
      }

      return updated;
    } catch (e, st) {
      appLogger.w(
        '[tool-result-enricher] Cursor terminals enrich failed path=$transcriptPath: $e',
        error: e,
        stackTrace: st,
      );
      return messages;
    }
  }
}

final class _TerminalCandidate {
  const _TerminalCandidate({required this.path, required this.file});

  final String path;
  final CursorTerminalFile file;
}

String? _cursorTerminalsDirFor(
  String transcriptPath, {
  required p.Context pathContext,
}) {
  final normalized = pathContext.normalize(transcriptPath);
  final parentDir = pathContext.dirname(normalized);
  final stem = pathContext.basenameWithoutExtension(normalized);
  if (stem.isEmpty) return null;

  final projectRoot = pathContext.basename(parentDir) == stem
      ? pathContext.dirname(pathContext.dirname(parentDir))
      : pathContext.dirname(parentDir);

  return pathContext.join(projectRoot, 'terminals');
}

Future<List<_TerminalCandidate>> _loadTerminalFiles(
  Filesystem fs,
  String terminalsDir,
) async {
  final stat = await fs.stat(terminalsDir);
  if (!stat.isDirectory) return const [];

  final candidates = <_TerminalCandidate>[];
  for (final entry in await fs.listDir(terminalsDir)) {
    if (!entry.isDirectory && entry.name.endsWith('.txt')) {
      final path = fs.pathContext.join(terminalsDir, entry.name);
      final raw = await fs.readString(path);
      if (raw == null) continue;
      final parsed = parseCursorTerminalFile(raw);
      if (parsed == null) continue;
      candidates.add(_TerminalCandidate(path: path, file: parsed));
    }
  }
  return candidates;
}

bool _isResultMissing(Object? result) {
  if (result == null) return true;
  final text = result is String ? result : result.toString();
  return text.trim().isEmpty;
}

String _normalizeCommand(String command) =>
    command.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

int? _pickTerminalIndex({
  required List<_TerminalCandidate> pool,
  required AiShellToolTarget target,
  required DateTime? referenceTime,
}) {
  if (pool.isEmpty) return null;

  final normalizedCommand = _normalizeCommand(target.command);
  final description = target.description?.trim();

  final tier1 = <int>[];
  final tier2 = <int>[];

  for (var i = 0; i < pool.length; i++) {
    final terminal = pool[i].file;
    final terminalCommand = _normalizeCommand(terminal.command);
    if (terminalCommand != normalizedCommand) continue;

    final title = terminal.title?.trim();
    if (description != null && description.isNotEmpty) {
      if (title == description) tier1.add(i);
    } else {
      tier2.add(i);
    }
  }

  final matches = tier1.isNotEmpty ? tier1 : tier2;
  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.single;

  return _pickBestTie(
    pool: pool,
    indices: matches,
    referenceTime: referenceTime,
  );
}

int _pickBestTie({
  required List<_TerminalCandidate> pool,
  required List<int> indices,
  required DateTime? referenceTime,
}) {
  if (referenceTime != null) {
    int? bestIndex;
    Duration? bestDistance;
    for (final index in indices) {
      final startedAt = _parseIso(pool[index].file.startedAt);
      if (startedAt == null) continue;
      final distance = startedAt.difference(referenceTime).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    if (bestIndex != null) return bestIndex;
  }

  int bestIndex = indices.first;
  DateTime? bestTime;
  for (final index in indices) {
    final terminal = pool[index].file;
    final candidateTime =
        _parseIso(terminal.endedAt) ?? _parseIso(terminal.startedAt);
    if (candidateTime == null) continue;
    if (bestTime == null || candidateTime.isAfter(bestTime)) {
      bestTime = candidateTime;
      bestIndex = index;
    }
  }
  return bestIndex;
}

DateTime? _parseIso(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}
