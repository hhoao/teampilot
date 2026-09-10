import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
// Patch visualStudio.defaultResolver (see _Utf8VisualStudioResolver below).
// ignore: implementation_imports
import 'package:native_toolchain_c/src/native_toolchain/msvc.dart'
    show visualStudio;
// ignore: implementation_imports
import 'package:native_toolchain_c/src/tool/tool_instance.dart';
// ignore: implementation_imports
import 'package:native_toolchain_c/src/tool/tool_resolver.dart';
// ignore: implementation_imports
import 'package:native_toolchain_c/src/utils/sem_version.dart'
    show versionFromString;

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final windows = input.config.code.targetOS == OS.windows;

    // Workaround for native_toolchain_c <= 0.19.4 on non-UTF-8 Windows locales
    // (e.g. zh-CN GBK): upstream runs vswhere with `-utf8` but decodes its
    // stdout with `systemEncoding`, so the JSON closing quote is swallowed by
    // mojibake and `json.decode` throws "Control character in string". Must
    // run before CBuilder touches any MSVC tool — `msvc` / `cl` / `vcvars64`
    // lazily capture `visualStudio.defaultResolver` when their top-level
    // definitions first initialize.
    if (windows) {
      visualStudio.defaultResolver = _Utf8VisualStudioResolver();
    }

    // Everything links into a single dynamic library asset whose id matches
    // the generated bindings file, so the `@Native` externals resolve without
    // an explicit asset id. See ffigen.yaml `ffi-native` + `assetName` below.
    //
    // Every bundled grammar (and its external scanner) is plain C, so the whole
    // asset builds as C11. See third_party/README.md for the pinned versions.
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      language: Language.c,
      // tree-sitter core and generated grammars require C11.
      std: 'c11',
      // Match tree-sitter's own build: strict C11 hides the POSIX/BSD symbols
      // its core relies on (`fdopen`, `le16toh`/`be16toh`). Re-expose them.
      // Harmless on Windows, which ignores these glibc feature-test macros.
      defines: {'_POSIX_C_SOURCE': '200112L', '_DEFAULT_SOURCE': null},
      sources: [
        // tree-sitter core amalgamation (`lib.c` #includes every core .c).
        'third_party/tree-sitter/lib/src/lib.c',
        // Bundled grammars via uniquely named wrappers under src/bundled/.
        // MSVC names .obj files from the source basename, so compiling many
        // third_party/*/parser.c files directly collapses to one parser.obj
        // (LNK4042) and drops earlier grammars at link time on Windows.
        'src/bundled/json_parser.c',
        'src/bundled/dart_parser.c',
        'src/bundled/dart_scanner.c',
        'src/bundled/yaml_parser.c',
        'src/bundled/yaml_scanner.c',
        'src/bundled/python_parser.c',
        'src/bundled/python_scanner.c',
        'src/bundled/rust_parser.c',
        'src/bundled/rust_scanner.c',
        'src/bundled/bash_parser.c',
        'src/bundled/bash_scanner.c',
        'src/bundled/toml_parser.c',
        'src/bundled/toml_scanner.c',
        'src/bundled/css_parser.c',
        'src/bundled/css_scanner.c',
        // typescript: the `tsx` grammar (parses .ts/.tsx/.js/.jsx).
        'src/bundled/tsx_parser.c',
        'src/bundled/tsx_scanner.c',
        // xml: the `xml` grammar.
        'src/bundled/xml_parser.c',
        'src/bundled/xml_scanner.c',
        // markdown: block grammar only (headings/code/lists).
        'src/bundled/markdown_parser.c',
        'src/bundled/markdown_scanner.c',
        // Stable C ABI shim binding grammars behind `tp_`-prefixed symbols.
        'src/teampilot_ts_api.c',
        // Windows: once any symbol uses __declspec(dllexport) (grammars +
        // tp_* shims), MSVC exports *only* those. Tree-sitter's api.h has no
        // Windows dllexport markup, so ts_parser_new/etc. stay hidden and
        // Dart FFI fails with error 127. The .def re-exports the FFI surface.
        // Clang and MSVC both forward .def files to the linker.
        if (windows) 'src/teampilot_tree_sitter.def',
      ],
      includes: [
        'third_party/tree-sitter/lib/include',
        'third_party/tree-sitter/lib/src',
        // Per-grammar src dirs expose each grammar's vendored `tree_sitter/`
        // ABI headers. The typescript/xml `tsx/src` & `xml/src` entries also
        // satisfy `#include "tree_sitter/parser.h"` from their common scanner.
        'third_party/tree-sitter-json/src',
        'third_party/tree-sitter-dart/src',
        'third_party/tree-sitter-yaml/src',
        'third_party/tree-sitter-python/src',
        'third_party/tree-sitter-rust/src',
        'third_party/tree-sitter-bash/src',
        'third_party/tree-sitter-toml/src',
        'third_party/tree-sitter-css/src',
        'third_party/tree-sitter-typescript/tsx/src',
        'third_party/tree-sitter-xml/xml/src',
        'third_party/tree-sitter-markdown/src',
        'src',
      ],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        // ignore: avoid_print
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

/// Drop-in replacement for upstream `VisualStudioResolver` that decodes
/// vswhere's `-utf8` output as UTF-8 instead of `systemEncoding`.
///
/// Mirrors the upstream query (`-format json -utf8 -latest -products *`) and
/// the upstream vswhere search paths, so behavior is identical on machines
/// where the upstream decoder happens to work (ASCII/English locales).
class _Utf8VisualStudioResolver implements ToolResolver {
  static const List<String> _vswherePaths = [
    r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
    r'C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe',
  ];

  @override
  Future<List<ToolInstance>> resolve(ToolResolvingContext context) async {
    String? vswherePath;
    for (final path in _vswherePaths) {
      if (File(path).existsSync()) {
        vswherePath = path;
        break;
      }
    }
    if (vswherePath == null) return const [];

    // Explicit utf8: Process.run defaults to systemEncoding (GBK on zh-CN
    // Windows), which mojibakes vswhere's `-utf8` output.
    final result = await Process.run(
      vswherePath,
      [
        '-format',
        'json',
        '-utf8',
        '-latest',
        '-products',
        '*',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) return const [];

    final logger = context.logger;
    final instances = <ToolInstance>[];
    for (final toolInfo in json.decode(result.stdout as String) as List) {
      final info = toolInfo as Map<String, dynamic>;
      final installationPath = info['installationPath'] as String?;
      final installationVersion = info['installationVersion'] as String?;
      if (installationPath == null || installationVersion == null) continue;
      final dir = Directory(installationPath);
      if (!dir.existsSync()) continue;
      final instance = ToolInstance(
        tool: visualStudio,
        uri: dir.uri,
        version: versionFromString(installationVersion),
      );
      logger?.fine('Found $instance.');
      instances.add(instance);
    }
    return instances;
  }
}
