import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;

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
        // Bundled grammars: generated parser.c plus their C external scanner
        // (json has no external scanner). Each scanner includes its grammar's
        // own vendored `tree_sitter/*.h` via the include paths below.
        'third_party/tree-sitter-json/src/parser.c',
        'third_party/tree-sitter-dart/src/parser.c',
        'third_party/tree-sitter-dart/src/scanner.c',
        'third_party/tree-sitter-yaml/src/parser.c',
        'third_party/tree-sitter-yaml/src/scanner.c',
        'third_party/tree-sitter-python/src/parser.c',
        'third_party/tree-sitter-python/src/scanner.c',
        'third_party/tree-sitter-rust/src/parser.c',
        'third_party/tree-sitter-rust/src/scanner.c',
        'third_party/tree-sitter-bash/src/parser.c',
        'third_party/tree-sitter-bash/src/scanner.c',
        'third_party/tree-sitter-toml/src/parser.c',
        'third_party/tree-sitter-toml/src/scanner.c',
        'third_party/tree-sitter-css/src/parser.c',
        'third_party/tree-sitter-css/src/scanner.c',
        // typescript: the `tsx` grammar (parses .ts/.tsx/.js/.jsx). Its scanner
        // #includes ../../common/scanner.h.
        'third_party/tree-sitter-typescript/tsx/src/parser.c',
        'third_party/tree-sitter-typescript/tsx/src/scanner.c',
        // xml: the `xml` grammar; scanner #includes ../../common/scanner.h.
        'third_party/tree-sitter-xml/xml/src/parser.c',
        'third_party/tree-sitter-xml/xml/src/scanner.c',
        // markdown: block grammar only (headings/code/lists).
        'third_party/tree-sitter-markdown/src/parser.c',
        'third_party/tree-sitter-markdown/src/scanner.c',
        // Stable C ABI shim binding grammars behind `tp_`-prefixed symbols.
        'src/teampilot_ts_api.c',
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
