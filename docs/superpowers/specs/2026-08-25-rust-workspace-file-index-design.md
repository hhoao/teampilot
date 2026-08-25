# 工作区文件名索引：Rust walk + fuzzy（teampilot_search）— 设计

Date: 2026-08-25
Status: Approved (brainstorming)

## 问题

工作区搜索对话框 / compose `@` 文件提及时，文件名索引（`WorkspaceFileIndex`）在**首次打开**时用纯 Dart BFS 逐目录 `listDir` 建表，大仓体感明显偏慢。索引就绪后，每次按键仍在 UI isolate 上对**全部**条目跑 `fuzzyMatchScore` 再排序，文件一多也会顿。

内容搜索已有 `teampilot_search`（`ignore::WalkBuilder` + ripgrep 栈）。原设计 v1 明确「文件名搜索改走 Rust」不在范围；本设计补上这一块。

## 目标

- **本地可读路径**：索引 build 与 fuzzy/contains **query 都在 Rust**；Dart 只持 handle、管新鲜度、回传 top-N。
- **默认尊重 `.gitignore`**（与内容搜索本地引擎一致）；跳过 hidden。
- **SSH / 进程不可直读路径**：保持现有纯 Dart 索引（固定目录黑名单，无 gitignore）。
- 对外：`WorkspaceSearchIndexes` / 对话框 / compose 调用面尽量不变。

## 非目标

- FsWatcher 增量更新（仍用 root mtime + TTL 全量重建）
- 工作区打开即预热索引（可后续加；本轮靠更快的 Rust build）
- 内容搜索与文件索引合成同一 handle
- 发布独立 pub 包变更说明之外的重构

## 决策摘要

| 项 | 选择 |
|----|------|
| 架构 | 持久 `TpFileIndex` 句柄：Rust 常驻路径表 + 进程内 query |
| 忽略规则（本地） | `use_gitignore` 默认 **true** + `hidden(true)` |
| 忽略规则（远程 Dart） | 现有 `workspaceFileIgnoredDirNames` / 跳过 `.` 前缀 |
| Fuzzy | 将现有 Dart `fuzzyMatchScore` 启发式迁到 Rust，测试对拍 |
| Query 模式 | `fuzzy`（对话框）、`contains`（compose 文件名）+ `query_dirs`（compose 目录） |
| 失败回退 | 本地 Rust build 失败 → 回退 Dart 索引，搜索不整挂 |

否决方案：每次按键整树 walk（无索引）；Rust 只 walk、全量路径拷回 Dart 再 fuzzy（按键收益不足且 FFI 过重）。

## 架构与数据流

```
对话框 / @-mention
  → WorkspaceSearchIndexes.fileIndexFor(root)
  → WorkspaceFileIndex.ensureFresh() / query() / queryDirectories()
       ├─ 本地可读路径 → TpFileIndex (teampilot_search Rust)
       │     build: ignore::WalkBuilder（gitignore 默认开、hidden）
       │     query: Rust fuzzy | contains → top-N only
       └─ SSH / 不可读 → 现有 Dart BFS 索引（固定黑名单）
```

新鲜度仍在 Dart 侧（与今天一致）：

- root `mtime` 变化 → rebuild
- mtime 不可用 → `WorkspaceFileIndex.maxStale`（5 分钟）TTL
- 并发 `ensureFresh` 共用 in-flight Future

内容搜索（`TpSearchEngine` / `ContentSearchRunner`）API 与行为不变；文件索引为包内**并列**能力。

## 组件与 ABI

### Rust / C shim（`teampilot_search`）

建议符号（命名可在实现时微调，语义固定）：

| 符号 | 作用 |
|------|------|
| `tp_file_index_new(config, &handle)` | 创建。`config`：`root`、`use_gitignore`（默认 true）、`max_entries` |
| `tp_file_index_build` + 可选分块 progress | 并行 walk，路径（及目录相对路径）常驻 Rust；超 `max_entries` 截断并标记 truncated |
| `tp_file_index_query(handle, query, mode, limit, chunk)` | `mode`: fuzzy \| contains；写入 top-N：`path` / `relative_path` / `name` |
| `tp_file_index_query_dirs(handle, query, limit, chunk)` | 相对目录路径，basename 大小写不敏感 contains（compose `@`） |
| `tp_file_index_cancel` / `tp_file_index_free` | 取消进行中的 build；释放 |

Walk 实现复用内容搜索同款 `ignore::WalkBuilder` 配置习惯（`git_global` / `git_exclude` 关闭以保持确定性；`hidden(true)`）。

Fuzzy 启发式对齐现有 Dart（`workspace_file_index.dart`）：

- 子序列匹配；连续 run 加分
- 路径段 / `_` / `-` / `.` 边界与 camelCase 边界加分
- 更早位置、basename 前缀 / contains、更短相对路径更优

### Dart 包 API

- `TpFileIndex`：与 `TpSearchEngine` 并列；`ensureBuilt` / `query` / `queryDirectories` / `cancel` / dispose。
- `supportsPath` 语义与内容搜索一致（本机可读，含 Windows `\\wsl$\...`）。

### App 接线

- `WorkspaceFileIndex`：
  - 本地：委托 `TpFileIndex`；`query` / `queryDirectories` 转发。
  - 远程或 Rust 不可用/build 失败：现有 Dart `_build` + 内存 `query`。
- 对话框继续用 expanded limit 语义，但 **Rust 只计算并返回 cap 内结果**，不再在 Dart 扫全表排序。
- Dart 可保留 `fuzzyMatchScore` 纯函数供对拍测试与 Dart fallback；不以 UI 热路径依赖它（本地）。

## 错误处理

| 情形 | 行为 |
|------|------|
| root 不存在 / 不可读 | `new`/`build` 失败 → 回退 Dart 索引（或等价空结果路径）；不导致搜索 UI 整体不可用 |
| 单目录不可读 | 跳过（同内容搜索） |
| 超过 `max_entries` | 截断索引并标记 truncated；query 仍可用 |
| build 未完成时 query | 等待 build；对话框保持 Searching… |
| SSH / `SftpFilesystem` | 从不创建 Rust file index |
| 无效 UTF-8 路径 | 跳过或 lossy 转字符串；不中止整个 build |

## 测试

- **Rust `cargo test`**：gitignore 排除、hidden 跳过、fuzzy 向量对拍、contains、query_dirs、max_entries 截断、cancel。
- **Dart 包测**：本地 fixture 上 `TpFileIndex` 端到端；与内容搜索包测试风格一致。
- **App**：`WorkspaceFileIndex` 在本地 vs 假 SFTP 下选对后端；现有 `workspace_file_index_test` / 对话框 / compose 相关测试更新或补后端分支。
- **对拍**：同一批 `(relativePath, query)`，Dart `fuzzyMatchScore` 与 Rust 分数一致，或至少 **排序稳定一致**（实现时选定一种并写死在测试里；优先分数一致）。

## 实现分期建议

1. Rust walk + 路径常驻 + Dart `TpFileIndex` build 接线（先 contains，验证冷启动）
2. Rust fuzzy + query / query_dirs；对拍测试
3. `WorkspaceFileIndex` 后端分流 + 失败回退
4. 对话框 / compose 回归；文档与 CHANGELOG（若包有）

## 相关文档

- [2026-08-12-teampilot-search-rust-engine-design.md](./2026-08-12-teampilot-search-rust-engine-design.md)（内容搜索；v1 曾排除文件名搜索）
- 实现入口：`client/packages/teampilot_search/`、`client/lib/services/file_tree/workspace_file_index.dart`
