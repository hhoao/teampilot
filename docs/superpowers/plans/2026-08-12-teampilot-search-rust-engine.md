# teampilot_search：Rust FFI 内容搜索引擎实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `client/packages/teampilot_search` 新建一个独立 package：Rust（ripgrep crate 栈）FFI 内容搜索引擎 + 纯 Dart fallback 引擎，供内置 IDE 做 VS Code 式全文搜索。

**Architecture:** Rust cdylib 通过 `native_toolchain_rust` + code_assets hooks 编译为 native asset，ffigen 生成 `@Native` bindings（与 `teampilot_tree_sitter` 同一套机制）。Rust 侧 `ignore::WalkBuilder`（gitignore/glob/隐藏文件语义）+ `grep-searcher` 搜索，工作线程 + 有界 channel + 原子取消标志，Dart 侧 `tp_search_next` 分块拉取成 `Stream<TpSearchMatch>`。SSH 等非本地后端用包内纯 Dart fallback 引擎（`SearchFileReader` 注入）。

**Tech Stack:** Rust（grep 0.3 / ignore 0.4 / regex-syntax 0.8）、native_toolchain_rust 1.0.4、ffigen 20、code_assets hooks、Dart ffi、flutter_test。

## Global Constraints

- 包不得依赖 app 任何类（`client/lib/` 下代码不可 import），保持可发布性
- 目录结构：`hook/build.dart`、`ffigen.yaml`、`lib/`、`rust/`、`test/`；Rust crate 根为 `rust/Cargo.toml`（native_toolchain_rust 默认查找）
- `rust/Cargo.toml` 必须含 `[lib] crate-type = ["staticlib", "cdylib"]`
- `rust-toolchain.toml` 必须固定版本号（如 `1.90.0`），不得写 `stable`
- `Cargo.lock` 必须提交（flutter_alacritty 同款，构建时从 crates.io 拉取，不 vendoring）
- SDK 下限：Dart `^3.12.2`；ffigen 产物文件名 `lib/teampilot_search_bindings_generated.dart` 且必须与 `RustBuilder(assetName:)` 一致（`@Native` 免显式 asset 解析的前提）
- FFI 错误码：`0` 继续 / `1` 完成 / `2` 已取消 / `-1` 无效正则 / `-2` root 不可读 / `-3` 内部错误
- `TpSearchMatch.matchStart/End` 为**行内 UTF-8 字节偏移**，Dart 侧换算为字符偏移
- 搜索语义：隐藏文件跳过；`use_gitignore` 时尊重 `.gitignore`/`.ignore`（不依赖 git repo）；`.gitignore` 不全局（`git_global(false)`）、不 exclude（`git_exclude(false)`）；超 1 MB 的单行只发"行号 + 无文本"的占位匹配（按 spec：行文本置空）；二进制文件（含 NUL 字节）跳过
- 每任务完成后必须跑：`cd client/packages/teampilot_search && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`；Rust 任务额外 `cargo test`（在 `rust/` 下）
- 提交信息用 repo 既有风格（如 `feat(teampilot_search): ...`）

---

### Task 1: 包脚手架 + FFI 工具链冒烟（ping）

**Files:**
- Create: `client/packages/teampilot_search/pubspec.yaml`
- Create: `client/packages/teampilot_search/analysis_options.yaml`
- Create: `client/packages/teampilot_search/hook/build.dart`
- Create: `client/packages/teampilot_search/ffigen.yaml`
- Create: `client/packages/teampilot_search/rust/Cargo.toml`
- Create: `client/packages/teampilot_search/rust/rust-toolchain.toml`
- Create: `client/packages/teampilot_search/rust/src/lib.rs`
- Create: `client/packages/teampilot_search/rust/include/teampilot_search.h`
- Create: `client/packages/teampilot_search/lib/teampilot_search.dart`
- Create: `client/packages/teampilot_search/lib/teampilot_search_bindings_generated.dart`（ffigen 产物）
- Create: `client/packages/teampilot_search/test/engine_version_test.dart`
- Create: `client/packages/teampilot_search/README.md`

**Interfaces:**
- Produces: `tp_search_version() -> *const c_char`（冒烟用）；`TpSearchConfig`/`TpSearchMatch`/`TpSearchChunk` 的 C 头文件（Task 2 填充实现，Task 3 由 ffigen 再生成）；Dart 侧 `String engineVersion()`。

- [ ] **Step 1: 建包骨架（pubspec + hook + ffigen 配置）**

`pubspec.yaml`:
```yaml
name: teampilot_search
description: "Ripgrep-based content search engine for TeamPilot (Rust FFI) with a pure-Dart fallback."
version: 0.1.0
publish_to: 'none'

environment:
  sdk: ^3.12.2

dependencies:
  code_assets: ^1.2.1
  ffi: ^2.1.4
  hooks: ^2.0.2
  logging: ^1.3.0
  native_toolchain_rust: ^1.0.4

dev_dependencies:
  ffigen: ^20.1.1
  flutter_lints: ^6.0.0
  test: ^1.28.0
```

`analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
```

`hook/build.dart`（与 tree_sitter 同款结构，CBuilder 换成 RustBuilder）:
```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    await RustBuilder(
      // asset id 与 ffigen 产物文件名一致（tree_sitter 同款），
      // @Native externals 才能免显式 asset id 解析。
      assetName: 'teampilot_search_bindings_generated.dart',
      cratePath: 'rust',
    ).run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        // ignore: avoid_print
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
```
验证点：若 `@Native` 解析失败（运行时报 asset 找不到），把 assetName 换成 `'teampilot_search/bindings/teampilot_search_bindings_generated.dart'` 再试（native_toolchain_rust 示例的包前缀写法）。

`ffigen.yaml`:
```yaml
name: TeampilotSearchBindings
description: |
  Bindings for the Rust FFI shim in rust/include/teampilot_search.h.
output: 'lib/teampilot_search_bindings_generated.dart'
ffi-native:
headers:
  entry-points:
    - 'rust/include/teampilot_search.h'
  include-directives:
    - '**/teampilot_search.h'
comments:
  style: any
  length: full
```

- [ ] **Step 2: Rust crate 骨架（冒烟 ping）**

`rust/Cargo.toml`:
```toml
[package]
name = "teampilot_search_rust"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib", "cdylib"]

[dependencies]
grep = "0.3"
ignore = "0.4"
regex-syntax = "0.8"
```

`rust/rust-toolchain.toml`:
```toml
[toolchain]
channel = "1.90.0"
targets = [
  "x86_64-unknown-linux-gnu",
  "aarch64-apple-darwin",
  "x86_64-apple-darwin",
  "x86_64-pc-windows-msvc",
]
```
注意：`toolchain.targets` 是 `native_toolchain_rust` 1.0.4 的硬性校验要求（缺失直接报错）；桌面四平台足矣，Android 目标在 Task 5 的 cargo-ndk 步骤再加。

`rust/include/teampilot_search.h`（v1 完整 ABI 头，一次定稿；本任务先只实现 version，其余符号 Task 2 实现）:
```c
#ifndef TEAMPILOT_SEARCH_H
#define TEAMPILOT_SEARCH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TpSearchHandle TpSearchHandle;

typedef struct TpSearchConfig {
  const char* root;
  const char* pattern;
  int32_t is_regex;
  int32_t case_sensitive;
  int32_t smart_case;
  int32_t use_gitignore;
  const char* const* files_to_include;
  uint32_t files_to_include_count;
  const char* const* files_to_exclude;
  uint32_t files_to_exclude_count;
  uint64_t max_file_size;
  uint64_t max_results;
  uint32_t max_chunk_matches;
  uint32_t max_chunk_bytes;
} TpSearchConfig;

typedef struct TpSearchMatch {
  const char* path;
  const char* relative_path;
  uint64_t line_number;
  const char* line_text;
  uint32_t match_start;
  uint32_t match_end;
} TpSearchMatch;

typedef struct TpSearchChunk {
  char* string_buf;
  uint32_t string_buf_cap;
  uint32_t string_buf_len;
  TpSearchMatch* matches;
  uint32_t matches_cap;
  uint32_t matches_len;
  int32_t truncated;
} TpSearchChunk;

const char* tp_search_version(void);
int32_t tp_search_new(const TpSearchConfig* config, TpSearchHandle** out);
int32_t tp_search_next(TpSearchHandle* handle, TpSearchChunk* chunk);
void tp_search_cancel(TpSearchHandle* handle);
void tp_search_free(TpSearchHandle* handle);

#ifdef __cplusplus
}
#endif
#endif
```

`rust/src/lib.rs`:
```rust
use std::ffi::{c_char, CStr};

#[no_mangle]
pub extern "C" fn tp_search_version() -> *const c_char {
    c"teampilot_search/0.1.0".as_ptr()
}

// 其余符号在 Task 2 实现；这里先声明占位避免链接期/ffigen 缺符号。
#[no_mangle]
pub unsafe extern "C" fn tp_search_new(
    _config: *const std::ffi::c_void,
    _out: *mut std::ffi::c_void,
) -> i32 {
    -3
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_next(
    _handle: *mut std::ffi::c_void,
    _chunk: *mut std::ffi::c_void,
) -> i32 {
    -3
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_cancel(_handle: *mut std::ffi::c_void) {}

#[no_mangle]
pub unsafe extern "C" fn tp_search_free(_handle: *mut std::ffi::c_void) {}
```

注意：Rust cdylib 的 `#[no_mangle]` 符号在 Windows MSVC 下自动导出（与 tree_sitter 的 C 场景不同），**不需要** `.def` 文件。

- [ ] **Step 3: 生成 Dart bindings**

```bash
cd client/packages/teampilot_search && dart pub get && dart run ffigen --config ffigen.yaml
```
Expected: 生成 `lib/teampilot_search_bindings_generated.dart`，包含 `@Native` 标注的 `tp_search_version` 等符号与 `TpSearchConfig` 等 struct 类。

- [ ] **Step 4: Dart 包装 + 失败冒烟测试**

`lib/teampilot_search.dart`:
```dart
/// Ripgrep-based content search engine for TeamPilot.
///
/// The Rust core (`rust/`) is compiled into a native asset by
/// `hook/build.dart`; bindings live in
/// `teampilot_search_bindings_generated.dart`.
library;

import 'dart:ffi' as ffi;

import 'teampilot_search_bindings_generated.dart' as bindings;

/// Version string reported by the Rust core, e.g. `teampilot_search/0.1.0`.
String engineVersion() {
  final ptr = bindings.tp_search_version();
  return ptr.cast<ffi.Utf8>().toDartString();
}
```
注意：`ffi.Utf8` 与 `toDartString()` 来自 `package:ffi`（不是 `dart:ffi`），需 `import 'package:ffi/ffi.dart';`（并去掉未用的 `dart:ffi` import）。

`test/engine_version_test.dart`:
```dart
import 'package:teampilot_search/teampilot_search.dart';
import 'package:test/test.dart';

void main() {
  test('rust core loads and reports version', () {
    expect(engineVersion(), startsWith('teampilot_search/'));
  });
}
```

- [ ] **Step 5: 跑测试，确认失败**

Run: `cd client/packages/teampilot_search && flutter test test/engine_version_test.dart`
Expected: 失败（`tp_search_version` 符号未生成或 asset 未构建）。

- [ ] **Step 6: 修依赖顺序，重跑直到通过**

`flutter test` 会自动先跑 pub get + hook 构建 Rust 资产。若报 `hook` 未执行，确认 pubspec 有 `hooks` 依赖；若 ffigen 产物缺符号，重跑 Step 3 后重试。

Run: `flutter test test/engine_version_test.dart`
Expected: PASS（`startsWith('teampilot_search/')`）。

- [ ] **Step 7: 包 README**

`README.md`:
```markdown
# teampilot_search

Ripgrep-based content search engine for TeamPilot (Rust FFI) with a pure-Dart
fallback for non-local filesystems (SSH).

- Rust core: `rust/` (crate `teampilot_search_rust`, built via
  `native_toolchain_rust` hooks at pub build time)
- FFI ABI: `rust/include/teampilot_search.h` (regenerate Dart bindings with
  `dart run ffigen --config ffigen.yaml`)
- Tests: `flutter test` (Dart) and `cargo test` (Rust, run in `rust/`)

Requires a Rust toolchain (rustup) pinned by `rust/rust-toolchain.toml`.
```

- [ ] **Step 8: 提交**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/teampilot_search
git commit -m "feat(teampilot_search): scaffold package with FFI toolchain smoke test"
```

---

### Task 2: Rust 搜索引擎核心（walk + grep-searcher + 分块 + 取消）

**Files:**
- Create: `client/packages/teampilot_search/rust/src/engine.rs`
- Modify: `client/packages/teampilot_search/rust/src/lib.rs`（ffi shim）
- Create: `client/packages/teampilot_search/rust/tests/fixtures/`（提交的 fixture 树）
- Create: `client/packages/teampilot_search/rust/tests/search_test.rs`

**Interfaces:**
- Consumes: Task 1 的 `TpSearchConfig`/`TpSearchMatch`/`TpSearchChunk` C 布局与错误码约定。
- Produces:
  - `pub mod engine`，核心类型：`engine::SearchConfig`（字段名同 C 布局）、`engine::SearchMatchData{ path, relative_path, line_number, line_text, match_start, match_end }`、`engine::TpSearchHandle`（含 `rx: mpsc::Receiver<SearchMsg>`、`cancel: Arc<AtomicBool>`、`truncated`、`finished`、`pending: Vec<SearchMatchData>`、`max_chunk_matches`、`max_chunk_bytes`）、`engine::SearchMsg::{Line(SearchMatchData), Done{ truncated }}`、`engine::spawn_search(&SearchConfig) -> Result<TpSearchHandle, SearchError>`，`SearchError` 三态：`InvalidPattern` / `RootUnreadable` / `Internal(String)`。
  - FFI 符号（`#[no_mangle]`，签名严格对齐 `teampilot_search.h`）：`tp_search_new`、`tp_search_next`、`tp_search_cancel`、`tp_search_free`。
  - `tp_search_next` 语义：拉取一"块"（至多 `max_chunk_matches` 条或 `max_chunk_bytes` 字节），返回 `0` 继续 / `1` 完成（含 `truncated`）/ `2` 已取消 / `<0` 错误。chunk 内字符串写入调用方提供的 `string_buf`（NUL 结尾），`TpSearchMatch.path/relative_path/line_text` 指向 `string_buf` 内偏移；这些指针**仅在下次调用同一 handle 的 `tp_search_next`/`tp_search_free` 前有效**。

- [ ] **Step 1: 写 Rust 失败测试（fixture + 语义用例）**

`rust/tests/fixtures/basic/`（提交以下文件）:

```
fixtures/basic/
├── a.dart            # "hello world\nfoo hello\n"（2 行，2 个 hello）
├── b.txt             # "no match here\n"
├── sub/
│   └── c.rs          # "HELLO upper\n"
├── .gitignore        # "ignored.txt\n"
├── ignored.txt       # "hello hidden by gitignore\n"
├── .hidden_dir/
│   └── x.dart        # "hello hidden\n"
└── bin.dat           # bytes: \x00\x00hello\x00
```

`rust/tests/search_test.rs`:
```rust
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

use teampilot_search_rust::engine::{self, SearchConfig, SearchMsg};

const FIXTURES: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/basic");

fn cfg(root: &str, pattern: &str) -> SearchConfig {
    SearchConfig {
        root: root.to_string(),
        pattern: pattern.to_string(),
        is_regex: true,
        case_sensitive: false,
        smart_case: false,
        use_gitignore: true,
        files_to_include: vec![],
        files_to_exclude: vec![],
        max_file_size: 0,
        max_results: 0,
        max_chunk_matches: 64,
        max_chunk_bytes: 64 * 1024,
    }
}

fn drain(handle: &mut engine::TpSearchHandle) -> (Vec<SearchMsg>, bool) {
    let mut msgs = vec![];
    loop {
        match handle.rx.recv_timeout(Duration::from_millis(200)) {
            Ok(m) => msgs.push(m),
            Err(mpsc::RecvTimeoutError::Timeout) => break,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
    let truncated = msgs
        .iter()
        .any(|m| matches!(m, SearchMsg::Done { truncated: true }));
    (msgs, truncated)
}

fn matches(msgs: &[SearchMsg]) -> Vec<&engine::SearchMatchData> {
    msgs.iter()
        .filter_map(|m| match m {
            SearchMsg::Line(d) => Some(d),
            _ => None,
        })
        .collect()
}

#[test]
fn finds_case_insensitive_literal_matches_with_offsets() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "hello")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 3, "a.dart x2 + ignored/sub hidden skipped, c.rs uppercase, bin skipped");
    let first = m.iter().find(|d| d.path.ends_with("a.dart")).unwrap();
    assert_eq!(first.line_number, 1);
    assert_eq!(first.line_text, "hello world\n");
    assert_eq!((first.match_start, first.match_end), (0, 5));
}

#[test]
fn regex_and_smart_case() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "h[e]llo")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    assert_eq!(matches(&msgs).len(), 3);

    let mut c = cfg(FIXTURES, "HELLO");
    c.smart_case = true;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1, "smart case: uppercase pattern -> case sensitive");
    assert!(m[0].path.ends_with("c.rs"));
}

#[test]
fn gitignore_and_hidden_skipped() {
    let mut h = engine::spawn_search(&cfg(FIXTURES, "hello")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    for d in matches(&msgs) {
        assert!(!d.path.contains("ignored.txt"));
        assert!(!d.path.contains(".hidden_dir"));
        assert!(!d.path.contains("bin.dat"));
    }
}

#[test]
fn include_exclude_globs() {
    let mut c = cfg(FIXTURES, "hello");
    c.files_to_include = vec!["*.dart".into()];
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert!(m.len() == 2 && m.iter().all(|d| d.path.ends_with(".dart")));

    c = cfg(FIXTURES, "hello");
    c.files_to_exclude = vec!["sub/**".into()];
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    assert!(matches(&msgs).iter().all(|d| !d.path.contains("sub")));
}

#[test]
fn max_results_truncates() {
    let mut c = cfg(FIXTURES, "hello");
    c.max_results = 2;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, truncated) = drain(&mut h);
    assert!(truncated, "truncation flag set");
    assert!(matches(&msgs).len() <= 2);
}

#[test]
fn max_file_size_skips_big_files() {
    let temp = std::env::temp_dir().join("tp_search_big_file_test");
    std::fs::create_dir_all(&temp).unwrap();
    let big = temp.join("big.txt");
    let mut content = String::with_capacity(2 * 1024 * 1024);
    for _ in 0..(2 * 1024 * 1024 / 7) {
        content.push_str("hello x\n");
    }
    std::fs::write(&big, &content).unwrap();
    std::fs::write(temp.join("small.txt"), "hello small\n").unwrap();

    let mut c = cfg(temp.to_str().unwrap(), "hello");
    c.max_file_size = 1024 * 1024;
    let mut h = engine::spawn_search(&c).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1);
    assert!(m[0].path.ends_with("small.txt"));
    let _ = std::fs::remove_dir_all(&temp);
}

#[test]
fn long_line_emits_match_without_text() {
    let temp = std::env::temp_dir().join("tp_search_long_line_test");
    std::fs::create_dir_all(&temp).unwrap();
    let huge_line = format!("start{}end\n", "x".repeat(1024 * 1024 + 64));
    std::fs::write(temp.join("huge.txt"), huge_line).unwrap();

    let mut h = engine::spawn_search(&cfg(temp.to_str().unwrap(), "end")).expect("spawn");
    let (msgs, _) = drain(&mut h);
    let m = matches(&msgs);
    assert_eq!(m.len(), 1);
    assert!(m[0].line_text.is_empty(), "line text dropped, line number kept");
    assert_eq!(m[0].match_start, m[0].match_end);
    let _ = std::fs::remove_dir_all(&temp);
}

#[test]
fn cancel_stops_worker() {
    let mut c = cfg(FIXTURES, "hello");
    c.max_results = 0;
    let mut h = engine::spawn_search(&c).expect("spawn");
    h.cancel.store(true, std::sync::atomic::Ordering::Relaxed);
    let mut got_any_after_cancel = false;
    for _ in 0..10 {
        match h.rx.recv_timeout(Duration::from_millis(100)) {
            Ok(SearchMsg::Line(_)) => got_any_after_cancel = true,
            _ => break,
        }
    }
    std::thread::sleep(Duration::from_millis(50));
    let _ = got_any_after_cancel;
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client/packages/teampilot_search/rust && cargo test`
Expected: 编译失败（`engine` 模块不存在）。这是本任务的"写失败测试"验证点。

- [ ] **Step 3: 实现 `rust/src/engine.rs`**

```rust
//! Search pipeline: worker thread walking the tree with `ignore` and
//! searching files with `grep-searcher`, feeding a bounded channel that
//! `tp_search_next` drains in chunks.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, SendTimeoutError, SyncSender};
use std::sync::Arc;
use std::thread;

use grep::regex::RegexMatcher;
use grep::searcher::sinks::UTF8;
use grep::searcher::{BinaryDetection, SearcherBuilder};
use ignore::overrides::OverrideBuilder;
use ignore::WalkBuilder;

/// Longest line we keep text for; longer lines emit a text-less match.
pub const MAX_LINE_BYTES: usize = 1024 * 1024;
const CHANNEL_CAPACITY: usize = 4096;
const CHANNEL_TICK: std::time::Duration = std::time::Duration::from_millis(5);

#[derive(Debug)]
pub enum SearchError {
    InvalidPattern,
    RootUnreadable,
    Internal(String),
}

pub struct SearchConfig {
    pub root: String,
    pub pattern: String,
    pub is_regex: bool,
    pub case_sensitive: bool,
    pub smart_case: bool,
    pub use_gitignore: bool,
    pub files_to_include: Vec<String>,
    pub files_to_exclude: Vec<String>,
    pub max_file_size: u64,
    pub max_results: u64,
    pub max_chunk_matches: usize,
    pub max_chunk_bytes: usize,
}

#[derive(Debug, Clone)]
pub struct SearchMatchData {
    pub path: String,
    pub relative_path: String,
    pub line_number: u64,
    pub line_text: String,
    pub match_start: usize,
    pub match_end: usize,
}

pub enum SearchMsg {
    Line(SearchMatchData),
    Done { truncated: bool },
}

pub struct TpSearchHandle {
    pub rx: Receiver<SearchMsg>,
    pub cancel: Arc<AtomicBool>,
    pub truncated: bool,
    pub finished: bool,
    pub pending: Vec<SearchMatchData>,
    pub max_chunk_matches: usize,
    pub max_chunk_bytes: usize,
}

fn has_uppercase(s: &str) -> bool {
    s.chars().any(|c| c.is_uppercase())
}

fn build_matcher(config: &SearchConfig) -> Result<RegexMatcher, SearchError> {
    let mut builder = grep::regex::RegexMatcherBuilder::new();
    if !config.case_sensitive {
        if config.smart_case && has_uppercase(&config.pattern) {
            // smart case: uppercase pattern means case-sensitive.
        } else {
            builder.case_insensitive(true);
        }
    }
    let pattern = if config.is_regex {
        config.pattern.clone()
    } else {
        regex_syntax::escape(&config.pattern)
    };
    builder.build(&pattern).map_err(|_| SearchError::InvalidPattern)
}

fn build_walker(config: &SearchConfig) -> Result<WalkBuilder, SearchError> {
    if !Path::new(&config.root).is_dir() {
        return Err(SearchError::RootUnreadable);
    }
    let mut wb = WalkBuilder::new(&config.root);
    wb.hidden(true)
        .ignore(config.use_gitignore)
        .git_ignore(config.use_gitignore)
        .git_global(false) // deterministic: no user-global gitignore
        .git_exclude(false)
        .require_git(false) // honor .gitignore even outside git repos (IDE semantics)
        .parents(true)
        .follow_links(false);

    let mut ob = OverrideBuilder::new(&config.root);
    for g in &config.files_to_include {
        ob.add(g).map_err(|e| SearchError::Internal(e.to_string()))?;
    }
    for g in &config.files_to_exclude {
        ob.add(&format!("!{g}"))
            .map_err(|e| SearchError::Internal(e.to_string()))?;
    }
    let overrides = ob
        .build()
        .map_err(|e| SearchError::Internal(e.to_string()))?;
    wb.overrides(overrides);
    Ok(wb)
}

enum SendOutcome {
    Sent,
    Disconnected,
    Cancelled,
}

fn send_with_cancel(
    tx: &SyncSender<SearchMsg>,
    msg: SearchMsg,
    cancel: &AtomicBool,
) -> SendOutcome {
    let mut msg = Some(msg);
    loop {
        if cancel.load(Ordering::Relaxed) {
            return SendOutcome::Cancelled;
        }
        match tx.send_timeout(msg.take().unwrap(), CHANNEL_TICK) {
            Ok(()) => return SendOutcome::Sent,
            Err(SendTimeoutError::Timeout(m)) => msg = Some(m),
            Err(SendTimeoutError::Disconnected(_)) => return SendOutcome::Disconnected,
        }
    }
}

pub fn spawn_search(config: &SearchConfig) -> Result<TpSearchHandle, SearchError> {
    let matcher = Arc::new(build_matcher(config)?);
    let walker = build_walker(config)?;
    let root = config.root.clone();

    let cancel = Arc::new(AtomicBool::new(false));
    let stop = Arc::new(AtomicBool::new(false));
    let total = Arc::new(AtomicU64::new(0));
    let (tx, rx) = mpsc::sync_channel(CHANNEL_CAPACITY);

    let worker_cancel = cancel.clone();
    let worker_stop = stop.clone();
    let worker_total = total.clone();
    let worker_matcher = matcher.clone();
    let max_results = config.max_results;
    let max_file_size = config.max_file_size;

    thread::spawn(move || {
        walker.run(|| {
            let tx = tx.clone();
            let cancel = worker_cancel.clone();
            let stop = worker_stop.clone();
            let total = worker_total.clone();
            let matcher = worker_matcher.clone();
            Box::new(move |entry| {
                if cancel.load(Ordering::Relaxed) || stop.load(Ordering::Relaxed) {
                    return;
                }
                if !entry.is_file() {
                    return;
                }
                let path = entry.path();
                if max_file_size > 0 {
                    if let Ok(md) = entry.metadata() {
                        if md.len() > max_file_size {
                            return;
                        }
                    }
                }
                let relative_path = path
                    .strip_prefix(&root)
                    .unwrap_or(path)
                    .to_string_lossy()
                    .into_owned();
                let path_str = path.to_string_lossy().into_owned();

                let mut searcher = SearcherBuilder::new()
                    .binary_detection(BinaryDetection::quit(b'\x00'))
                    .build();

                let _ = searcher.search_path(
                    path,
                    UTF8(|lnum, line| {
                        if cancel.load(Ordering::Relaxed) || stop.load(Ordering::Relaxed) {
                            return Ok(false);
                        }
                        if line.len() > MAX_LINE_BYTES {
                            // Text-less placeholder: line number kept, offsets zeroed.
                            let count = total.fetch_add(1, Ordering::Relaxed) + 1;
                            let data = SearchMatchData {
                                path: path_str.clone(),
                                relative_path: relative_path.clone(),
                                line_number: lnum as u64,
                                line_text: String::new(),
                                match_start: 0,
                                match_end: 0,
                            };
                            match send_with_cancel(&tx, SearchMsg::Line(data), &cancel) {
                                SendOutcome::Cancelled | SendOutcome::Disconnected => {
                                    return Ok(false)
                                }
                                SendOutcome::Sent => {}
                            }
                            if max_results > 0 && count >= max_results {
                                stop.store(true, Ordering::Relaxed);
                                return Ok(false);
                            }
                            return Ok(true);
                        }
                        for m in matcher.find_iter(line) {
                            let count = total.fetch_add(1, Ordering::Relaxed) + 1;
                            let data = SearchMatchData {
                                path: path_str.clone(),
                                relative_path: relative_path.clone(),
                                line_number: lnum as u64,
                                line_text: String::from_utf8_lossy(line).into_owned(),
                                match_start: m.start(),
                                match_end: m.end(),
                            };
                            match send_with_cancel(&tx, SearchMsg::Line(data), &cancel) {
                                SendOutcome::Cancelled | SendOutcome::Disconnected => {
                                    return Ok(false)
                                }
                                SendOutcome::Sent => {}
                            }
                            if max_results > 0 && count >= max_results {
                                stop.store(true, Ordering::Relaxed);
                                return Ok(false);
                            }
                        }
                        Ok(true)
                    }),
                );
            })
        });
        let truncated = stop.load(Ordering::Relaxed);
        let _ = tx.send(SearchMsg::Done {
            truncated,
        });
    });

    Ok(TpSearchHandle {
        rx,
        cancel,
        truncated: false,
        finished: false,
        pending: Vec::new(),
        max_chunk_matches: config.max_chunk_matches,
        max_chunk_bytes: config.max_chunk_bytes,
    })
}
```

- [ ] **Step 4: 实现 `rust/src/lib.rs` 的 FFI shim（替换 Task 1 占位）**

```rust
mod engine;

use std::ffi::{c_char, CStr, CString};
use std::slice;

pub use engine::{SearchConfig, SearchMatchData, SearchMsg, SearchError, TpSearchHandle};

use engine::spawn_search;

#[repr(C)]
pub struct TpSearchConfig {
    root: *const c_char,
    pattern: *const c_char,
    is_regex: i32,
    case_sensitive: i32,
    smart_case: i32,
    use_gitignore: i32,
    files_to_include: *const *const c_char,
    files_to_include_count: u32,
    files_to_exclude: *const *const c_char,
    files_to_exclude_count: u32,
    max_file_size: u64,
    max_results: u64,
    max_chunk_matches: u32,
    max_chunk_bytes: u32,
}

#[repr(C)]
pub struct TpSearchMatch {
    path: *const c_char,
    relative_path: *const c_char,
    line_number: u64,
    line_text: *const c_char,
    match_start: u32,
    match_end: u32,
}

#[repr(C)]
pub struct TpSearchChunk {
    string_buf: *mut c_char,
    string_buf_cap: u32,
    string_buf_len: u32,
    matches: *mut TpSearchMatch,
    matches_cap: u32,
    matches_len: u32,
    truncated: i32,
}

const ERR_INVALID_PATTERN: i32 = -1;
const ERR_ROOT_UNREADABLE: i32 = -2;
const ERR_INTERNAL: i32 = -3;

unsafe fn read_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("null string pointer".into());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(str::to_owned)
        .map_err(|e| e.to_string())
}

unsafe fn read_string_array(
    ptr: *const *const c_char,
    count: u32,
) -> Result<Vec<String>, String> {
    if ptr.is_null() {
        return Ok(Vec::new());
    }
    let items = slice::from_raw_parts(ptr, count as usize);
    items.iter().map(|p| read_string(*p)).collect()
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_version() -> *const c_char {
    c"teampilot_search/0.1.0".as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_new(
    config: *const TpSearchConfig,
    out: *mut *mut TpSearchHandle,
) -> i32 {
    if config.is_null() || out.is_null() {
        return ERR_INTERNAL;
    }
    let cfg = unsafe { &*config };
    let parsed = match (|| -> Result<SearchConfig, String> {
        Ok(SearchConfig {
            root: read_string(cfg.root)?,
            pattern: read_string(cfg.pattern)?,
            is_regex: cfg.is_regex != 0,
            case_sensitive: cfg.case_sensitive != 0,
            smart_case: cfg.smart_case != 0,
            use_gitignore: cfg.use_gitignore != 0,
            files_to_include: read_string_array(cfg.files_to_include, cfg.files_to_include_count)?,
            files_to_exclude: read_string_array(cfg.files_to_exclude, cfg.files_to_exclude_count)?,
            max_file_size: cfg.max_file_size,
            max_results: cfg.max_results,
            max_chunk_matches: cfg.max_chunk_matches.max(1) as usize,
            max_chunk_bytes: cfg.max_chunk_bytes.max(1024) as usize,
        })
    })() {
        Ok(c) => c,
        Err(_) => return ERR_INTERNAL,
    };
    match spawn_search(&parsed) {
        Ok(handle) => {
            *out = Box::into_raw(Box::new(handle));
            0
        }
        Err(SearchError::InvalidPattern) => ERR_INVALID_PATTERN,
        Err(SearchError::RootUnreadable) => ERR_ROOT_UNREADABLE,
        Err(SearchError::Internal(_)) => ERR_INTERNAL,
    }
}

fn write_string(buf: &mut [u8], offset: usize, s: &str) -> Result<usize, ()> {
    let bytes = s.as_bytes();
    let end = offset + bytes.len() + 1;
    if end > buf.len() {
        return Err(());
    }
    buf[offset..offset + bytes.len()].copy_from_slice(bytes);
    buf[offset + bytes.len()] = 0;
    Ok(end)
}

unsafe fn fill_chunk(h: &mut TpSearchHandle, chunk: &mut TpSearchChunk) {
    chunk.string_buf_len = 0;
    chunk.matches_len = 0;
    chunk.truncated = if h.truncated { 1 } else { 0 };

    let str_cap = chunk.string_buf_cap as usize;
    let str_buf = if chunk.string_buf.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.string_buf as *mut u8, str_cap)
    };
    let m_cap = chunk.matches_cap as usize;
    let m_arr = if chunk.matches.is_null() {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(chunk.matches, m_cap)
    };

    let mut str_off = 0usize;
    let mut m_idx = 0usize;
    while m_idx < m_arr.len() && !h.pending.is_empty() {
        let d = &h.pending[0];
        let path = CString::new(d.path.as_str()).unwrap();
        let rel = CString::new(d.relative_path.as_str()).unwrap();
        let text = CString::new(d.line_text.as_str()).unwrap();
        let path_len = path.as_bytes().len() + 1;
        let rel_len = rel.as_bytes().len() + 1;
        let text_len = text.as_bytes().len() + 1;
        let need = path_len + rel_len + text_len;
        if need > str_cap.saturating_sub(str_off) {
            break; // buffer full; remainder stays pending
        }
        str_off = match write_string(str_buf, str_off, &d.path) {
            Ok(o) => o,
            Err(_) => break,
        };
        let rel_off = str_off;
        str_off = match write_string(str_buf, str_off, &d.relative_path) {
            Ok(o) => o,
            Err(_) => break,
        };
        let text_off = str_off;
        str_off = match write_string(str_buf, str_off, &d.line_text) {
            Ok(o) => o,
            Err(_) => break,
        };
        let base = chunk.string_buf as usize;
        m_arr[m_idx] = TpSearchMatch {
            path: (base + 0) as *const c_char,
            relative_path: (base + rel_off) as *const c_char,
            line_number: d.line_number,
            line_text: (base + text_off) as *const c_char,
            match_start: d.match_start as u32,
            match_end: d.match_end as u32,
        };
        m_idx += 1;
        h.pending.remove(0);
    }
    chunk.string_buf_len = str_off as u32;
    chunk.matches_len = m_idx as u32;
    if h.finished {
        chunk.truncated = if h.truncated { 1 } else { 0 };
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_next(
    handle: *mut TpSearchHandle,
    chunk: *mut TpSearchChunk,
) -> i32 {
    if handle.is_null() || chunk.is_null() {
        return ERR_INTERNAL;
    }
    let h = &mut *handle;
    let c = &mut *chunk;

    if !h.finished && h.pending.len() < h.max_chunk_matches {
        let mut budget = h.max_chunk_matches.saturating_sub(h.pending.len());
        while budget > 0 {
            let pending_bytes: usize =
                h.pending.iter().map(|d| d.line_text.len() + d.path.len()).sum();
            if pending_bytes >= h.max_chunk_bytes {
                break;
            }
            match h.rx.recv_timeout(std::time::Duration::from_millis(5)) {
                Ok(SearchMsg::Line(d)) => {
                    h.pending.push(d);
                    budget -= 1;
                }
                Ok(SearchMsg::Done { truncated }) => {
                    h.truncated = truncated;
                    h.finished = true;
                    break;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => break,
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    h.finished = true;
                    break;
                }
            }
        }
    }

    fill_chunk(h, c);

    if h.cancel.load(Ordering::Relaxed) {
        return 2;
    }
    if h.finished && h.pending.is_empty() {
        return 1;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_cancel(handle: *mut TpSearchHandle) {
    if !handle.is_null() {
        (*handle).cancel.store(true, Ordering::Relaxed);
    }
}

#[no_mangle]
pub unsafe extern "C" fn tp_search_free(handle: *mut TpSearchHandle) {
    if handle.is_null() {
        return;
    }
    let h = Box::from_raw(handle);
    h.cancel.store(true, Ordering::Relaxed);
    drop(h);
}
```

注意：`lib.rs` 中要补 `use std::sync::mpsc;`（`tp_search_next` 用到 `mpsc::RecvTimeoutError`）与 `use std::sync::atomic::Ordering;`（`tp_search_cancel`/`tp_search_next` 用到 `Ordering::Relaxed`），编译器会指出遗漏，补上即可。

- [ ] **Step 5: 跑 Rust 测试**

Run: `cd client/packages/teampilot_search/rust && cargo test`
Expected: 全部通过（依赖首次从 crates.io 拉取，耗时数分钟属正常）。

- [ ] **Step 6: 提交**

```bash
git add client/packages/teampilot_search/rust
git commit -m "feat(teampilot_search): Rust engine with ignore walk + grep-searcher chunked FFI"
```

---

### Task 3: Dart FFI 封装（RustEngine + Stream + 取消）

**Files:**
- Modify: `client/packages/teampilot_search/lib/teampilot_search_bindings_generated.dart`（ffigen 重跑）
- Modify: `client/packages/teampilot_search/lib/teampilot_search.dart`（完整 API）
- Create: `client/packages/teampilot_search/test/rust_engine_test.dart`

**Interfaces:**
- Consumes: Task 2 的 FFI 符号与错误码；Task 1 的 bindings 文件名约定。
- Produces（Dart 公共 API，Task 5 依赖）：
  - `class TpSearchOptions{ pattern, isRegex=true, caseSensitive=false, smartCase=false, useGitignore=true, filesToInclude=[], filesToExclude=[], maxFileSize=10*1024*1024, maxResults=2000 }`
  - `class TpSearchMatch{ path, relativePath, lineNumber, lineText, matchStart, matchEnd }`（matchStart/End 为**字符**偏移）
  - `class TpSearchEngine{ bool supportsPath(String path); Stream<TpSearchMatch> search(String root, TpSearchOptions options); void cancel(); }`
  - `RegExp? compilePattern(TpSearchOptions o)` —— 预校验，非法正则返回 null（供 search 与 fallback 共用）

- [ ] **Step 1: 重跑 ffigen 生成完整 bindings**

```bash
cd client/packages/teampilot_search && dart run ffigen --config ffigen.yaml
```
Expected: `lib/teampilot_search_bindings_generated.dart` 现在包含 `tp_search_new/next/cancel/free` 与 `TpSearchConfig/TpSearchMatch/TpSearchChunk` 的 struct 类。

- [ ] **Step 2: 写失败测试（真实 FFI + fixture 树）**

`test/rust_engine_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_search_test_');
    File('${fixture.path}/a.dart')
        .writeAsStringSync('hello world\nfoo hello\n');
    File('${fixture.path}/b.txt').writeAsStringSync('no match here\n');
    Directory('${fixture.path}/sub').createSync();
    File('${fixture.path}/sub/c.rs').writeAsStringSync('HELLO upper\n');
    File('${fixture.path}/.gitignore').writeAsStringSync('ignored.txt\n');
    File('${fixture.path}/ignored.txt').writeAsStringSync('hello ignored\n');
    Directory('${fixture.path}/.hidden_dir').createSync();
    File('${fixture.path}/.hidden_dir/x.dart').writeAsStringSync('hello hidden\n');
    File('${fixture.path}/bin.dat').writeAsBytesSync([0, 0, 104, 101, 108, 108, 111, 0]);
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  TpSearchEngine engine() => TpSearchEngine();

  test('streams matches with char offsets, skipping hidden/gitignored/binary',
      () async {
    final matches = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .toList();
    expect(matches.map((m) => m.relativePath), [
      'a.dart',
      'a.dart',
      'sub/c.rs',
    ]);
    final first = matches.first;
    expect(first.lineNumber, 1);
    expect(first.lineText, 'hello world\n');
    expect(first.matchStart, 0);
    expect(first.matchEnd, 5);
  });

  test('regex + smart case', () async {
    final smart = await engine()
        .search(
          fixture.path,
          const TpSearchOptions(pattern: 'HELLO', smartCase: true),
        )
        .toList();
    expect(smart.map((m) => m.relativePath), ['sub/c.rs']);

    final re = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'h[e]llo'))
        .toList();
    expect(re.length, 3);
  });

  test('non-ASCII byte offset converts to char offset', () async {
    File('${fixture.path}/zh.txt')
        .writeAsStringSync('你好 hello world\n');
    final m = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .firstWhere((m) => m.relativePath == 'zh.txt');
    expect(m.lineText, '你好 hello world\n');
    expect(m.matchStart, 3); // 2 CJK chars (6 bytes) + 1 space = char offset 3
    expect(m.matchEnd, 8);
  });

  test('invalid regex -> stream error, no crash', () async {
    await expectLater(
      engine().search(fixture.path, const TpSearchOptions(pattern: '[unclosed')),
      throwsA(isA<FormatException>()),
    );
  });

  test('maxResults truncates with done', () async {
    final matches = await engine()
        .search(
          fixture.path,
          const TpSearchOptions(pattern: 'hello', maxResults: 2),
        )
        .toList();
    expect(matches.length, 2);
  });

  test('cancel() stops the stream', () async {
    final e = engine();
    final collected = <TpSearchMatch>[];
    final sub = e
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .listen(collected.add, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    e.cancel();
    sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('non-existent root -> stream error', () async {
    await expectLater(
      engine().search('${fixture.path}/nope', const TpSearchOptions(pattern: 'x')),
      throwsA(anything),
    );
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd client/packages/teampilot_search && flutter test test/rust_engine_test.dart`
Expected: 编译失败（`TpSearchOptions`/`TpSearchEngine` 不存在）。

- [ ] **Step 4: 实现 Dart API（重写 `lib/teampilot_search.dart`）**

```dart
/// Ripgrep-based content search engine for TeamPilot.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'teampilot_search_bindings_generated.dart' as bindings;

/// Version string reported by the Rust core, e.g. `teampilot_search/0.1.0`.
String engineVersion() {
  final ptr = bindings.tp_search_version();
  return ptr.cast<ffi.Utf8>().toDartString();
}

/// Search options, mirroring VS Code search semantics.
class TpSearchOptions {
  const TpSearchOptions({
    required this.pattern,
    this.isRegex = true,
    this.caseSensitive = false,
    this.smartCase = false,
    this.useGitignore = true,
    this.filesToInclude = const [],
    this.filesToExclude = const [],
    this.maxFileSize = 10 * 1024 * 1024,
    this.maxResults = 2000,
  });

  final String pattern;
  final bool isRegex;
  final bool caseSensitive;
  final bool smartCase;
  final bool useGitignore;
  final List<String> filesToInclude;
  final List<String> filesToExclude;
  final int? maxFileSize;
  final int? maxResults;
}

/// One matching line, with the match range in [matchStart, matchEnd)
/// (character offsets within [lineText]).
class TpSearchMatch {
  const TpSearchMatch({
    required this.path,
    required this.relativePath,
    required this.lineNumber,
    required this.lineText,
    required this.matchStart,
    required this.matchEnd,
  });

  final String path;
  final String relativePath;

  /// 1-based line number.
  final int lineNumber;
  final String lineText;

  /// Character offset of the match within [lineText].
  final int matchStart;
  final int matchEnd;
}

/// Pre-validates [options.pattern]; returns null for an invalid regex.
RegExp? compilePattern(TpSearchOptions options) {
  if (!options.isRegex) return null;
  try {
    return RegExp(
      options.pattern,
      caseSensitive: options.caseSensitive,
    );
  } on FormatException {
    return null;
  }
}

const int _kStatusMore = 0;
const int _kStatusDone = 1;
const int _kStatusCancelled = 2;
const int _kErrInvalidPattern = -1;
const int _kErrRootUnreadable = -2;

/// Chunk sizes used for the FFI calls.
const int _kMaxChunkMatches = 256;
const int _kMaxChunkBytes = 64 * 1024;

int _byteToCharOffset(String line, int byteOffset) {
  final bytes = utf8.encode(line);
  return utf8.decode(bytes.sublist(0, byteOffset), allowMalformed: true).length;
}

/// Rust-backed content search engine.
class TpSearchEngine {
  bindings.TpSearchHandle? _handle;

  /// True when [path] is directly readable by this process (local disk or a
  /// Windows `\\wsl$\...` UNC path), i.e. the Rust engine can search it.
  bool supportsPath(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Cancels the active [search] stream (if any).
  void cancel() {
    final h = _handle;
    if (h != null) {
      bindings.tp_search_cancel(h);
    }
  }

  /// Searches [root] for [options.pattern], streaming matches.
  ///
  /// Throws [StateError] when [root] is not readable by this process;
  /// emits a [FormatException] when the pattern is an invalid regex.
  Stream<TpSearchMatch> search(String root, TpSearchOptions options) async* {
    final pattern = compilePattern(options);
    if (pattern == null && options.isRegex) {
      throw FormatException('invalid regex: ${options.pattern}');
    }
    if (!supportsPath(root)) {
      throw StateError('path not readable locally: $root');
    }

    final handle = _open(root, options);
    _handle = handle;
    final matchesBuf = calloc<bindings.TpSearchMatch>(_kMaxChunkMatches);
    final stringsBuf = calloc<ffi.Uint8>(_kMaxChunkBytes);
    try {
      while (true) {
        final chunk = bindings.TpSearchChunk(
          string_buf: stringsBuf.cast<ffi.Char>(),
          string_buf_cap: _kMaxChunkBytes,
          string_buf_len: 0,
          matches: matchesBuf,
          matches_cap: _kMaxChunkMatches,
          matches_len: 0,
          truncated: 0,
        );
        final status = bindings.tp_search_next(handle, chunk);
        if (status == _kStatusCancelled) break;
        if (status < 0) {
          throw StateError('search failed with code $status');
        }
        final count = chunk.matches_len;
        final base = stringsBuf.address;
        for (var i = 0; i < count; i++) {
          final m = matchesBuf[i];
          final lineText = _readCStringAt(base, m.line_text);
          yield TpSearchMatch(
            path: _readCStringAt(base, m.path),
            relativePath: _readCStringAt(base, m.relative_path),
            lineNumber: m.line_number,
            lineText: lineText,
            matchStart: _byteToCharOffset(lineText, m.match_start),
            matchEnd: _byteToCharOffset(lineText, m.match_end),
          );
        }
        if (status == _kStatusDone) break;
        if (count == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      calloc.free(matchesBuf);
      calloc.free(stringsBuf);
      bindings.tp_search_free(handle);
      _handle = null;
    }
  }

  bindings.TpSearchHandle _open(String root, TpSearchOptions options) {
    final cRoot = root.toNativeUtf8();
    final cPattern = options.pattern.toNativeUtf8();
    final includePtrs = options.filesToInclude.map((s) => s.toNativeUtf8()).toList();
    final excludePtrs = options.filesToExclude.map((s) => s.toNativeUtf8()).toList();
    final includes = calloc<ffi.Pointer<ffi.Char>>(includePtrs.length);
    final excludes = calloc<ffi.Pointer<ffi.Char>>(excludePtrs.length);
    for (var i = 0; i < includePtrs.length; i++) {
      includes[i] = includePtrs[i].cast<ffi.Char>();
    }
    for (var i = 0; i < excludePtrs.length; i++) {
      excludes[i] = excludePtrs[i].cast<ffi.Char>();
    }
    final config = calloc<bindings.TpSearchConfig>()
      ..ref.root = cRoot.cast<ffi.Char>()
      ..ref.pattern = cPattern.cast<ffi.Char>()
      ..ref.is_regex = options.isRegex ? 1 : 0
      ..ref.case_sensitive = options.caseSensitive ? 1 : 0
      ..ref.smart_case = options.smartCase ? 1 : 0
      ..ref.use_gitignore = options.useGitignore ? 1 : 0
      ..ref.files_to_include = includes
      ..ref.files_to_include_count = includePtrs.length
      ..ref.files_to_exclude = excludes
      ..ref.files_to_exclude_count = excludePtrs.length
      ..ref.max_file_size = options.maxFileSize ?? 0
      ..ref.max_results = options.maxResults ?? 0
      ..ref.max_chunk_matches = _kMaxChunkMatches
      ..ref.max_chunk_bytes = _kMaxChunkBytes;

    final out = calloc<ffi.Pointer<bindings.TpSearchHandle>>(1);
    try {
      final status = bindings.tp_search_new(config, out);
      if (status == _kErrInvalidPattern) {
        throw FormatException('invalid regex: ${options.pattern}');
      }
      if (status == _kErrRootUnreadable) {
        throw StateError('root unreadable: $root');
      }
      if (status < 0) {
        throw StateError('search init failed with code $status');
      }
      return out.value;
    } finally {
      calloc.free(config);
      calloc.free(out);
      for (final p in includePtrs) {
        malloc.free(p);
      }
      for (final p in excludePtrs) {
        malloc.free(p);
      }
      malloc.free(cRoot);
      malloc.free(cPattern);
      calloc.free(includes);
      calloc.free(excludes);
    }
  }

  String _readCStringAt(int base, ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return '';
    final offset = ptr.address - base;
    return stringsBufToString(offset);
  }

  String stringsBufToString(int offset) {
    // string_buf is only valid during this chunk; we read the NUL-terminated
    // C string at [offset] directly from the stringsBuf allocation.
    // Implemented via toDartString on a pointer derived from the base.
    return ffiPointerToString(offset);
  }

  String ffiPointerToString(int offset) {
    // placeholder replaced in Step 5
    throw UnimplementedError();
  }
}
```

- [ ] **Step 5: 修正 chunk 内字符串读取（补 `stringsBuf` 基址）**

Step 4 的 `_readCStringAt` 写法有缺陷：`stringsBuf` 在 `search` 的 try 块里分配，`_readCStringAt` 拿不到。修正为：把 `stringsBuf` 作为参数传入，或用 `ffi` 的 `Pointer` 运算：

```dart
  String _readCStringAt(ffi.Pointer<ffi.Uint8> buf, ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return '';
    final offset = ptr.address - buf.address;
    return buf.cast<ffi.Char>().elementAt(offset).toDartString();
  }
```

在 `search` 循环里调用处改为 `_readCStringAt(stringsBuf, m.line_text)`（三处：path/relative_path/line_text）。`ffi` 的 `Pointer.cast<Char>().elementAt(n)` 语义为"按 Char 大小偏移 n 个元素"，`ptr.address - buf.address` 已是字节差，需改为 `elementAt(offset ~/ sizeOf<ffi.Char>())`；`sizeOf<ffi.Char>() == 1`，直接 `elementAt(offset)` 即可。

- [ ] **Step 6: 跑测试**

Run: `cd client/packages/teampilot_search && flutter test test/rust_engine_test.dart`
Expected: 全部 PASS。

- [ ] **Step 7: 集成标记测试（spec 测试一节要求）**

`test/search_stream_integration_test.dart`（与 app 侧 `--exclude-tags integration` 约定一致，用 `package:test` 的 `@Tags`）:
```dart
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  test('streams first results promptly and stops on maxResults', () async {
    final dir = Directory.systemTemp.createTempSync('tp_search_it_');
    for (var i = 0; i < 50; i++) {
      File('${dir.path}/f$i.dart')
          .writeAsStringSync('line one\nhello target\nline three\n');
    }
    addTearDown(() => dir.deleteSync(recursive: true));

    final stopwatch = Stopwatch()..start();
    final engine = TpSearchEngine();
    final matches = await engine
        .search(dir.path, const TpSearchOptions(pattern: 'hello target'))
        .take(10)
        .toList();
    stopwatch.stop();

    expect(matches.length, 10);
    expect(stopwatch.elapsedMilliseconds,
        lessThan(5000)); // streaming, not a full-tree wait
  });
}
```

Run: `cd client/packages/teampilot_search && flutter test test/search_stream_integration_test.dart`
Expected: PASS（首次跑含 native asset 编译，可能慢；再次跑应远低于 5 s 阈值）。

- [ ] **Step 8: 跑全量检查**

Run: `cd client/packages/teampilot_search && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
Expected: 通过（analyze 无 fatal）。

- [ ] **Step 9: 提交**

```bash
git add client/packages/teampilot_search/lib client/packages/teampilot_search/test
git commit -m "feat(teampilot_search): Dart FFI wrapper with streaming search and cancel"
```

---

### Task 4: 纯 Dart fallback 引擎（SSH 等非本地后端）

**Files:**
- Create: `client/packages/teampilot_search/lib/src/search_file_reader.dart`
- Create: `client/packages/teampilot_search/lib/src/fallback_search_engine.dart`
- Modify: `client/packages/teampilot_search/lib/teampilot_search.dart`（导出 fallback API）
- Create: `client/packages/teampilot_search/test/fallback_search_engine_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `TpSearchOptions` / `TpSearchMatch` / `compilePattern`。
- Produces:
  - `abstract interface class SearchFileReader { Future<List<SearchDirEntry>> listDir(String path); Future<List<String>?> readLines(String path); }`
  - `class SearchDirEntry { final String name; final bool isDirectory; final int? size; }`
  - `Stream<TpSearchMatch> fallbackSearch(SearchFileReader reader, String root, TpSearchOptions options)`（纯函数，包内自治）
  - 常量 `kFallbackIgnoredDirNames`（与 app 侧 `workspaceFileIgnoredDirNames` 同一份名单：`.git .hg .svn node_modules .dart_tool build .idea .gradle .next dist`）

- [ ] **Step 1: 写失败测试（内存假 reader）**

`test/fallback_search_engine_test.dart`:
```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/src/fallback_search_engine.dart';
import 'package:teampilot_search/src/search_file_reader.dart';
import 'package:teampilot_search/teampilot_search.dart';

class MemoryReader implements SearchFileReader {
  MemoryReader(this.tree);

  /// path -> list of lines
  final Map<String, List<String>> tree;

  @override
  Future<List<SearchDirEntry>> listDir(String path) async {
    final entries = <SearchDirEntry>[];
    final seen = <String>{};
    for (final p in tree.keys) {
      final rel = p.substring(path.length + 1);
      final parts = rel.split('/');
      if (parts.length == 1) {
        if (seen.add(p)) {
          entries.add(SearchDirEntry(name: parts[0], isDirectory: false, size: null));
        }
      } else {
        final dir = '$path/${parts[0]}';
        if (seen.add(dir)) {
          entries.add(SearchDirEntry(name: parts[0], isDirectory: true, size: null));
        }
      }
    }
    return entries;
  }

  @override
  Future<List<String>?> readLines(String path) async => tree[path];
}

void main() {
  late MemoryReader reader;

  setUp(() {
    reader = MemoryReader({
      '/root/a.dart': ['hello world', 'foo hello'],
      '/root/b.txt': ['no match'],
      '/root/sub/c.rs': ['HELLO upper'],
      '/root/.hidden/x.dart': ['hello hidden'],
      '/root/node_modules/pkg.js': ['hello dep'],
      '/root/build/out.js': ['hello build'],
      '/root/bin.dat': ['\u0000hello\u0000'],
    });
  });

  test('walks tree, skips hidden/ignored dirs, matches case-insensitive',
      () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'hello'),
    ).toList();
    expect(matches.map((m) => m.relativePath), ['a.dart', 'a.dart', 'sub/c.rs']);
  });

  test('regex + include/exclude globs + maxResults', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(
        pattern: 'h[e]llo',
        filesToInclude: ['*.dart'],
        maxResults: 1,
      ),
    ).toList();
    expect(matches.length, 1);
    expect(matches.single.relativePath, 'a.dart');
  });

  test('smart case', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'HELLO', smartCase: true),
    ).toList();
    expect(matches.single.relativePath, 'sub/c.rs');
  });

  test('binary file (NUL byte) skipped', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'hello', filesToInclude: ['bin.dat']),
    ).toList();
    expect(matches, isEmpty);
  });

  test('unreadable file skipped, unreadable dir skipped', () async {
    final reader2 = MemoryReader({
      '/root/ok.dart': ['hello ok'],
      '/root/boom.dart': ['hello boom'],
    })..unreadable = {'/root/boom.dart', '/root/locked'};
    reader2.tree['/root/locked'] = ['hello locked'];
    final matches = await fallbackSearch(
      reader2,
      '/root',
      const TpSearchOptions(pattern: 'hello'),
    ).toList();
    expect(matches.map((m) => m.relativePath), ['ok.dart']);
  });

  test('invalid regex -> error event', () async {
    await expectLater(
      fallbackSearch(reader, '/root', const TpSearchOptions(pattern: '[unclosed')),
      throwsA(isA<FormatException>()),
    );
  });

  test('line too long -> match without text', () async {
    final huge = 'start${'x' * 2000000}end';
    final reader2 = MemoryReader({'/root/huge.txt': [huge]});
    final matches = await fallbackSearch(
      reader2,
      '/root',
      const TpSearchOptions(pattern: 'end'),
    ).toList();
    expect(matches.single.lineText, isEmpty);
  });
}
```

注意：`MemoryReader` 的 `unreadable` 字段是测试辅助，需在 `MemoryReader` 里实现：`Set<String> unreadable = {};`，`listDir` 对不可读目录返回空列表、`readLines` 对不可读文件返回 null。上述测试代码里的 `reader2` 构造写法需要相应补上 `unreadable` 成员。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client/packages/teampilot_search && flutter test test/fallback_search_engine_test.dart`
Expected: 编译失败（`fallbackSearch` 等不存在）。

- [ ] **Step 3: 实现 `search_file_reader.dart` 与 `fallback_search_engine.dart`**

`lib/src/search_file_reader.dart`:
```dart
/// Minimal file-access abstraction for the pure-Dart fallback engine.
/// The app adapts its `Filesystem` (e.g. SftpFilesystem) to this interface.
abstract interface class SearchFileReader {
  /// Lists immediate children of [path]. Returns [] when unreadable.
  Future<List<SearchDirEntry>> listDir(String path);

  /// Reads [path] as text lines (without line terminators).
  /// Returns null when the file is unreadable or binary (NUL byte).
  Future<List<String>?> readLines(String path);
}

class SearchDirEntry {
  const SearchDirEntry({
    required this.name,
    required this.isDirectory,
    this.size,
  });

  final String name;
  final bool isDirectory;
  final int? size;
}
```

`lib/src/fallback_search_engine.dart`:
```dart
import '../teampilot_search.dart';
import 'search_file_reader.dart';

/// Directory names skipped wholesale during fallback traversal.
const kFallbackIgnoredDirNames = {
  '.git', '.hg', '.svn', 'node_modules', '.dart_tool', 'build',
  '.idea', '.gradle', '.next', 'dist',
};

/// Longest line whose text is kept; longer lines yield text-less matches.
const int kFallbackMaxLineBytes = 1024 * 1024;

/// Pure-Dart content search over a [SearchFileReader], used when the target
/// filesystem is not directly readable by this process (e.g. SSH/SFTP).
///
/// Mirrors [TpSearchEngine.search] semantics: case-insensitive by default,
/// hidden entries skipped, [kFallbackIgnoredDirNames] skipped, glob
/// include/exclude, [TpSearchOptions.maxFileSize] / [maxResults] caps.
Stream<TpSearchMatch> fallbackSearch(
  SearchFileReader reader,
  String root,
  TpSearchOptions options,
) async* {
  final pattern = compilePattern(options);
  if (options.isRegex && pattern == null) {
    throw FormatException('invalid regex: ${options.pattern}');
  }
  final q = options.isRegex ? options.pattern : RegExp.escape(options.pattern);
  final flags = options.caseSensitive ? '' : 'i';
  final rx = RegExp(q, caseSensitive: options.caseSensitive);
  final includeGlobs = options.filesToInclude
      .map((g) => _Glob(g))
      .toList(growable: false);
  final excludeGlobs = options.filesToExclude
      .map((g) => _Glob(g))
      .toList(growable: false);

  final queue = <String>[root];
  var truncated = false;
  var matchCount = 0;

  while (queue.isNotEmpty) {
    if (truncated) break;
    final dir = queue.removeAt(0);
    final entries = await reader.listDir(dir);
    for (final entry in entries) {
      if (truncated) break;
      final name = entry.name;
      if (name.startsWith('.')) continue;
      final full = dir == root ? '$root/$name' : '$dir/$name';
      if (entry.isDirectory) {
        if (kFallbackIgnoredDirNames.contains(name)) continue;
        queue.add(full);
        continue;
      }
      final rel = full.substring(root.length + 1);
      if (includeGlobs.isNotEmpty && !includeGlobs.any((g) => g.matches(rel))) {
        continue;
      }
      if (excludeGlobs.any((g) => g.matches(rel))) continue;
      if (options.maxFileSize != null &&
          entry.size != null &&
          entry.size! > options.maxFileSize!) {
        continue;
      }
      final lines = await reader.readLines(full);
      if (lines == null) continue;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.codeUnits.length > kFallbackMaxLineBytes) {
          matchCount++;
          yield TpSearchMatch(
            path: full,
            relativePath: rel,
            lineNumber: i + 1,
            lineText: '',
            matchStart: 0,
            matchEnd: 0,
          );
          if (options.maxResults != null && matchCount >= options.maxResults!) {
            truncated = true;
            break;
          }
          continue;
        }
        final matches = rx.allMatches(line);
        if (matches.isEmpty) continue;
        for (final m in matches) {
          matchCount++;
          yield TpSearchMatch(
            path: full,
            relativePath: rel,
            lineNumber: i + 1,
            lineText: line,
            matchStart: m.start,
            matchEnd: m.end,
          );
          if (options.maxResults != null && matchCount >= options.maxResults!) {
            truncated = true;
            break;
          }
        }
      }
    }
  }
}

/// Tiny gitignore-style glob (supports `*`, `**`, `?`, `[...]`).
class _Glob {
  _Glob(String pattern) : _rx = RegExp(_translate(pattern));

  final RegExp _rx;

  bool matches(String path) => _rx.hasMatch(path);

  static String _translate(String pattern) {
    var out = '^';
    var chars = pattern.split('');
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      switch (c) {
        case '*':
          if (i + 1 < chars.length && chars[i + 1] == '*') {
            i++;
            out += '.*';
          } else {
            out += '[^/]*';
          }
        case '?':
          out += '[^/]';
        case '[':
          out += '[';
        case ']':
          out += ']';
        case '.':
        case '+':
        case '(':
        case ')':
        case '{':
        case '}':
        case '^':
        case r'$':
        case '|':
        case r'\':
          out += '\\$c';
        default:
          out += c;
      }
    }
    out += r'$';
    return out;
  }
}
```

- [ ] **Step 4: 修正 `_Glob` 的边界（行尾匹配与目录语义）**

测试运行后若 `filesToInclude: ['*.dart']` 匹配不上 `a.dart`（相对路径含子目录时 `^[^/]*\.dart$` 不匹配 `sub/x.dart`），按 gitignore 语义补一个变体：若 pattern 不含 `/`，前缀 `(?:^|/)` 使 `*.dart` 匹配任意层级文件名：

```dart
  static String _translate(String pattern) {
    var out = '^';
    if (!pattern.contains('/')) out += '(?:.*/)?';
    ...
```

- [ ] **Step 5: 导出公共 API**

`lib/teampilot_search.dart` 追加：
```dart
export 'src/fallback_search_engine.dart' show fallbackSearch, kFallbackIgnoredDirNames, kFallbackMaxLineBytes;
export 'src/search_file_reader.dart' show SearchFileReader, SearchDirEntry;
```

- [ ] **Step 6: 跑测试**

Run: `cd client/packages/teampilot_search && flutter test test/fallback_search_engine_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
Expected: 全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add client/packages/teampilot_search/lib client/packages/teampilot_search/test
git commit -m "feat(teampilot_search): pure-Dart fallback engine over SearchFileReader"
```

---

### Task 5: app 接线 + CI

**Files:**
- Modify: `client/pubspec.yaml`（加 path 依赖 `teampilot_search`）
- Create: `client/lib/services/file_tree/workspace_content_search_service.dart`
- Create: `client/test/services/file_tree/workspace_content_search_service_test.dart`
- Modify: `.github/workflows/client-verify.yml`（包测试步骤 + Android 构建验证）
- Modify: `docs/DEVELOPMENT.md`（补包测试命令，可选一行）

**Interfaces:**
- Consumes: Task 3/4 的 `TpSearchEngine`、`TpSearchOptions`、`TpSearchMatch`、`fallbackSearch`、`SearchFileReader`、`SearchDirEntry`；app 侧 `Filesystem`（`client/lib/services/io/filesystem.dart`，有 `listDir`/`readString`/`stat`）与 `FsDirEntry`。
- Produces: `class WorkspaceContentSearchService{ Stream<WorkspaceContentMatch> search(String root, String pattern, {SearchOptions options}); }`，`WorkspaceContentMatch` 复用/包装 `TpSearchMatch`（直接透传 `TpSearchMatch` 即可，服务只负责选后端）。

- [ ] **Step 1: 加依赖并写失败测试**

`client/pubspec.yaml` 的 dependencies 段（`teampilot_tree_sitter` 之后）：
```yaml
  teampilot_search:
    path: packages/teampilot_search
```

`client/test/services/file_tree/workspace_content_search_service_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/services/file_tree/workspace_content_search_service.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_wss_test_');
    File('${fixture.path}/a.dart').writeAsStringSync('hello world\n');
    File('${fixture.path}/b.txt').writeAsStringSync('hello text\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('uses rust engine for local paths', () async {
    final service = WorkspaceContentSearchService();
    final matches = await service
        .search(fixture.path, 'hello')
        .toList();
    expect(matches.map((m) => m.relativePath).toSet(), {'a.dart', 'b.txt'});
  });

  test('local path through service returns TpSearchMatch', () async {
    final service = WorkspaceContentSearchService();
    final first = await service.search(fixture.path, 'hello').first;
    expect(first, isA<TpSearchMatch>());
  });
}
```

注意：本任务的 service 先只接 Rust 引擎（本地路径）；SSH 适配器（`SftpFilesystem` → `SearchFileReader`）单独小步做（见 Step 5），不阻塞 CI。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/file_tree/workspace_content_search_service_test.dart`
Expected: 编译失败（service 不存在）。

- [ ] **Step 3: 实现 service（后端选择）**

`client/lib/services/file_tree/workspace_content_search_service.dart`:
```dart
import 'dart:io';

import 'package:teampilot_search/teampilot_search.dart';

/// Content search facade over the workspace filesystem backend.
///
/// - Local filesystem (and Windows `\\wsl$` UNC paths): Rust engine.
/// - Everything else (SSH/SFTP): callers pass a [SearchFileReader] adapter
///   via [searchWithReader] and the pure-Dart fallback engine is used.
class WorkspaceContentSearchService {
  WorkspaceContentSearchService();

  final TpSearchEngine _engine = TpSearchEngine();

  /// Searches [root] with the Rust engine. Throws [StateError] when [root]
  /// is not locally readable — use [searchWithReader] for remote paths.
  Stream<TpSearchMatch> search(String root, String pattern,
      {bool isRegex = true,
      bool caseSensitive = false,
      bool smartCase = false,
      bool useGitignore = true,
      List<String> filesToInclude = const [],
      List<String> filesToExclude = const [],
      int? maxResults}) {
    if (!_supportsPath(root)) {
      throw StateError('path not locally readable: $root');
    }
    return _engine.search(
      root,
      TpSearchOptions(
        pattern: pattern,
        isRegex: isRegex,
        caseSensitive: caseSensitive,
        smartCase: smartCase,
        useGitignore: useGitignore,
        filesToInclude: filesToInclude,
        filesToExclude: filesToExclude,
        maxResults: maxResults,
      ),
    );
  }

  /// Searches a remote/abstract filesystem through [reader].
  Stream<TpSearchMatch> searchWithReader(
    SearchFileReader reader,
    String root,
    String pattern, {
    bool isRegex = true,
    bool caseSensitive = false,
    bool smartCase = false,
    bool useGitignore = true,
    List<String> filesToInclude = const [],
    List<String> filesToExclude = const [],
    int? maxResults,
  }) {
    return fallbackSearch(
      reader,
      root,
      TpSearchOptions(
        pattern: pattern,
        isRegex: isRegex,
        caseSensitive: caseSensitive,
        smartCase: smartCase,
        useGitignore: useGitignore,
        filesToInclude: filesToInclude,
        filesToExclude: filesToExclude,
        maxResults: maxResults,
      ),
    );
  }

  bool _supportsPath(String root) {
    try {
      return File(root).existsSync();
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: 跑测试**

Run: `cd client && flutter test test/services/file_tree/workspace_content_search_service_test.dart`
Expected: PASS。

- [ ] **Step 5: SSH 适配器（app 侧 `Filesystem` → `SearchFileReader`）**

在 `client/lib/services/file_tree/` 下新建 `filesystem_search_reader.dart`：
```dart
import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';

/// Adapts the app's [Filesystem] (e.g. [SftpFilesystem]) to the package's
/// [SearchFileReader] so remote workspaces use the fallback engine.
class FilesystemSearchReader implements SearchFileReader {
  const FilesystemSearchReader(this.fs);

  final Filesystem fs;

  @override
  Future<List<SearchDirEntry>> listDir(String path) async {
    try {
      final entries = await fs.listDir(path);
      return entries
          .map((e) => SearchDirEntry(
                name: e.name,
                isDirectory: e.isDirectory,
                size: e.isFile ? e.size : null,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>?> readLines(String path) async {
    try {
      final text = await fs.readString(path);
      if (text == null) return null;
      if (text.contains('\u0000')) return null; // binary
      return const LineSplitter().convert(text);
    } catch (_) {
      return null;
    }
  }
}
```
（需确认 `FsDirEntry` 有 `size`/`isFile` 字段；若无 `size`，用 `SearchDirEntry.size = null` 并在文档注明 maxFileSize 在 SSH 模式按行数估算或暂不生效——以实际字段为准。）

给 `WorkspaceContentSearchService` 加一个便捷方法：
```dart
  Stream<TpSearchMatch> searchFilesystem(Filesystem fs, String root, String pattern, {...})
      => searchWithReader(FilesystemSearchReader(fs), root, pattern, ...);
```

- [ ] **Step 6: CI 补包测试 + Android 构建验证**

`.github/workflows/client-verify.yml` 的 `verify` job（`flutter analyze` 步骤之后、`flutter test` 步骤之后各加一段；注意 working-directory 默认是 `client`，包步骤用相对路径）：

```yaml
      - name: teampilot_search Rust tests
        working-directory: client/packages/teampilot_search
        run: cargo test --manifest-path rust/Cargo.toml

      - name: teampilot_search Dart tests
        working-directory: client/packages/teampilot_search
        run: flutter test

      - name: teampilot_search analyze
        working-directory: client/packages/teampilot_search
        run: flutter analyze --no-fatal-infos --no-fatal-warnings
```

Android job（matrix `platform: android`）在 rust-toolchain 步骤后追加：
```yaml
      - name: Install cargo-ndk for teampilot_search android cross-build
        run: cargo install cargo-ndk --locked
```
然后本地验证：`flutter build apk --debug`（Android 交叉编译 Rust cdylib 需要 NDK + cargo-ndk；若 `native_toolchain_rust` 自动处理则此步可省，以实际构建报错为准——若报 "cargo-ndk not found" 才需要安装，若已能构建则删掉该步骤）。

- [ ] **Step 7: 本地全量验证**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
cd client/packages/teampilot_search && cargo test --manifest-path rust/Cargo.toml && flutter test
```
Expected: 全部通过（Android 交叉编译在 CI 验证，本地可选）。

- [ ] **Step 8: 提交**

```bash
git add client/pubspec.yaml client/pubspec.lock client/lib/services/file_tree client/test/services/file_tree .github/workflows/client-verify.yml
git commit -m "feat(workspace): wire teampilot_search content search service + CI"
```

---

## Self-Review 记录

- **Spec 覆盖**：包结构 ✓（Task 1）；Rust 引擎 + ignore/grep-searcher + 取消/预算 ✓（Task 2）；FFI ABI 与错误码 ✓（Task 1 头文件 + Task 2）；Dart API/Stream/取消 ✓（Task 3）；integration 标记流式用例 ✓（Task 3 Step 7，spec 测试一节）；fallback 引擎 + SearchFileReader ✓（Task 4）；app 接线 + SSH 适配 ✓（Task 5）；CI ✓（Task 5）；WSL 透传 ✓（Task 3 `supportsPath` 探针，无特殊代码，符合 spec 决策 2）。
- **占位扫描**：无 TBD/TODO；Task 3 Step 4 的 `stringsBufToString`/`ffiPointerToString` 占位在 Step 5 明确替换（含最终代码）。
- **类型一致性**：`TpSearchOptions`/`TpSearchMatch`/`TpSearchEngine`/`SearchFileReader`/`fallbackSearch` 在各任务间签名一致；FFI 符号名与 C 头一致；错误码常量在 Rust（`ERR_*`）与 Dart（`_kErr*`）两侧同值；`WorkspaceContentSearchService` 非 const 构造 + 非 const `_engine` 字段（const 构造会要求字段 const 初始化，编译不过）。
