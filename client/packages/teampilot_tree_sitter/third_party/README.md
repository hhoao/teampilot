# Vendored tree-sitter sources

These C sources are copied (not git-submoduled) so that `flutter test` and
`flutter build` compile the native asset offline, with no runtime download and
no wasm. Re-vendor with [`../tool/fetch_grammars.sh`](../tool/fetch_grammars.sh),
which checks out the pinned tags below and copies the needed files here.

## Pinned versions

| Component | Repo | Tag | Commit SHA |
|-----------|------|-----|------------|
| tree-sitter (core runtime) | https://github.com/tree-sitter/tree-sitter | `v0.25.10` | `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406` |
| tree-sitter-json (grammar) | https://github.com/tree-sitter/tree-sitter-json | `v0.24.8` | `ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24` |

When bumping a version: update the tag in `tool/fetch_grammars.sh`, run it,
then update the tag + SHA in the table above.

## Layout

```
tree-sitter/
  LICENSE
  lib/
    include/tree_sitter/api.h   # public C API (ffigen entry point)
    src/                        # core runtime; lib.c is the unity build
tree-sitter-json/
  LICENSE
  src/
    parser.c                    # generated JSON parser (no external scanner)
    grammar.json, node-types.json
    tree_sitter/                # generated parser ABI headers (parser.h, ...)
```

## What is compiled (`../hook/build.dart`)

A single native asset links:

1. `tree-sitter/lib/src/lib.c` — the core amalgamation (`#include`s every core
   `.c`; `wasm_store.c` is a no-op because `TREE_SITTER_FEATURE_WASM` is unset).
2. `tree-sitter-json/src/parser.c` — the JSON grammar.
3. `../src/teampilot_ts_api.c` — a thin shim exporting `tp_ts_language_json`.

Include paths: `tree-sitter/lib/include`, `tree-sitter/lib/src`,
`tree-sitter-json/src`, and `../src`. The build defines `_POSIX_C_SOURCE` and
`_DEFAULT_SOURCE` because strict C11 otherwise hides POSIX/BSD symbols the core
uses (`fdopen`, `le16toh`/`be16toh`).

## Licenses

Both projects are MIT licensed; their `LICENSE` files are vendored alongside the
sources in each subdirectory.
