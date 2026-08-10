import 'dart:io';

import 'package:path/path.dart' as p;
import '../../models/run/launch_configuration.dart';

/// Expands VS Code-style launch variables in configuration fields.
///
/// Path-shaped fields ([LaunchConfiguration.cwd], shell `scriptPath`) are
/// resolved through [expandPath], which additionally re-spells the result in
/// the *target machine's* path style. Text/env fields are expanded verbatim —
/// a backslash in a shell script or env value is meaningful and must survive.
class LaunchVariableExpander {
  LaunchVariableExpander._();

  static final RegExp _envPattern = RegExp(r'\$\{env:([^}]+)\}');

  /// Shell extras that name a filesystem path (target-style normalized).
  static const _shellScriptPathKeys = {'scriptPath'};

  /// Shell extras that carry shell text or an executable spec (verbatim).
  static const _shellScriptTextKeys = {
    'scriptText',
    'interpreterPath',
    'interpreterOptions',
    'scriptOptions',
  };

  /// Path style of the local host — the default when no target is resolved.
  static p.Style get hostPathStyle =>
      Platform.isWindows ? p.Style.windows : p.Style.posix;

  static String expand(
    String input, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    var out = input.replaceAll(r'${workspaceFolder}', workspaceFolder);
    out = out.replaceAllMapped(_envPattern, (match) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty) return match.group(0) ?? '';
      return env[key] ?? match.group(0)!;
    });
    return out;
  }

  /// Expands [input] then re-spells it in [style]'s separators.
  static String expandPath(
    String input, {
    required String workspaceFolder,
    Map<String, String> env = const {},
    required p.Style style,
  }) => normalizeForStyle(
    expand(input, workspaceFolder: workspaceFolder, env: env),
    style,
  );

  /// Null-preserving [expandPath].
  static String? expandPathOrNull(
    String? input, {
    required String workspaceFolder,
    Map<String, String> env = const {},
    required p.Style style,
  }) => input == null
      ? null
      : expandPath(
          input,
          workspaceFolder: workspaceFolder,
          env: env,
          style: style,
        );

  /// Re-spells [path] in [style]'s separators and collapses `.`/`..` segments.
  ///
  /// `\` in a template (a Windows-authored config) is a separator, not a
  /// filename character, so POSIX expansion folds it to `/`. Windows expansion
  /// folds `/` to `\` for the reverse case.
  static String normalizeForStyle(String path, p.Style style) {
    // Keep empty/whitespace paths untouched — `p.normalize('')` yields `.`.
    if (path.trim().isEmpty) return path;
    // p.Style values are `static final`, not `const`, so they cannot be used in
    // constant patterns — compare with `==`.
    final String swapped;
    if (style == p.Style.posix) {
      swapped = path.replaceAll(r'\', '/');
    } else if (style == p.Style.windows) {
      swapped = path.replaceAll('/', r'\');
    } else {
      return path;
    }
    // Collapse `.`/`..` only for absolute paths — normalizing a relative path
    // like `./a.sh` would strip its `./` and change its meaning.
    if (!_isAbsoluteForStyle(swapped, style)) return swapped;
    return p.Context(style: style).normalize(swapped);
  }

  static bool _isAbsoluteForStyle(String path, p.Style style) {
    if (style == p.Style.windows) {
      return path.startsWith(r'\\') ||
          RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
    }
    return path.startsWith('/');
  }

  static List<String> expandStringList(
    List<String> values, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    return [
      for (final value in values)
        expand(value, workspaceFolder: workspaceFolder, env: env),
    ];
  }

  static Map<String, String> expandEnvMap(
    Map<String, String> values, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    return {
      for (final entry in values.entries)
        entry.key: expand(
          entry.value,
          workspaceFolder: workspaceFolder,
          env: env,
        ),
    };
  }

  /// Expands a launch configuration. Path fields ([cwd], shell `scriptPath`)
  /// are normalized to [pathStyle]; text/env fields are expanded verbatim.
  ///
  /// [pathStyle] defaults to the local host's style; callers that know the run
  /// target pass `RunTargetPlan.pathStyle` so remote/WSL configs are spelled in
  /// the target machine's style.
  static LaunchConfiguration expandConfiguration(
    LaunchConfiguration configuration, {
    required String workspaceFolder,
    Map<String, String> env = const {},
    p.Style? pathStyle,
  }) {
    final style = pathStyle ?? hostPathStyle;
    final expandedEnv = expandEnvMap(
      configuration.env,
      workspaceFolder: workspaceFolder,
      env: env,
    );
    final mergedEnv = {...env, ...expandedEnv};

    return configuration.copyWith(
      cwd: expandPathOrNull(
        configuration.cwd,
        workspaceFolder: workspaceFolder,
        env: mergedEnv,
        style: style,
      ),
      env: expandedEnv,
      extras: _expandShellScriptExtras(
        configuration.extras,
        workspaceFolder: workspaceFolder,
        env: mergedEnv,
        style: style,
      ),
    );
  }

  static Map<String, Object?> _expandShellScriptExtras(
    Map<String, Object?> extras, {
    required String workspaceFolder,
    required Map<String, String> env,
    required p.Style style,
  }) {
    if (extras.isEmpty) return extras;

    final out = Map<String, Object?>.from(extras);
    for (final key in _shellScriptPathKeys) {
      final value = out[key];
      if (value is! String) continue;
      out[key] = expandPath(
        value,
        workspaceFolder: workspaceFolder,
        env: env,
        style: style,
      );
    }
    for (final key in _shellScriptTextKeys) {
      final value = out[key];
      if (value is! String) continue;
      out[key] = expand(value, workspaceFolder: workspaceFolder, env: env);
    }
    return out;
  }
}
