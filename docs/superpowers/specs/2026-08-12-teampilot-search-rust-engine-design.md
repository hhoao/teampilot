# 工作区内容搜索：Rust FFI 引擎库（teampilot_search）— 设计

Date: 2026-08-12
Status: Draft (brainstorming, rev 1)

## 问题

内置 IDE 目前只有**文件名**搜索（`client/lib/services/file_tree/workspace_file_search.dart`，BFS 匹配 basename），没有 VS Code 式的**文件内容**搜索（Ctrl+Shift+F：正则/字面量、gitignore、glob 排除、按文件/行/范围展示结果）。

### 性能基线（本机实测，同一源码树 ~93–235 MB 可搜文本）

| 方案 | 吞吐 | 全量扫一遍 |
|------|------|-----------|
| 纯 Dart 单线程 RegExp | ~25–50 MB/s | 2–5 s |
| 纯 Dart 22 isolates 并行 | ~65–130 MB/s | 0.5–1.5 s |
| 系统 ripgrep（22 核） | ~1 GB/s | 0.09 s |

### 候选方案评估

- **pub.dev 无 grep 类库**：搜 `ripgrep` / `grep` / `search in files` 无可用绑定；Dart 生态没有全文搜索实现。
- **纯 Dart 自研**：可行，但慢 rg 一个数量级；需自己做 gitignore、glob、并行、取消。
- **系统 rg 二进制 shell 出去**：只对本地 native 成立；SSH 要远程 exec，WSL 要 `wsl rg`，还有二进制分发问题。
- **Rust FFI 库（本设计）**：ripgrep 本身就是 crate 栈（`grep-searcher` / `grep-regex` / `grep-matcher` / `ignore` / `memchr`），编译成 cdylib 经 FFI 调用，性能达 rg 级别，且**统一获得 gitignore/glob 语义**。仓库已有两条先例：`teampilot_tree_sitter`（ffi + ffigen + code_assets hooks，in-repo package）与 `flutter_alacritty`（Rust crate + cargokit，submodule repo）。

## 决策

1. **仓库内独立 package**：`client/packages/teampilot_search`，遵循 `teampilot_tree_sitter` 模式（`ffi` + `ffigen` + `hooks` + `native_toolchain_rust` 的 `RustBuilder`）。包不依赖 app 任何类，**后续可直接演进为可发布的 pub 包**。
2. **引擎覆盖**：Rust 引擎用于本地 native（Linux/macOS/Windows）；Windows + WSL 后端经 `\\wsl$\<distro>\...` UNC 路径直接本地读（FFI 只认"本机进程可读的路径"，无需特殊代码，实测确认性能即可）；SSH / Android（始终 SSH）走包内纯 Dart fallback 引擎。
3. **Cargo 依赖**：构建时从 crates.io 拉取，提交 `Cargo.lock` 锁版本（flutter_alacritty 同款），不 vendoring（`grep`/`ignore` 依赖树提交进仓库体积不可接受）。

## 包结构

```
client/packages/teampilot_search/
├── pubspec.yaml            # deps: ffi, code_assets, hooks, logging, native_toolchain_rust; dev: ffigen, test
├── hook/build.dart         # RustBuilder(assetName: 'lib/teampilot_search_bindings_generated.dart')
├── ffigen.yaml             # 绑 rust/include/teampilot_search.h 的 extern "C" shim
├── lib/
│   ├── teampilot_search.dart          # 公共 API：search() Stream、模型、选项
│   ├── teampilot_search_bindings_generated.dart  # ffigen 产物
│   ├── rust_engine.dart               # FFI 封装：句柄生命周期 + 分块拉取 + 取消
│   └── fallback/
│       ├── fallback_search_engine.dart  # 纯 Dart 引擎（search_reader 抽象）
│       └── search_reader.dart           # 最小可插拔文件读取接口
├── rust/
│   ├── Cargo.toml          # crate-type = ["staticlib", "cdylib"]；deps: grep, ignore, memchr
│   ├── Cargo.lock          # 提交
│   ├── rust-toolchain.toml # 固定版本号（reproducible builds），targets 仅 linux/mac/windows 桌面
│   ├── include/teampilot_search.h   # FFI shim 的 C 声明头（ffigen 入口）
│   └── src/
│       ├── ffi.rs          # #[no_mangle] extern "C" shim：句柄状态机 + 预算分块
│       └── engine.rs       # ignore::WalkBuilder + grep-searcher 组装、结果打包
└── test/                   # Dart 侧测试（fixture 树）；rust/ 内 cargo test
```

构建链路与 `teampilot_tree_sitter` 一致：`hook/build.dart` 由 pub 构建时执行，`RustBuilder` 编译 cdylib 为 native asset，asset id 与 ffigen 生成的 bindings 文件名一致，`@Native` externals 免显式 asset 解析。CI 已有 `dtolnay/rust-toolchain@stable`（flutter_alacritty 在用），本包加对应步骤即可。

## FFI ABI（v1 最小面）

```c
typedef struct TpSearchHandle TpSearchHandle;

// 配置 + 创建搜索句柄。返回 0 成功；-1 无效正则；-2 路径不可读。
int32_t tp_search_new(const TpSearchConfig* config, TpSearchHandle** out);
// 同步做一块工作（预算见下），把结果写入 chunk 缓冲区。
// 返回 0 有更多工作；1 搜索完成；2 已取消；负数为错误码。
int32_t tp_search_next(TpSearchHandle* h, TpSearchChunk* chunk);
// 置原子取消标志，next() 在块边界返回 2。
void tp_search_cancel(TpSearchHandle* h);
void tp_search_free(TpSearchHandle* h);
```

`TpSearchConfig`：root 路径（UTF-8）、pattern（字面量或正则）、caseSensitive、smartCase、filesToInclude（glob 列表）、filesToExclude（glob 列表）、useGitignore、maxFileSize、maxResults。

`TpSearchChunk`：一批 `TpSearchMatch`（定长数组 + 数量 + 是否已达 maxResults 截断标记）。`TpSearchMatch{ path, relativePath, lineNumber(1-based), lineText, matchStart, matchEnd }`——`matchStart/End` 为**行内 UTF-8 字节偏移**，Dart 侧换算成字符偏移用于编辑器高亮/跳转（对齐 re-editor 的文本模型）。

**内存约定**：chunk 内的字符串由 Rust 分配，通过 `tp_search_free` 释放整块；或 Rust 写入 Dart 传入的预分配缓冲区（大小由 `TpSearchConfig.maxChunkBytes` 控制，默认 64 KB）——v1 采用**预分配缓冲区**方案，避免跨 FFI 的分配器配对问题。

## 取消与预算（chunk 模型）

- Rust 在 `ignore::WalkBuilder` 上并行遍历 + `grep-searcher`（`SearcherBuilder`，多线程）。搜索结果先进**内部队列**（有界，如 4096 条），`tp_search_next` 从队列取一批，队列空时再做一块工作（约 10–50 ms 或扫完 N 个文件），保证每次 FFI 调用不长期阻塞，Dart 侧 await 块之间让出事件循环。
- 取消：`tp_search_cancel` 置 `AtomicBool`，遍历/搜索循环在块边界检查，`tp_search_next` 返回 2；Dart 侧 Stream 随之 `done`。
- 同时**在 Dart 侧**：`search()` 返回 `Stream<TpSearchMatch>` + `cancel()`；消费方可以只取消 Stream 订阅，引擎随后被 `tp_search_cancel` 回收。

## Dart API

```dart
class TpSearchOptions {
  final String pattern;                 // 字面量或正则（isRegex 决定）
  final bool isRegex, caseSensitive, smartCase, useGitignore;
  final List<String> filesToInclude, filesToExclude; // glob，VS Code 语义
  final int? maxResults, maxFileSize;   // 默认 2000 / 10 MB（对齐 VS Code）
}

class TpSearchMatch { path, relativePath, lineNumber, lineText, matchStartChar, matchEndChar }

abstract interface class SearchFileReader {
  /// 读取 [path] 的全部文本行（含行分隔符），供 fallback 引擎逐行匹配。
  Future<List<String>> readLines(String path);
}

class TpSearchEngine {
  bool get supportsPath(String path);                 // 本地可读路径 → true（Rust）
  Stream<TpSearchMatch> search(String root, TpSearchOptions options); // Rust 引擎
  Stream<TpSearchMatch> searchFallback(SearchFileReader reader, String root, TpSearchOptions options);
  void cancel();
}
```

- **后端选择不在包内**：包只提供 `supportsPath` 探针与两套引擎；app 侧（`client/lib/services/file_tree/` 附近）按 Workspace 的 `Filesystem` 类型接线——`LocalFilesystem` → Rust；Windows 上 `WslFilesystem` → Rust（路径透传）；`SftpFilesystem` → fallback（app 把 Sftp 读文件适配成 `SearchFileReader`）。
- 正则解析失败在 **Dart 侧预校验**（`RegExp` try），错误作为 Stream 的 error 事件，不打日志不上报。

## 错误处理

| 情形 | 行为 |
|------|------|
| 无效正则 | Dart 预校验 → Stream error（用户可见，l10n） |
| root 不存在/不可读 | `tp_search_new` 返回 -2 → Stream error |
| 单个文件不可读/损坏编码 | 跳过（rg 语义），不计错误 |
| 块内存不足 | `maxChunkBytes` 扩大或丢弃超长单行（>1 MB 的行跳过匹配，仅保留行号跳转） |
| 搜索中途异常 | `tp_search_next` 负错误码 → Stream error + `tp_search_free` |

## 测试

- **Rust**：`cargo test` —— fixture 目录（嵌套、隐藏文件、`.gitignore`、大小写、多行、二进制、大行），验证 WalkBuilder 语义与 chunk 预算/取消。
- **Dart 单元**：`flutter test` —— Rust 引擎（真实 FFI，desktop 上跑）+ fallback 引擎（注入 `SearchFileReader` 假实现，测全部分支）；fixture 树用 `setUpTestAppStorage` 无关的临时目录。
- **集成**：包内一个 `@Tags(['integration'])` 用例验证 Stream 语义（首个结果延迟、取消、截断标记）。
- CI：`client-verify.yml` 在现有 rust-toolchain 步骤基础上，包目录加 `cargo test`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 覆盖新包。

## 不在 v1 范围

- 发布 pub 包（包结构已为此准备，后续补 CHANGELOG/license/example 即可）
- 文件变更实时更新（后续可加 `watcher`/`file` 通知）
- 文件名搜索改走 Rust（保持现有纯 Dart 实现）
- WSL 在非 Windows 平台（无此场景）
