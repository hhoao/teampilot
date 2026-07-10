import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;

    // Everything links into a single dynamic library asset whose id matches
    // the generated bindings file, so the `@Native` externals resolve without
    // an explicit asset id. See ffigen.yaml `ffi-native` + `assetName` below.
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
        // tree-sitter-json generated parser (no external scanner).
        'third_party/tree-sitter-json/src/parser.c',
        // Stable C ABI shim binding grammars behind `tp_`-prefixed symbols.
        'src/teampilot_ts_api.c',
      ],
      includes: [
        'third_party/tree-sitter/lib/include',
        'third_party/tree-sitter/lib/src',
        'third_party/tree-sitter-json/src',
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
