# Vendored tree-sitter sources

These C sources are copied (not git-submoduled) so that `flutter test` and
`flutter build` compile the native asset offline, with no runtime download and
no wasm. Re-vendor with [`../tool/fetch_grammars.sh`](../tool/fetch_grammars.sh),
which checks out the pinned tags below and copies the needed files here.

## Pinned versions

| Component | Repo | Tag / ref | Commit SHA |
|-----------|------|-----------|------------|
| tree-sitter (core runtime) | https://github.com/tree-sitter/tree-sitter | `v0.25.10` | `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406` |
| tree-sitter-json | https://github.com/tree-sitter/tree-sitter-json | `v0.24.8` | `ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24` |
| tree-sitter-dart | https://github.com/UserNobody14/tree-sitter-dart | `master` (no tags) | `be07cf7118d3dba06236a3f19541685a68209934` |
| tree-sitter-yaml | https://github.com/tree-sitter-grammars/tree-sitter-yaml | `v0.7.2` | `7708026449bed86239b1cd5bce6e3c34dbca6415` |
| tree-sitter-markdown | https://github.com/tree-sitter-grammars/tree-sitter-markdown | `v0.5.3` | `f969cd3ae3f9fbd4e43205431d0ae286014c05b5` |
| tree-sitter-python | https://github.com/tree-sitter/tree-sitter-python | `v0.23.6` | `bffb65a8cfe4e46290331dfef0dbf0ef3679de11` |
| tree-sitter-rust | https://github.com/tree-sitter/tree-sitter-rust | `v0.24.0` | `18b0515fca567f5a10aee9978c6d2640e878671a` |
| tree-sitter-typescript | https://github.com/tree-sitter/tree-sitter-typescript | `v0.23.2` | `f975a621f4e7f532fe322e13c4f79495e0a7b2e7` |
| tree-sitter-bash | https://github.com/tree-sitter/tree-sitter-bash | `v0.25.0` | `56b54c61fb48bce0c63e3dfa2240b5d274384763` |
| tree-sitter-xml | https://github.com/tree-sitter-grammars/tree-sitter-xml | `v0.7.0` | `4b64dd3a03ec002258d6268d712fd93716d6ab57` |
| tree-sitter-toml | https://github.com/tree-sitter-grammars/tree-sitter-toml | `v0.7.0` | `64b56832c2cffe41758f28e05c756a3a98d16f41` |
| tree-sitter-css | https://github.com/tree-sitter/tree-sitter-css | `v0.23.2` | `c0d581e32d183a536731ed6c3a72758b27e20411` |

All grammar language ABIs are 14 or 15, within the core runtime's supported
range (min 13, max 15). Every bundled grammar's external scanner is plain C, so
they all link into the single C11 native asset.

Note: this phase maps `.html`/`.htm` (and `.xml`) to the **xml** grammar, so no
separate html grammar is vendored. `tree-sitter-typescript` is vendored via its
`tsx` grammar (a superset that also parses `.ts`/`.js`/`.jsx`).
`tree-sitter-markdown` vendors only the block grammar (`tree-sitter-markdown/`,
not the inline sub-package).

When bumping a version: update the tag/ref in `tool/fetch_grammars.sh`, run it,
then update the ref + SHA in the table above.

## Layout

```
tree-sitter/
  LICENSE
  lib/
    include/tree_sitter/api.h   # public C API (ffigen entry point)
    src/                        # core runtime; lib.c is the unity build
tree-sitter-<name>/             # json, dart, yaml, python, rust, bash,
  LICENSE                       #   toml, css, markdown
  src/
    parser.c                    # generated parser
    scanner.c                   # external scanner (C; json has none)
    grammar.json, node-types.json
    tree_sitter/                # generated parser ABI headers (parser.h, ...)
tree-sitter-typescript/         # multi-grammar repo
  LICENSE
  common/scanner.h              # shared scanner, #included by tsx/src/scanner.c
  tsx/src/                      # the tsx grammar (parser.c + scanner.c + hdrs)
tree-sitter-xml/                # multi-grammar repo
  LICENSE
  common/scanner.h              # shared scanner, #included by xml/src/scanner.c
  xml/src/                      # the xml grammar (parser.c + scanner.c + hdrs)
```

## What is compiled (`../hook/build.dart`)

A single native asset links:

1. `tree-sitter/lib/src/lib.c` — the core amalgamation (`#include`s every core
   `.c`; `wasm_store.c` is a no-op because `TREE_SITTER_FEATURE_WASM` is unset).
2. Each bundled grammar's `parser.c` (+ its C `scanner.c`, where present).
3. `../src/teampilot_ts_api.c` — a thin shim exporting `tp_ts_language_*`
   symbols, one per bundled grammar.

Include paths: `tree-sitter/lib/include`, `tree-sitter/lib/src`, each grammar's
`src` dir (for its vendored `tree_sitter/*.h`), and `../src`. The build defines
`_POSIX_C_SOURCE` and `_DEFAULT_SOURCE` because strict C11 otherwise hides
POSIX/BSD symbols the core uses (`fdopen`, `le16toh`/`be16toh`).

## Licenses

All projects are MIT licensed; their `LICENSE` files are vendored alongside the
sources in each subdirectory.
