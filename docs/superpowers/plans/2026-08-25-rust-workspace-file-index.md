# Rust workspace file name index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `teampilot_search` with a Rust-backed file-name index (gitignore-aware walk + in-process fuzzy/contains query) and wire `WorkspaceFileIndex` to use it on locally readable roots, keeping the existing Dart BFS path for SSH/SFTP and as build-failure fallback.

**Architecture:** Add a persistent `TpFileIndex` handle beside `TpSearchEngine`: Rust owns the path list after a parallel `ignore::WalkBuilder` build; each keystroke calls `tp_file_index_query` and receives only top-N matches. App-layer `WorkspaceFileIndex` selects Rust vs Dart by “path locally readable and filesystem is not SFTP”; freshness (root mtime + 5‑minute TTL) stays in Dart.

**Tech Stack:** Existing `teampilot_search` (Rust `ignore`, FFI + ffigen, Flutter tests), `WorkspaceFileIndex` / `WorkspaceSearchIndexes` in the app.

**Spec:** [docs/superpowers/specs/2026-08-25-rust-workspace-file-index-design.md](../specs/2026-08-25-rust-workspace-file-index-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| `client/packages/teampilot_search/rust/src/fuzzy.rs` | Pure `fuzzy_match_score` (Dart parity) |
| `client/packages/teampilot_search/rust/src/file_index.rs` | Walk, store files+dirs, query / query_dirs |
| `client/packages/teampilot_search/rust/src/lib.rs` | FFI exports for file index |
| `client/packages/teampilot_search/rust/include/teampilot_search.h` | C declarations |
| `client/packages/teampilot_search/lib/teampilot_search_bindings_generated.dart` | Regenerated via ffigen |
| `client/packages/teampilot_search/lib/src/file_index.dart` | Dart `TpFileIndex` wrapper |
| `client/packages/teampilot_search/lib/teampilot_search.dart` | Export new API |
| `client/packages/teampilot_search/rust/tests/file_index_test.rs` | Rust walk + fuzzy tests |
| `client/packages/teampilot_search/test/file_index_test.dart` | Dart/FFI package tests |
| `client/lib/services/file_tree/workspace_file_index.dart` | Backend select + fallback |
| `client/test/services/file_tree/workspace_file_index_test.dart` | App-level backend tests |

## Global constraints

- Package must not import `client/lib/`.
- After Rust/package tasks: `cd client/packages/teampilot_search && cargo test --manifest-path rust/Cargo.toml && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
- After app tasks: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and targeted `flutter test` paths listed in the task.
- Commit style: `feat(teampilot_search): …` / `feat(file-tree): …`
- Fuzzy **scores must match** existing Dart `fuzzyMatchScore` (same integer), not merely sort order.
- Local walk: `use_gitignore` default **true**, `hidden(true)`, `git_global(false)`, `git_exclude(false)`, `require_git(false)` — same as content search walker.
- Do not change content-search ABI behavior.

---

### Task 1: Rust `fuzzy_match_score` with Dart parity tests

**Files:**
- Create: `client/packages/teampilot_search/rust/src/fuzzy.rs`
- Modify: `client/packages/teampilot_search/rust/src/lib.rs` (add `mod fuzzy;`)
- Create: `client/packages/teampilot_search/rust/tests/fuzzy_test.rs`

- [ ] **Step 1: Write failing Rust tests from known Dart vectors**

Create `rust/tests/fuzzy_test.rs`:

```rust
use teampilot_search_rust::fuzzy::fuzzy_match_score;

#[test]
fn empty_query_is_no_match() {
    assert_eq!(fuzzy_match_score("lib/app.dart", ""), -1);
}

#[test]
fn subsequence_across_separators() {
    // "ppro" ⊆ "lib/app_router.dart"
    assert!(fuzzy_match_score("lib/app_router.dart", "ppro") > 0);
}

#[test]
fn basename_prefix_beats_directory_only() {
    let a = fuzzy_match_score("lib/widgets/router_guard.dart", "router_guard");
    let b = fuzzy_match_score("router/other.dart", "router_guard");
    assert!(a > b);
}

#[test]
fn dart_parity_vectors() {
    // Lock exact scores against Dart fuzzyMatchScore for these pairs.
    // Compute expected values once by running a tiny Dart snippet / existing
    // unit test helper before implementing; fill literals below.
    let cases: &[(&str, &str, i32)] = &[
        ("lib/app_router.dart", "router", /* EXPECT */ 0), // replace 0 after measuring
        ("lib/chat_cubit.dart", "chat", /* EXPECT */ 0),
        ("README.md", "readme", /* EXPECT */ 0),
        ("a/b/c.dart", "xyz", -1),
    ];
    for (path, q, want) in cases {
        assert_eq!(fuzzy_match_score(path, q), *want, "{path} / {q}");
    }
}
```

Before coding the scorer: from `client/`, run a one-off that prints Dart scores for the paths above (or add a temporary test), paste real integers into `EXPECT` slots, then delete the temporary helper.

- [ ] **Step 2: Run tests — expect compile/link failure (module missing)**

Run: `cd client/packages/teampilot_search/rust && cargo test --test fuzzy_test`

Expected: FAIL (crate has no `fuzzy` module / `fuzzy_match_score`).

- [ ] **Step 3: Implement `fuzzy.rs` as a line-faithful port of Dart**

Port `client/lib/services/file_tree/workspace_file_index.dart` `fuzzyMatchScore` + `_boundaryBonus` to Rust (`fuzzy_match_score` / `boundary_bonus`). Use Unicode-aware lowercasing consistent with Dart’s `toLowerCase` on the ASCII-heavy path set used in tests; for parity tests stick to ASCII paths.

Export from `lib.rs`:

```rust
pub mod fuzzy;
pub mod engine;
// existing …
```

Make `fuzzy_match_score` `pub` so integration tests can call `teampilot_search_rust::fuzzy::fuzzy_match_score`.

- [ ] **Step 4: Re-run `cargo test --test fuzzy_test` — all PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/teampilot_search/rust/src/fuzzy.rs \
  client/packages/teampilot_search/rust/src/lib.rs \
  client/packages/teampilot_search/rust/tests/fuzzy_test.rs
git commit -m "$(cat <<'EOF'
feat(teampilot_search): port fuzzyMatchScore to Rust with Dart parity

EOF
)"
```

---

### Task 2: Rust in-memory file index (walk + query)

**Files:**
- Create: `client/packages/teampilot_search/rust/src/file_index.rs`
- Modify: `client/packages/teampilot_search/rust/src/lib.rs` (`pub mod file_index;`)
- Create: `client/packages/teampilot_search/rust/tests/file_index_test.rs`
- Create fixture dir under `client/packages/teampilot_search/rust/tests/fixtures/file_index/` (files + `.gitignore` + `node_modules/` noise)

- [ ] **Step 1: Write failing walk/query tests**

Fixture layout (create files in the test setup or checked-in fixtures):

```
fixtures/file_index/
  .gitignore          → contains `secret.txt` and/or `ignored_dir/`
  lib/app_router.dart
  lib/chat_cubit.dart
  secret.txt          (gitignored)
  ignored_dir/x.dart  (gitignored)
  node_modules/pkg/a.dart
  .hidden/y.dart
```

`file_index_test.rs` sketch:

```rust
use teampilot_search_rust::file_index::{
    FileIndex, FileIndexConfig, FileMatchMode,
};

fn fixture_root() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/file_index")
}

#[test]
fn build_respects_gitignore_and_hidden() {
    let mut idx = FileIndex::new(FileIndexConfig {
        root: fixture_root().to_string_lossy().into(),
        use_gitignore: true,
        max_entries: 100_000,
    })
    .unwrap();
    idx.build().unwrap();
    let rels: Vec<_> = idx
        .query("router", FileMatchMode::Fuzzy, 50)
        .into_iter()
        .map(|m| m.relative_path)
        .collect();
    assert!(rels.iter().any(|p| p.ends_with("app_router.dart")));
    assert!(!rels.iter().any(|p| p.contains("secret")));
    assert!(!rels.iter().any(|p| p.contains("ignored_dir")));
    assert!(!rels.iter().any(|p| p.contains("node_modules")));
    assert!(!rels.iter().any(|p| p.contains(".hidden")));
}

#[test]
fn contains_mode_matches_basename() {
    let mut idx = FileIndex::new(FileIndexConfig {
        root: fixture_root().to_string_lossy().into(),
        use_gitignore: true,
        max_entries: 100_000,
    })
    .unwrap();
    idx.build().unwrap();
    let names: Vec<_> = idx
        .query("CHAT", FileMatchMode::Contains, 50)
        .into_iter()
        .map(|m| m.name)
        .collect();
    assert_eq!(names, vec!["chat_cubit.dart".to_string()]);
}

#[test]
fn query_dirs_matches_basename() {
    let mut idx = FileIndex::new(FileIndexConfig {
        root: fixture_root().to_string_lossy().into(),
        use_gitignore: true,
        max_entries: 100_000,
    })
    .unwrap();
    idx.build().unwrap();
    let dirs = idx.query_dirs("lib", 20);
    assert!(dirs.iter().any(|d| d == "lib"));
}

#[test]
fn max_entries_truncates() {
    let mut idx = FileIndex::new(FileIndexConfig {
        root: fixture_root().to_string_lossy().into(),
        use_gitignore: true,
        max_entries: 1,
    })
    .unwrap();
    idx.build().unwrap();
    assert!(idx.truncated());
    assert!(idx.file_count() <= 1);
}
```

- [ ] **Step 2: Run `cargo test --test file_index_test` — FAIL (missing module)**

- [ ] **Step 3: Implement `file_index.rs`**

Public types:

```rust
pub struct FileIndexConfig {
    pub root: String,
    pub use_gitignore: bool,
    pub max_entries: u64,
}

pub enum FileMatchMode {
    Fuzzy,
    Contains,
}

pub struct FileHit {
    pub path: String,
    pub relative_path: String,
    pub name: String,
}

pub struct FileIndex { /* entries, dirs, truncated, cancel flag */ }

impl FileIndex {
    pub fn new(config: FileIndexConfig) -> Result<Self, FileIndexError> { … }
    pub fn build(&mut self) -> Result<(), FileIndexError> { … }
    pub fn cancel(&self) { … }
    pub fn query(&self, q: &str, mode: FileMatchMode, limit: usize) -> Vec<FileHit> { … }
    pub fn query_dirs(&self, q: &str, limit: usize) -> Vec<String> { … }
    pub fn truncated(&self) -> bool { … }
    pub fn file_count(&self) -> usize { … }
}
```

`build`:
- Reuse walker settings from `engine::build_walker` pattern (extract shared `build_path_walker(root, use_gitignore)` into a small helper in `file_index.rs` or `engine.rs` if clean — prefer **local copy of WalkBuilder setup** in `file_index.rs` first to avoid risking content-search regressions; optional refactor later).
- Parallel walk; collect files (path, relative with `/`, basename) and relative directory paths.
- Stop when `scanned >= max_entries`; set `truncated`.
- Honor cancel atomic between entries.

`query` Fuzzy: score every file with `fuzzy_match_score(relative_path, q)`, keep score≥0, sort by score desc then `relative_path` asc, take `limit`.

`query` Contains: case-insensitive `name.contains(q)`, first `limit` in walk order (match current Dart).

`query_dirs`: basename contains, case-insensitive, cap `limit`.

- [ ] **Step 4: `cargo test --test file_index_test` PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/teampilot_search/rust/src/file_index.rs \
  client/packages/teampilot_search/rust/src/lib.rs \
  client/packages/teampilot_search/rust/tests/file_index_test.rs \
  client/packages/teampilot_search/rust/tests/fixtures/file_index
git commit -m "$(cat <<'EOF'
feat(teampilot_search): add Rust file index walk and query

EOF
)"
```

---

### Task 3: FFI ABI + header + ffigen

**Files:**
- Modify: `client/packages/teampilot_search/rust/include/teampilot_search.h`
- Modify: `client/packages/teampilot_search/rust/src/lib.rs` (extern "C" shims)
- Regenerate: `client/packages/teampilot_search/lib/teampilot_search_bindings_generated.dart`

- [ ] **Step 1: Extend the C header**

Append to `teampilot_search.h` (keep existing search types untouched):

```c
typedef struct TpFileIndexHandle TpFileIndexHandle;

typedef struct TpFileIndexConfig {
  const char* root;
  int32_t use_gitignore;
  uint64_t max_entries;
  uint32_t max_chunk_matches;
  uint32_t max_chunk_bytes;
} TpFileIndexConfig;

typedef struct TpFileIndexEntry {
  const char* path;
  const char* relative_path;
  const char* name;
} TpFileIndexEntry;

typedef struct TpFileIndexChunk {
  char* string_buf;
  uint32_t string_buf_cap;
  uint32_t string_buf_len;
  TpFileIndexEntry* entries;
  uint32_t entries_cap;
  uint32_t entries_len;
  int32_t truncated; /* index truncated at build, or query hit limit — see docs */
} TpFileIndexChunk;

/* mode: 0 = fuzzy, 1 = contains */
int32_t tp_file_index_new(const TpFileIndexConfig* config, TpFileIndexHandle** out);
int32_t tp_file_index_build(TpFileIndexHandle* handle); /* 0 ok, negative err; blocks until done or cancel */
void tp_file_index_cancel(TpFileIndexHandle* handle);
/* Returns 0 ok; fills chunk with up to limit entries (caller sets entries_cap). */
int32_t tp_file_index_query(
    TpFileIndexHandle* handle,
    const char* query,
    int32_t mode,
    uint32_t limit,
    TpFileIndexChunk* chunk);
int32_t tp_file_index_query_dirs(
    TpFileIndexHandle* handle,
    const char* query,
    uint32_t limit,
    TpFileIndexChunk* chunk); /* name unused; relative_path holds dir path */
void tp_file_index_free(TpFileIndexHandle* handle);
```

Error codes: reuse `-2` root unreadable, `-3` internal; `0` success.

- [ ] **Step 2: Implement FFI in `lib.rs`**

Mirror the content-search pattern: own `TpFileIndexHandle { inner: FileIndex, … }`, pack strings into caller-provided `string_buf`, set entry pointers into that buffer (same packing strategy as `tp_search_next`).

`tp_file_index_build`: call `inner.build()` synchronously on the calling thread **or** spawn + wait; prefer **spawn worker + block with short sleeps checking cancel** only if needed — simplest correct v1: run `build()` on a dedicated thread and join, with cancel flag checked inside walk.

- [ ] **Step 3: Regenerate bindings**

Run from package root:

```bash
cd client/packages/teampilot_search
dart run ffigen --config ffigen.yaml
```

Expected: new `@Native` externs for `tp_file_index_*` in `lib/teampilot_search_bindings_generated.dart`.

- [ ] **Step 4: Smoke `flutter test test/engine_version_test.dart` still PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/teampilot_search/rust/include/teampilot_search.h \
  client/packages/teampilot_search/rust/src/lib.rs \
  client/packages/teampilot_search/lib/teampilot_search_bindings_generated.dart
git commit -m "$(cat <<'EOF'
feat(teampilot_search): expose file index FFI and regenerate bindings

EOF
)"
```

---

### Task 4: Dart `TpFileIndex` wrapper + package tests

**Files:**
- Create: `client/packages/teampilot_search/lib/src/file_index.dart`
- Modify: `client/packages/teampilot_search/lib/teampilot_search.dart` (export)
- Create: `client/packages/teampilot_search/test/file_index_test.dart`
- Modify: `client/packages/teampilot_search/README.md` (one paragraph on file index)

- [ ] **Step 1: Write failing Dart tests**

```dart
import 'dart:io';

import 'package:teampilot_search/teampilot_search.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('rust/tests/fixtures/file_index').absolute.path;

  test('TpFileIndex builds and fuzzy-queries', () async {
    final index = TpFileIndex();
    await index.build(
      root,
      const TpFileIndexOptions(useGitignore: true),
    );
    final hits = index.query('router', limit: 20);
    expect(hits.map((h) => h.name), contains('app_router.dart'));
    expect(hits.any((h) => h.relativePath.contains('node_modules')), isFalse);
    index.dispose();
  });

  test('contains mode and queryDirectories', () async {
    final index = TpFileIndex();
    await index.build(root, const TpFileIndexOptions());
    expect(
      index.query('chat', mode: TpFileMatchMode.contains).single.name,
      'chat_cubit.dart',
    );
    expect(index.queryDirectories('lib'), contains('lib'));
    index.dispose();
  });
}
```

- [ ] **Step 2: `flutter test test/file_index_test.dart` — FAIL (API missing)**

- [ ] **Step 3: Implement `lib/src/file_index.dart`**

```dart
enum TpFileMatchMode { fuzzy, contains }

class TpFileIndexOptions {
  const TpFileIndexOptions({
    this.useGitignore = true,
    this.maxEntries = 200000,
  });
  final bool useGitignore;
  final int maxEntries;
}

class TpFileHit {
  const TpFileHit({
    required this.path,
    required this.relativePath,
    required this.name,
  });
  final String path;
  final String relativePath;
  final String name;
}

class TpFileIndex {
  // holds Pointer<TpFileIndexHandle>?; build via FFI; query packs Utf8 query
  Future<void> build(String root, [TpFileIndexOptions options = const TpFileIndexOptions()]);
  List<TpFileHit> query(String query, {TpFileMatchMode mode = TpFileMatchMode.fuzzy, int limit = 50});
  List<String> queryDirectories(String query, {int limit = 20});
  void cancel();
  void dispose();
  bool get isBuilt;
  bool get truncated;
}
```

Use the same preallocated chunk buffer approach as `TpSearchEngine.search` (read that file and mirror packing/unpacking).

Export from `teampilot_search.dart`:

```dart
export 'src/file_index.dart';
```

- [ ] **Step 4: `flutter test test/file_index_test.dart` PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/teampilot_search/lib/src/file_index.dart \
  client/packages/teampilot_search/lib/teampilot_search.dart \
  client/packages/teampilot_search/test/file_index_test.dart \
  client/packages/teampilot_search/README.md
git commit -m "$(cat <<'EOF'
feat(teampilot_search): add Dart TpFileIndex wrapper

EOF
)"
```

---

### Task 5: Wire `WorkspaceFileIndex` (Rust local + Dart fallback)

**Files:**
- Modify: `client/lib/services/file_tree/workspace_file_index.dart`
- Modify: `client/test/services/file_tree/workspace_file_index_test.dart`
- Ensure `client/pubspec.yaml` already depends on `teampilot_search` (it should from content search)

- [ ] **Step 1: Add failing tests for backend selection**

Extend `workspace_file_index_test.dart`:

```dart
test('uses Dart backend when filesystem is not local-readable path', () async {
  // Keep using InMemoryFilesystem — root path is not a real OS path.
  // After wiring, ensureFresh must still succeed via Dart BFS.
  final index = WorkspaceFileIndex(fs: fs, root: root);
  await index.ensureFresh();
  expect(index.isReady, isTrue);
  expect(index.query('router'), isNotEmpty);
});
```

Add a test that documents Rust path only when `Directory(root).existsSync()` — optional integration-style test under `client/packages/teampilot_search` already covers Rust; app test focuses on “in-memory fs still works”.

If you introduce a `@visibleForTesting` `FileIndexBackend` enum or `bool get usedRustBackend`, assert `usedRustBackend == false` on InMemoryFilesystem.

- [ ] **Step 2: Run the new test — may PASS already on pure Dart; then implement selection and re-assert**

- [ ] **Step 3: Implement dual backend in `WorkspaceFileIndex`**

Logic in `ensureFresh` / `_build`:

```dart
bool _shouldUseRust() {
  if (_fs is SftpFilesystem) return false;
  try {
    return FileSystemEntity.typeSync(root) != FileSystemEntityType.notFound;
  } catch (_) {
    return false;
  }
}
```

When Rust:
1. Create/reuse `TpFileIndex`.
2. `await index.build(root, TpFileIndexOptions(maxEntries: _limits.maxIndexEntries, useGitignore: true))`.
3. On success, set `_entries`/`_dirs` **or** keep only the handle and make `query`/`queryDirectories` delegate to `TpFileIndex` (preferred: **delegate**, avoid duplicating the full path list in Dart).
4. On failure: `dispose` handle, fall through to existing Dart `_build()`.

When Dart: existing BFS unchanged (fixed ignore list, no gitignore).

`query` / `queryDirectories`: if Rust handle ready → forward; else use in-memory lists as today.

`invalidate` / dispose path: free Rust handle.

Import: `package:teampilot_search/teampilot_search.dart`, `dart:io` for `FileSystemEntity`, and `../io/sftp_filesystem.dart` for the type check.

- [ ] **Step 4: Run**

```bash
cd client && flutter test test/services/file_tree/workspace_file_index_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/file_tree/workspace_file_index.dart \
  client/test/services/file_tree/workspace_file_index_test.dart
git commit -m "$(cat <<'EOF'
feat(file-tree): use Rust TpFileIndex for local workspace file search

EOF
)"
```

---

### Task 6: Regression — dialog + compose paths

**Files:**
- Verify only (modify only if tests fail):  
  `client/test/pages/workspace_search_dialog_test.dart`  
  `client/test/services/compose/compose_file_search_test.dart`  
  `client/test/services/file_tree/workspace_file_search_test.dart`

- [ ] **Step 1: Run existing tests**

```bash
cd client && flutter test \
  test/pages/workspace_search_dialog_test.dart \
  test/services/compose/compose_file_search_test.dart \
  test/services/file_tree/workspace_file_search_test.dart \
  test/services/file_tree/workspace_file_index_test.dart
```

Expected: PASS. Dialog and compose already go through `WorkspaceFileIndex` / `WorkspaceSearchIndexes`; no UI change required if Task 5 preserves APIs.

- [ ] **Step 2: If a test assumed “no gitignore” on a real temp directory used as local root**, either mark the directory non-existent to force Dart backend, or add a `.gitignore`-compatible fixture. Prefer forcing Dart via InMemoryFilesystem / non-OS paths.

- [ ] **Step 3: Manual smoke (engineer)**  
  Open a large local git repo workspace → open search dialog once → confirm first open is faster and gitignored paths do not appear; `@` file mention still works.

- [ ] **Step 4: Commit only if Step 2 required code/test fixes**

---

### Task 7: Spec/plan cross-link + package README note

**Files:**
- Modify: `client/packages/teampilot_search/README.md` (if not done in Task 4)
- Optionally one-line link from content-search design “out of scope” note — **skip** unless you want historical clarity; do not rewrite old specs.

- [ ] **Step 1: Ensure README mentions file index API briefly**

- [ ] **Step 2: Commit if dirty**

```bash
git add client/packages/teampilot_search/README.md
git commit -m "$(cat <<'EOF'
docs(teampilot_search): document file index API

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Rust walk + persistent index | 2, 3, 4 |
| Rust fuzzy + contains + query_dirs | 1, 2, 4 |
| gitignore default on (local) | 2, 5 |
| SSH / non-local Dart fallback | 5 |
| Build failure → Dart fallback | 5 |
| Freshness mtime/TTL in Dart | 5 (keep existing) |
| Dialog/compose API stable | 5, 6 |
| Score parity tests | 1 |
| No content-search regression | 3 (header additive), 6 |

## Placeholder / consistency self-review

- No TBD steps; fuzzy EXPECT literals must be filled in Task 1 Step 1 from measured Dart scores before implementation.
- ABI names (`tp_file_index_*`, `TpFileIndex`, `TpFileHit`) consistent across Tasks 3–5.
- `max_entries` default aligns with `WorkspaceFileSearchLimits.maxIndexEntries` (200000).
