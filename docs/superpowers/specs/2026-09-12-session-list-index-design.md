# Session 列表索引（SSH home 读路径）

- 日期：2026-09-12
- 状态：已审阅（对话确认：home 上派生行索引，手机不落本地缓存）
- 目标：手机经 SSH 打开一个 session 时，不要先把同工作区每一个 `session.json` 读完；侧栏只读一份行索引。

## 背景

手机 SSH home 点开会话要等很久才出聊天。日志：

- `readManifest ... indexOnly=false listMs=15–18s sessions=20–27`
- `loadSessionsForWorkspace ... 904 sessions +23176ms`

根因不是聊天 JSONL，而是 **列表和打开共用「读完全仓 `session.json`」**：

1. `session.json` 是会话文档（标题、归档、成员、folders、CLI）。磁盘上 **没有** 列表专用摘要。
2. `workspaces-index.json` 只存 session **id**。侧栏还要 `display` / 时间 / archived / pinned，于是 `ensureSessionsForWorkspace` 把整仓文档灌进 `ChatCubit.state.sessions`。
3. 打开聊天、深链 `await` 这个全有或全无标志，所以点一条也要等 903 个无关文件。
4. 索引缺失/过期时 `loadWorkspacesIndex` 用 `indexOnly: false` 再扫一遍 `session.json`，只为 `createdAt` 排序。
5. 桌面走 `LocalFilesystem` 同步快路径，感觉不到；手机每文件一次 SFTP。

不在手机上做会话镜像。派生索引写在 **home 同一棵树**，变异时更新，和现有 `workspaces-index.json` 同一模式。

## 目标与非目标

### 目标

1. 进工作区画侧栏：读 **一个** `sessions-index.json`（加一次 `listDir` 对账），不读 N 个 `session.json`。
2. 点开一个 session：再读 **那一个** `session.json`，然后才绑历史 / 启动。
3. `loadWorkspacesIndex` 重建与过期校验只用目录名（`indexOnly: true`），禁止为排序去读 `session.json`。
4. 索引与 `session.json` 同住 home；手机不落会话本地缓存。
5. 桌面 UX 不变；clone / automation 等仍可按需读完整文档。

### 非目标

- 不修历史 `page-first miss → full parse`（第二刀）。
- 不做 Android 本地会话镜像、不做 Event Transport、不改 SFTP 实现。
- 不把 `loadSessions()` / clone / automation 改成「永远不读文档」（它们本来就要完整 `AppSession`）。
- 不新增用户可见文案。

## 存储

路径：`workspace/workspaces/{workspaceId}/sessions-index.json`

```json
{
  "version": 1,
  "updatedAt": 1710000000000,
  "sessions": [
    {
      "sessionId": "...",
      "display": "...",
      "purpose": "normal",
      "workflowId": "",
      "sessionTeam": "",
      "createdAt": 1,
      "updatedAt": 2,
      "archived": false,
      "pinned": false,
      "sortOrder": 0
    }
  ]
}
```

- `session.json` 仍是文档源。索引是派生快照。
- 行字段 = 侧栏 / 过滤所需：`SessionRowContent` + pinned + archived + sortOrder + `sessionTeam` + `purpose`/`workflowId`。
- **不含** folders、members、CLI、continueOverrides。
- 工作区删除整目录即带走索引。版本不等于 `1` 视为缺失，触发重建。

`WorkspaceLayout.sessionsIndexFile(workspaceId)` 提供路径。

## 读写契约

### 模型

`SessionListEntry`：上表字段；`fromJson` / `toJson`；`fromSession(AppSession)`；`toListSession(workspaceId)` → 仅填行字段的 `AppSession`（folders/members 为空）。列表行 **不是** 可启动文档。

### `SessionListIndexStore`

对单个工作区，锁内读写（按文件路径一把 `Lock`，仿 `WorkspaceIndexStore`）：

- `Future<List<SessionListEntry>?> tryRead()`
- `Future<void> writeAll(List<SessionListEntry> entries)`
- `Future<void> upsert(SessionListEntry entry)`
- `Future<void> remove(String sessionId)`

传输失败（`isStorageTransportFailure`）上抛；坏 JSON / 版本不对返回 `null`。

### 仓库

- `loadSessionListForWorkspace(workspaceId)`：
  1. `tryRead` 索引；
  2. `listSessionDirectoryIds`（一次 `listDir`）与索引 id 集合比较；
  3. 一致则 `toListSession`；
  4. 缺失或 id 不一致：用现有 `listSessionJsonMapsForWorkspace` **重建一次**，`writeAll`，再返回列表行。
- `loadSession(workspaceId, sessionId)`：读那一个 `session.json`（现有 `_readSession` 公开化）。`findById` 仍可全库找，不作为打开热路径。
- `loadSessionsForWorkspace` / `loadSessions`：**保持读完整文档**（clone、automation、测试）。Chat 侧栏与打开 **不再** 走这两条。
- `loadWorkspacesIndex` 缺失重建与 `_revalidateWorkspacesIndexSnapshot` 过期：一律 `_loadWorkspaces(indexOnly: true)`。`workspace.sessionIds` 用目录名；顺序以索引里已有顺序为准，没有则目录序。不要为 createdAt 读 `session.json`。
- 所有写 `session.json` 的变异在 `_writeSession` 之后 `upsert(SessionListEntry.fromSession(session))`。`deleteSession` 调 `remove`。`createSession` 走 `_writeSession` 即可覆盖。

## Chat 层

`SessionDataStore` / `ChatCubit`：

- `ensureSessionsForWorkspace` 改为 `loadSessionListForWorkspace`。灌进 `state.sessions` 的是列表行。已 `hydrate` 过的完整文档 **不被** 列表行覆盖（只 `copyWith` 行字段：display、archived、pinned、sortOrder、updatedAt、sessionTeam、purpose、workflowId）。
- 新方法 `hydrateSessionDocument(workspaceId, sessionId) → AppSession?`：已是完整文档则返回内存对象；否则 `loadSession`，替换内存项，记入 `_documentSessionIds`。
- 完整文档判定：**不要** 用 `folders.isEmpty` 启发式。用 `_documentSessionIds`（`createSession` / `loadWorkspaceData` 写入的对象一开始就是完整文档）。
- `ChatCubit.requestOpenSession`：打开前 `hydrateSessionDocument`，用返回值 `request.withSession(...)`。侧栏点行、深链、`_sessionById` 都经过这里或显式 hydrate。
- 深链 `_applySessionFromRoute`：不要 `await ensureSessionsForWorkspace` 才开 tab。`unawaited` 列表 hydrate；`await hydrateSessionDocument` 后 `openWorkspaceSessionTab`。
- 启动 `prefetchSessionsForEntryWorkspace` 继续 `ensureSessionsForWorkspace`，此时应变便宜（一份索引）。

`ChatCubit.ensureSession(TeamProfile)` 是启动会话，**不要** 复用这个名字。

## 失效

| 情况 | 行为 |
|---|---|
| 变异经 `SessionRepository` | 增量 upsert/remove，热路径不重建 |
| 索引缺失 / version 不对 | 该工作区重建一次（N 次读，只这一次） |
| `listDir` id 与索引不一致（手改磁盘、半次写入） | 该工作区重建一次 |
| 工作区集合与 `workspaces-index` 不一致 | 只 `listDir` 工作区 + manifest，不读 session.json |
| 手机杀进程 | 无设备缓存；下次读 home 上的索引 |

## 测试要点

- 种 80+ 个 `session.json`：`loadWorkspacesIndex` 在无快照时 **不** `readString` 任何 `session.json`（包装 `Filesystem` 计数）。
- 种 80+ 个文件并写好 `sessions-index.json`：`loadSessionListForWorkspace` 不读 `session.json`；返回行字段。
- 删掉索引或让目录多一个 id：重建后索引文件存在且 id 对齐。
- `createSession` / `touchSession` / `setSessionArchived` / `deleteSession` 后索引文件与文档一致。
- `ensureSessionsForWorkspace` 后 `state.sessions` 有行；`hydrateSessionDocument` 才带上 folders；再次列表 hydrate 不丢掉 folders。
- `requestOpenSession` 在列表行上打开会先变成完整文档（cubit 测试，不启 PTY）。

## 文档

更新 `docs/workspace-storage-layout.md` 工作区目录树，加上 `sessions-index.json` 一行说明：派生侧栏快照，源仍是 `session.json`。
