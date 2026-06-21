import 'dart:convert';

import '../../models/git_worktree.dart';
import '../cli/cli_tool_locator.dart';
// ignore: unused_import — GitException is used by list/add/remove in a later task.
import 'git_service.dart' show GitException;

/// Runs `git worktree …` for the worktree sidebar. Desktop-local only;
/// mirrors [GitService]'s injected [ProcessRunner] seam so tests never spawn
/// real git. Listing/parsing is path-derived; nothing is persisted.
class GitWorktreeService {
  GitWorktreeService({
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? gitLocator,
  })  : _runner = runner,
        _gitLocator = gitLocator ?? const CliToolLocator('git');

  // ignore: unused_field — used by list/add/remove in a later task.
  final ProcessRunner _runner;
  // ignore: unused_field — used by list/add/remove in a later task.
  final CliToolLocator _gitLocator;

  // ignore: unused_field — used by list/add/remove in a later task.
  static const Encoding _textEncoding = Utf8Codec(allowMalformed: true);
  // ignore: unused_field — used by list/add/remove in a later task.
  static const List<String> _globalFlags = [
    '--no-optional-locks',
    '-c',
    'core.quotePath=false',
  ];

  /// Parse `git worktree list --porcelain` output. [nulDelimited] for the
  /// `-z` form (fields NUL-delimited, records terminated by an extra NUL).
  static List<GitWorktree> parseWorktreeList(
    String output, {
    required bool nulDelimited,
  }) {
    final blocks =
        nulDelimited ? _splitNulBlocks(output) : _splitLineBlocks(output);
    final result = <GitWorktree>[];
    for (final lines in blocks) {
      if (lines.isEmpty) continue;
      var path = '';
      var head = '';
      var branch = '';
      var isBare = false;
      for (final line in lines) {
        if (line.startsWith('worktree ')) {
          path = line.substring('worktree '.length);
        } else if (line.startsWith('HEAD ')) {
          head = line.substring('HEAD '.length);
        } else if (line.startsWith('branch ')) {
          branch = line.substring('branch '.length);
        } else if (line == 'bare') {
          isBare = true;
        }
        // 'detached' → leave branch empty (isDetached getter returns true).
      }
      if (path.isEmpty) continue;
      result.add(GitWorktree(
        path: path,
        head: head,
        branch: branch,
        isBare: isBare,
        isMainWorktree: result.isEmpty,
      ));
    }
    return result;
  }

  static List<List<String>> _splitLineBlocks(String output) => output
      .trim()
      .split(RegExp(r'\r?\n\r?\n'))
      .where((b) => b.trim().isNotEmpty)
      .map((b) => b.trim().split(RegExp(r'\r?\n')))
      .toList();

  /// Split NUL-delimited (`-z`) porcelain output into blocks.
  ///
  /// `git worktree list --porcelain -z` emits fields separated by `\x00`
  /// and terminates each record with an extra `\x00` (so two consecutive
  /// NULs mark the record boundary). Splitting on `\x00` gives a sequence
  /// of field strings; an empty string signals the end of a record.
  static List<List<String>> _splitNulBlocks(String output) {
    const nul = '\x00';
    if (!output.contains(nul)) return _splitLineBlocks(output);
    final blocks = <List<String>>[];
    var current = <String>[];
    for (final field in output.split(nul)) {
      if (field.isNotEmpty) {
        current.add(field);
      } else if (current.isNotEmpty) {
        blocks.add(current);
        current = <String>[];
      }
    }
    if (current.isNotEmpty) blocks.add(current);
    return blocks;
  }
}
