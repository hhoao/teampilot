# teampilot_search

Ripgrep-based content search engine for TeamPilot (Rust FFI) with a pure-Dart
fallback for non-local filesystems (SSH).

`TpFileIndex` builds a Rust-backed file and directory index for a local root,
honours `.gitignore` by default, and supports fuzzy or substring file queries.

- Rust core: `rust/` (crate `teampilot_search_rust`, built via
  `native_toolchain_rust` hooks at pub build time)
- FFI ABI: `rust/include/teampilot_search.h` (regenerate Dart bindings with
  `dart run ffigen --config ffigen.yaml`)
- Tests: `flutter test` (Dart) and `cargo test` (Rust, run in `rust/`)

Requires a Rust toolchain (rustup) pinned by `rust/rust-toolchain.toml`.
