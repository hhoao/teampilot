import 'package:flutter/foundation.dart';

const _instructionKeys = <String>{
  'COPY',
  'ENV',
  'FROM',
  'PATH',
  'RUN',
  'SCRIPT',
  'SHELL',
  'SKILLS',
  'WORKDIR',
};

const _modifierKeys = <String>{'optional'};

/// One Dockerfile-like install step in a skill pack.
sealed class SkillPackInstruction {
  const SkillPackInstruction();
}

@immutable
final class FromInstruction extends SkillPackInstruction {
  const FromInstruction({
    required this.owner,
    required this.name,
    required this.branch,
  });

  final String owner;
  final String name;
  final String branch;

  static FromInstruction parseRef(String ref) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('FROM: empty repository reference');
    }

    var ownerName = trimmed;
    var branch = 'main';
    final atIndex = trimmed.lastIndexOf('@');
    if (atIndex >= 0) {
      ownerName = trimmed.substring(0, atIndex).trim();
      final branchPart = trimmed.substring(atIndex + 1).trim();
      if (branchPart.isNotEmpty) {
        branch = branchPart;
      }
    }

    final slashIndex = ownerName.indexOf('/');
    if (slashIndex <= 0 || slashIndex == ownerName.length - 1) {
      throw FormatException('FROM: invalid repository reference "$ref"');
    }

    return FromInstruction(
      owner: ownerName.substring(0, slashIndex),
      name: ownerName.substring(slashIndex + 1),
      branch: branch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FromInstruction &&
      owner == other.owner &&
      name == other.name &&
      branch == other.branch;

  @override
  int get hashCode => Object.hash(owner, name, branch);
}

@immutable
final class ScriptInstruction extends SkillPackInstruction {
  const ScriptInstruction({
    required this.url,
    this.id,
    this.primaryDirectory,
    this.alternatives = const [],
    this.optional = false,
  });

  final String url;
  final String? id;
  final String? primaryDirectory;
  final List<String> alternatives;
  final bool optional;

  @override
  bool operator ==(Object other) =>
      other is ScriptInstruction &&
      url == other.url &&
      id == other.id &&
      primaryDirectory == other.primaryDirectory &&
      listEquals(alternatives, other.alternatives) &&
      optional == other.optional;

  @override
  int get hashCode => Object.hash(
    url,
    id,
    primaryDirectory,
    Object.hashAll(alternatives),
    optional,
  );
}

@immutable
final class CopyInstruction extends SkillPackInstruction {
  const CopyInstruction({required this.from, required this.to});

  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is CopyInstruction && from == other.from && to == other.to;

  @override
  int get hashCode => Object.hash(from, to);
}

@immutable
final class SkillsInstruction extends SkillPackInstruction {
  const SkillsInstruction({
    required this.includeAll,
    this.include = const [],
    this.exclude = const [],
  });

  final bool includeAll;
  final List<String> include;
  final List<String> exclude;

  @override
  bool operator ==(Object other) =>
      other is SkillsInstruction &&
      includeAll == other.includeAll &&
      listEquals(include, other.include) &&
      listEquals(exclude, other.exclude);

  @override
  int get hashCode =>
      Object.hash(includeAll, Object.hashAll(include), Object.hashAll(exclude));
}

@immutable
final class ShellInstruction extends SkillPackInstruction {
  const ShellInstruction(this.wrapper);

  final List<String> wrapper;

  @override
  bool operator ==(Object other) =>
      other is ShellInstruction && listEquals(wrapper, other.wrapper);

  @override
  int get hashCode => Object.hashAll(wrapper);
}

@immutable
final class RunInstruction extends SkillPackInstruction {
  const RunInstruction({
    this.shell,
    this.exec,
    this.optional = false,
  }) : assert(shell != null || exec != null);

  final String? shell;
  final List<String>? exec;
  final bool optional;

  @override
  bool operator ==(Object other) =>
      other is RunInstruction &&
      shell == other.shell &&
      listEquals(exec, other.exec) &&
      optional == other.optional;

  @override
  int get hashCode {
    final execArgs = exec;
    return Object.hash(
      shell,
      execArgs == null ? null : Object.hashAll(execArgs),
      optional,
    );
  }
}

@immutable
final class WorkdirInstruction extends SkillPackInstruction {
  const WorkdirInstruction(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is WorkdirInstruction && path == other.path;

  @override
  int get hashCode => path.hashCode;
}

@immutable
final class PathInstruction extends SkillPackInstruction {
  const PathInstruction(this.entries);

  final List<String> entries;

  @override
  bool operator ==(Object other) =>
      other is PathInstruction && listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

@immutable
final class EnvInstruction extends SkillPackInstruction {
  const EnvInstruction(this.entries);

  final Map<String, String> entries;

  @override
  bool operator ==(Object other) =>
      other is EnvInstruction && mapEquals(entries, other.entries);

  @override
  int get hashCode =>
      Object.hashAll(entries.entries.map((e) => Object.hash(e.key, e.value)));
}

/// Parses a pack `install` array into typed instructions.
List<SkillPackInstruction> parseSkillPackInstall(List<Object?> raw) {
  final result = <SkillPackInstruction>[];
  for (var i = 0; i < raw.length; i++) {
    result.add(_parseInstructionElement(raw[i], index: i));
  }
  return result;
}

SkillPackInstruction _parseInstructionElement(Object? raw, {required int index}) {
  if (raw is! Map) {
    throw FormatException('install[$index]: expected object');
  }
  final map = raw.map((key, value) => MapEntry(key.toString(), value));

  final unknownKeys = map.keys
      .where((key) => !_instructionKeys.contains(key) && !_modifierKeys.contains(key))
      .toList(growable: false);
  if (unknownKeys.isNotEmpty) {
    throw FormatException('install[$index]: unknown key ${unknownKeys.first}');
  }

  final instructionKeys = map.keys.where(_instructionKeys.contains).toList();
  if (instructionKeys.length != 1) {
    throw FormatException(
      instructionKeys.isEmpty
          ? 'install[$index]: missing instruction key'
          : 'install[$index]: expected exactly one instruction key',
    );
  }

  final key = instructionKeys.single;
  final optional = map['optional'] == true;
  if (optional && key != 'RUN' && key != 'SCRIPT') {
    throw FormatException('install[$index] $key: optional not allowed');
  }

  return switch (key) {
    'FROM' => _parseFrom(map['FROM'], index: index),
    'SCRIPT' => _parseScript(map['SCRIPT'], index: index, optional: optional),
    'COPY' => _parseCopy(map['COPY'], index: index),
    'SKILLS' => _parseSkills(map['SKILLS'], index: index),
    'SHELL' => _parseShell(map['SHELL'], index: index),
    'RUN' => _parseRun(map['RUN'], index: index, optional: optional),
    'WORKDIR' => _parseWorkdir(map['WORKDIR'], index: index),
    'PATH' => _parsePath(map['PATH'], index: index),
    'ENV' => _parseEnv(map['ENV'], index: index),
    _ => throw FormatException('install[$index]: unknown key $key'),
  };
}

FromInstruction _parseFrom(Object? raw, {required int index}) {
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('install[$index] FROM: expected non-empty string');
  }
  try {
    return FromInstruction.parseRef(raw);
  } on FormatException catch (error) {
    throw FormatException('install[$index] FROM: ${error.message}');
  }
}

ScriptInstruction _parseScript(
  Object? raw, {
  required int index,
  required bool optional,
}) {
  if (raw is String) {
    final url = raw.trim();
    if (url.isEmpty) {
      throw FormatException('install[$index] SCRIPT: expected non-empty url');
    }
    return ScriptInstruction(url: url, optional: optional);
  }
  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final unknownKeys = map.keys
        .where(
          (key) =>
              key != 'alternatives' &&
              key != 'id' &&
              key != 'primaryDirectory' &&
              key != 'url',
        )
        .toList();
    if (unknownKeys.isNotEmpty) {
      throw FormatException('install[$index] SCRIPT: unknown key ${unknownKeys.first}');
    }
    final url = (map['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      throw FormatException('install[$index] SCRIPT: expected non-empty url');
    }
    final alternativesRaw = map['alternatives'];
    return ScriptInstruction(
      url: url,
      id: (map['id'] as String?)?.trim(),
      primaryDirectory: (map['primaryDirectory'] as String?)?.trim(),
      alternatives: alternativesRaw is List
          ? alternativesRaw
                .map((entry) => entry.toString().trim())
                .where((entry) => entry.isNotEmpty)
                .toList(growable: false)
          : const [],
      optional: optional,
    );
  }
  throw FormatException('install[$index] SCRIPT: expected string or object');
}

CopyInstruction _parseCopy(Object? raw, {required int index}) {
  if (raw is! List || raw.length != 2) {
    throw FormatException('install[$index] COPY: expected [from, to]');
  }
  final from = raw[0]?.toString().trim() ?? '';
  final to = raw[1]?.toString().trim() ?? '';
  if (from.isEmpty || to.isEmpty) {
    throw FormatException('install[$index] COPY: from and to must be non-empty');
  }
  return CopyInstruction(from: from, to: to);
}

SkillsInstruction _parseSkills(Object? raw, {required int index}) {
  if (raw == '*') {
    return const SkillsInstruction(includeAll: true);
  }
  if (raw is List) {
    final include = raw
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (include.isEmpty) {
      throw FormatException('install[$index] SKILLS: expected non-empty list');
    }
    if (include.length == 1 && include.single == '*') {
      return const SkillsInstruction(includeAll: true);
    }
    return SkillsInstruction(includeAll: false, include: include);
  }
  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final unknownKeys = map.keys.where((key) => key != 'include' && key != 'exclude').toList();
    if (unknownKeys.isNotEmpty) {
      throw FormatException('install[$index] SKILLS: unknown key ${unknownKeys.first}');
    }

    final excludeRaw = map['exclude'];
    final exclude = excludeRaw is List
        ? excludeRaw
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final includeRaw = map['include'];
    if (includeRaw == null) {
      return SkillsInstruction(includeAll: true, exclude: exclude);
    }
    if (includeRaw == '*') {
      return SkillsInstruction(includeAll: true, exclude: exclude);
    }
    if (includeRaw is List) {
      final include = includeRaw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      if (include.isEmpty) {
        throw FormatException('install[$index] SKILLS: expected non-empty include list');
      }
      if (include.length == 1 && include.single == '*') {
        return SkillsInstruction(includeAll: true, exclude: exclude);
      }
      return SkillsInstruction(includeAll: false, include: include, exclude: exclude);
    }
    throw FormatException('install[$index] SKILLS: invalid include value');
  }
  throw FormatException('install[$index] SKILLS: expected "*", list, or object');
}

ShellInstruction _parseShell(Object? raw, {required int index}) {
  if (raw is! List || raw.isEmpty) {
    throw FormatException('install[$index] SHELL: expected non-empty string list');
  }
  final wrapper = raw
      .map((entry) => entry.toString().trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (wrapper.isEmpty) {
    throw FormatException('install[$index] SHELL: expected non-empty string list');
  }
  return ShellInstruction(wrapper);
}

RunInstruction _parseRun(
  Object? raw, {
  required int index,
  required bool optional,
}) {
  if (raw is String) {
    final shell = raw.trim();
    if (shell.isEmpty) {
      throw FormatException('install[$index] RUN: empty command');
    }
    return RunInstruction(shell: shell, optional: optional);
  }
  if (raw is List) {
    final exec = raw
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (exec.isEmpty) {
      throw FormatException('install[$index] RUN: empty command');
    }
    return RunInstruction(exec: exec, optional: optional);
  }
  throw FormatException('install[$index] RUN: expected string or string list');
}

WorkdirInstruction _parseWorkdir(Object? raw, {required int index}) {
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('install[$index] WORKDIR: expected non-empty string');
  }
  return WorkdirInstruction(raw.trim());
}

PathInstruction _parsePath(Object? raw, {required int index}) {
  final entries = _parseStringOrStringList(
    raw,
    index: index,
    key: 'PATH',
    allowEmpty: false,
  );
  return PathInstruction(entries);
}

EnvInstruction _parseEnv(Object? raw, {required int index}) {
  if (raw is! Map) {
    throw FormatException('install[$index] ENV: expected object');
  }
  final entries = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) {
      continue;
    }
    entries[key] = entry.value?.toString() ?? '';
  }
  return EnvInstruction(Map.unmodifiable(entries));
}

List<String> _parseStringOrStringList(
  Object? raw, {
  required int index,
  required String key,
  required bool allowEmpty,
}) {
  if (raw is String) {
    final value = raw.trim();
    if (!allowEmpty && value.isEmpty) {
      throw FormatException('install[$index] $key: expected non-empty string');
    }
    return value.isEmpty ? const [] : [value];
  }
  if (raw is List) {
    final values = raw
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (!allowEmpty && values.isEmpty) {
      throw FormatException('install[$index] $key: expected non-empty list');
    }
    return values;
  }
  throw FormatException('install[$index] $key: expected string or string list');
}

/// Resolves [relative] under [root], rejecting absolute paths and `..` escape.
String resolveUnderRoot({required String root, required String relative}) {
  if (relative.trim().isEmpty) {
    throw const FormatException('empty relative path');
  }
  if (_isAbsolutePath(relative)) {
    throw FormatException('absolute path not allowed: $relative');
  }

  final normalizedRoot = root.replaceAll(r'\', '/');
  final absoluteUnix = normalizedRoot.startsWith('/');
  final rootSegments = _splitPathSegments(root);
  final relativeSegments = _splitPathSegments(relative);
  final resolved = <String>[...rootSegments];
  for (final segment in relativeSegments) {
    if (segment == '..') {
      if (resolved.length <= rootSegments.length) {
        throw FormatException('path escapes root: $relative');
      }
      resolved.removeLast();
      continue;
    }
    resolved.add(segment);
  }
  final joined = resolved.join('/');
  if (absoluteUnix) {
    return '/$joined';
  }
  // Preserve Windows drive-letter absolute roots (e.g. C:/...).
  if (normalizedRoot.length >= 2 &&
      normalizedRoot[1] == ':' &&
      rootSegments.isNotEmpty) {
    return joined;
  }
  return joined;
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/') || path.startsWith(r'\')) {
    return true;
  }
  return path.length >= 2 && path[1] == ':';
}

List<String> _splitPathSegments(String path) {
  return path
      .replaceAll(r'\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

/// Stable script skill id from package URL: `script:<host>/<path-basename>`.
String skillScriptIdFromPackageUrl(String? package) {
  if (package == null || package.trim().isEmpty) {
    return 'script:unknown';
  }
  final uri = Uri.tryParse(package.trim());
  if (uri == null || uri.host.isEmpty) {
    return 'script:unknown';
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final basename = segments.isEmpty ? 'unknown' : segments.last;
  return 'script:${uri.host}/$basename';
}
