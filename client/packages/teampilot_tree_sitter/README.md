# teampilot_tree_sitter

Dart FFI bindings for [tree-sitter](https://tree-sitter.github.io/) plus a set
of native grammars, statically linked into a single native asset. Powers
viewport-first syntax highlighting in the TeamPilot editor — no wasm, no runtime
download.

## Layout

- `third_party/` — vendored, pinned tree-sitter core + grammar C sources. See
  [`third_party/README.md`](third_party/README.md) for versions/SHAs. Re-vendor
  with [`tool/fetch_grammars.sh`](tool/fetch_grammars.sh).
- `src/teampilot_ts_api.{h,c}` — thin C shim exposing grammars behind stable
  `tp_ts_language_*` symbols.
- `hook/build.dart` — native-assets build hook. Compiles the tree-sitter core
  amalgamation, the bundled grammars, and the shim into one dynamic library.
- `src/teampilot_tree_sitter.def` — Windows module-definition exports for the
  tree-sitter C API. Required so MSVC exports `ts_*` symbols (grammars already
  use `__declspec(dllexport)`, which otherwise hides unmarked API symbols).
- `ffigen.yaml` / `lib/teampilot_tree_sitter_bindings_generated.dart` — the
  generated FFI bindings (regenerate with `dart run ffigen`).
- `lib/teampilot_tree_sitter.dart` — the Dart API (`TsParser`, `TsTree`,
  `TsQuery`, `TsLanguage`, `TsCapture`).

## Usage

```dart
final lang = TsLanguage.json();
final parser = TsParser()..setLanguage(lang);
final tree = parser.parseUtf8(utf8.encode('{"a": 1}') as Uint8List);
final query = TsQuery(lang, '(string) @string');
final caps = query.captures(tree, startByte: 0, endByte: 8);
```

## Development

```bash
dart run ffigen --config ffigen.yaml   # regenerate bindings after header changes
flutter test                           # builds the native asset + runs the smoke test
```

Adding a grammar: vendor its generated `src/parser.c` (+ scanner if any) under
`third_party/`, add a `tp_ts_language_<name>` shim in `src/teampilot_ts_api.c`,
list the sources in `hook/build.dart`, and re-run ffigen.
