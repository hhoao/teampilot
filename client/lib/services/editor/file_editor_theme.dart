import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../theme/workspace_surface_layers.dart';
import '../editor_platform/editor_syntax_theme.dart';

/// Extensions we treat as plain text for in-app editing (allowlist).
///
/// Everything else opens with the system default app. Safer than a binary
/// blocklist: unknown formats (Office, media, …) never look "editable".
const kEditorTextExtensions = {
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

const kEditorImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
};

/// Max image bytes loaded for in-app preview (separate from text editor cap).
const kEditorMaxImageBytes = 25 * 1024 * 1024;

/// Whether [filePath] should open in the in-app text editor.
bool isEditorOpenableFilePath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  if (ext.isNotEmpty) {
    return kEditorTextExtensions.contains(ext);
  }
  final base = p.basename(filePath).toLowerCase();
  return kEditorTextBasenames.contains(base);
}

bool isImagePreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kEditorImageExtensions.contains(ext);
}

const kHtmlPreviewExtensions = {'html', 'htm'};

/// Whether [filePath] supports the in-app rendered HTML preview (Edit|Preview).
bool isHtmlPreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kHtmlPreviewExtensions.contains(ext);
}

bool isWorkbenchOpenableFilePath(String filePath) =>
    isEditorOpenableFilePath(filePath) || isImagePreviewPath(filePath);

/// Editor monospace size from [AppTypographyTheme.mono].
double fileEditorFontSize(BuildContext context) => context.appTypography.mono;

CodeEditorStyle codeEditorStyleFor(
  BuildContext context,
  String filePath, {
  CodeTokenProvider? tokenProvider,
  Color? backgroundColor,
}) {
  final cs = Theme.of(context).colorScheme;
  final fonts = context.tpFonts;
  final textScaler = MediaQuery.textScalerOf(context);
  final theme = EditorSyntaxTheme.forBrightness(Theme.of(context).brightness);
  return CodeEditorStyle(
    fontSize: textScaler.scale(fileEditorFontSize(context)),
    fontHeight: 1.35,
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    textColor: cs.onSurface,
    backgroundColor: backgroundColor ?? cs.workspaceCode,
    selectionColor: cs.primary.withValues(alpha: 0.28),
    highlightColor: cs.tertiary.withValues(alpha: 0.35),
    cursorColor: cs.primary,
    cursorLineColor: cs.primary.withValues(alpha: 0.12),
    tokenProvider: tokenProvider,
    syntaxTheme: theme.asStyleMap(),
  );
}
