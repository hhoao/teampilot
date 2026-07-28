import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/skill_pack.dart';
import '../../../models/skill_pack_instruction.dart';

/// Mutable run state shared across install instructions.
class SkillAcquireContext {
  SkillAcquireContext({
    required this.overwrite,
    required this.expectedSkillId,
    this.pack,
    List<String>? shell,
  }) : shell = List<String>.from(
         shell ??
             (Platform.isWindows ? const ['cmd', '/C'] : const ['sh', '-c']),
       );

  final bool overwrite;
  final String expectedSkillId;
  final SkillPack? pack;

  /// Absolute sync / workspace root after a successful `FROM` / `SCRIPT`.
  String? syncRoot;

  /// Repo identity from the last successful `FROM` (for SKILLS git install).
  String? syncOwner;
  String? syncName;
  String? syncBranch;

  /// Relative path under [syncRoot], or empty for sync root itself.
  String workdir = '';

  /// Wrapper argv for string-form `RUN` (e.g. `sh -c` / `cmd /C`).
  List<String> shell;

  final List<String> installedSkillIds = [];
  final List<String> pathExports = [];
  final Map<String, String> envExports = {};

  bool get hasWorkspace {
    final root = syncRoot;
    return root != null && root.isNotEmpty;
  }

  /// Absolute cwd for `RUN` / `COPY` destinations.
  String get effectiveWorkdir {
    final root = syncRoot;
    if (root == null || root.isEmpty) {
      throw StateError('no sync root');
    }
    if (workdir.isEmpty) return root;
    return resolveRelative(workdir);
  }

  /// Resolves [relative] under [syncRoot]; rejects absolutes and `..` escape.
  String resolveRelative(String relative) {
    final root = syncRoot;
    if (root == null || root.isEmpty) {
      throw StateError('no sync root');
    }
    try {
      return resolveUnderRoot(root: root, relative: relative);
    } on FormatException catch (e) {
      throw StateError(e.message);
    }
  }

  /// Resolves [relative] under current [effectiveWorkdir].
  String resolveWorkdirRelative(String relative) {
    final base = effectiveWorkdir;
    try {
      return resolveUnderRoot(root: base, relative: relative);
    } on FormatException catch (e) {
      throw StateError(e.message);
    }
  }

  void appendPathExports(Iterable<String> absPaths) {
    for (final path in absPaths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty) continue;
      if (!pathExports.contains(trimmed)) {
        pathExports.add(trimmed);
      }
    }
  }

  void mergeEnv(Map<String, String> entries) {
    envExports.addAll(entries);
  }

  /// Joins with the platform path context when available.
  String joinUnder(String root, String relative) =>
      p.Context(style: p.Style.posix).join(root, relative);
}
