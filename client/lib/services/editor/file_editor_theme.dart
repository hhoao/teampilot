import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../theme/workspace_surface_layers.dart';

/// Extensions we treat as plain text for in-app editing (allowlist).
///
/// Everything else opens with the system default app. Safer than a binary
/// blocklist: unknown formats (Office, media, …) never look "editable".
const kEditorTextExtensions = {
  // Highlighted in [highlightLanguageKeyForPath].
  'dart',
  'json',
  'yaml',
  'yml',
  'md',
  'markdown',
  'py',
  'rs',
  'ts',
  'tsx',
  'js',
  'jsx',
  'mjs',
  'cjs',
  'sh',
  'bash',
  'zsh',
  'fish',
  'xml',
  'html',
  'htm',
  'xhtml',
  'toml',
  'css',
  'scss',
  'sass',
  'less',
  // Other common text / code (no dedicated highlighter).
  'txt',
  'text',
  'log',
  'csv',
  'tsv',
  'sql',
  'c',
  'h',
  'cc',
  'cpp',
  'cxx',
  'hpp',
  'hh',
  'go',
  'mod',
  'sum',
  'java',
  'kt',
  'kts',
  'swift',
  'rb',
  'erb',
  'php',
  'vue',
  'svelte',
  'lua',
  'zig',
  'hs',
  'elm',
  'clj',
  'cljs',
  'ex',
  'exs',
  'ml',
  'mli',
  'fs',
  'fsx',
  'r',
  'pl',
  'pm',
  'awk',
  'gradle',
  'groovy',
  'tf',
  'hcl',
  'ini',
  'cfg',
  'conf',
  'config',
  'properties',
  'env',
  'plist',
  'svg',
  'graphql',
  'gql',
  'proto',
  'cmake',
  'ninja',
  'lock',
  'patch',
  'diff',
};

/// Extensionless files that are still plain text (checked case-insensitively).
const kEditorTextBasenames = {
  'dockerfile',
  'containerfile',
  'makefile',
  'gnumakefile',
  'cmakelists.txt',
  'license',
  'licence',
  'readme',
  'changelog',
  'gemfile',
  'rakefile',
  'procfile',
  'vagrantfile',
  'brewfile',
  'justfile',
};

/// Maximum file size loaded into the editor (bytes).
const kEditorMaxFileBytes = 2 * 1024 * 1024;

/// Whether [filePath] should open in the in-app text editor.
bool isEditorOpenableFilePath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  if (ext.isNotEmpty) {
    return kEditorTextExtensions.contains(ext);
  }
  final base = p.basename(filePath).toLowerCase();
  return kEditorTextBasenames.contains(base);
}

String? highlightLanguageKeyForPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return switch (ext) {
    'dart' => 'dart',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'md' || 'markdown' => 'markdown',
    'py' => 'python',
    'rs' => 'rust',
    'ts' || 'tsx' => 'typescript',
    'js' || 'jsx' => 'typescript',
    'sh' || 'bash' => 'bash',
    'xml' || 'html' || 'htm' => 'xml',
    'toml' => 'yaml',
    'css' || 'scss' => 'xml',
    _ => null,
  };
}

Mode? highlightModeForKey(String key) => switch (key) {
  'dart' => langDart,
  'json' => langJson,
  'yaml' => langYaml,
  'markdown' => langMarkdown,
  'python' => langPython,
  'rust' => langRust,
  'typescript' => langTypescript,
  'bash' => langBash,
  'xml' => langXml,
  _ => null,
};

CodeHighlightTheme? codeHighlightThemeFor(
  BuildContext context,
  String filePath,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final key = highlightLanguageKeyForPath(filePath);
  final mode = key == null ? null : highlightModeForKey(key);
  if (mode == null || key == null) {
    return null;
  }
  return CodeHighlightTheme(
    languages: {key: CodeHighlightThemeMode(mode: mode)},
    theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
  );
}

/// Editor monospace size from [AppTypographyTheme.mono].
double fileEditorFontSize(BuildContext context) => context.appTypography.mono;

CodeEditorStyle codeEditorStyleFor(BuildContext context, String filePath) {
  final cs = Theme.of(context).colorScheme;
  final fonts = context.appFonts;
  final textScaler = MediaQuery.textScalerOf(context);
  return CodeEditorStyle(
    fontSize: textScaler.scale(fileEditorFontSize(context)),
    fontHeight: 1.35,
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    textColor: cs.onSurface,
    backgroundColor: cs.workspaceCode,
    selectionColor: cs.primary.withValues(alpha: 0.28),
    highlightColor: cs.tertiary.withValues(alpha: 0.35),
    cursorColor: cs.primary,
    cursorLineColor: cs.primary.withValues(alpha: 0.12),
    codeTheme: codeHighlightThemeFor(context, filePath),
  );
}
