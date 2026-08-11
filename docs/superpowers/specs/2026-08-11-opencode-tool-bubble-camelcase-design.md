# opencode 工具气泡适配设计（camelCase filePath）

**日期:** 2026-08-11
**状态:** 已批准（待实现）

## 背景

opencode（1.18.4）的 tool call 参数使用 **camelCase** key：`edit`（`filePath` / `oldString` / `newString`）、`write`（`filePath` / `content`）、`read`（`filePath` / `offset` / `limit`）。

`SharedToolCallResolvers`（`client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`）的 pathKeys 只有 snake_case 变体（`file_path` / `path` / `file` / `target_file`），`oldString` / `newString` / `content` 恰好已覆盖。因此 opencode 的 `edit` / `write` / `read` 工具调用解析不到文件路径：

- `edit` → 不渲染编辑卡片（diff hunk）
- `write` → 不渲染写文件卡片
- `read` → 不生成可点击文件链接

`bash`（`command` key）与 `task`（subagent，`builtin_ai_history_capabilities.dart` 已含 `task`）不受影响。

## 方案（已批准：方案 B — opencode 独立配置）

遵循 [docs/tool-call-parsing-convention.md](../../tool-call-parsing-convention.md) 的 CLI 差异化约定：共享层不因 opencode 变宽，opencode 在自身配置层追加 camelCase key。

### 1. `shared_tool_call_resolvers.dart` — 暴露共享常量

将 `_strReplaceCodec` / `_writeCodec` / `_unifiedDiffCodec` / `_fileRules` / `_shellToolNames` 内部使用的 key 列表与 toolName 集合提取为 **public static const**，供 per-CLI 配置复用：

- `editToolNames`、`editPathKeys`、`editOldStringKeys`、`editNewStringKeys`、`editStartLineKeys`
- `writeToolNames`、`writePathKeys`、`writeContentKeys`
- `diffToolNames`、`diffPatchKeys`（复用 `editPathKeys` 作路径 key）
- `fileReadToolNames`、`fileWriteToolNames`、`fileEditToolNames`
- `shellToolNames`

`SharedToolCallResolvers` 自身行为不变（纯提取，内部引用同名常量）。

### 2. `opencode_tool_call_resolvers.dart` — opencode 专属配置

`OpencodeToolCallResolvers` 由 `extends SharedToolCallResolvers` 改为 `implements ToolCallResolversCapability`：

- 各 pathKeys = 共享常量 + `'filePath'`（追加而非替换，旧 snake_case 会话仍兼容）
- `editResolver`：strReplace codec（toolNames = `editToolNames`）、write codec、unifiedDiff codec
- `fileResolver`：三条 rule（read 保留 `useOffsetLimit: true`，opencode 的 `offset` / `limit` 数字 key 已兼容）
- `shellResolver` / `categoryResolver`：直接复用共享配置

## 测试

`client/test/` 新增 opencode tool call resolver 单测：

- `edit`（`filePath` / `oldString` / `newString`）→ `AiEditToolTarget` hunk 含 remove/add 行
- `write`（`filePath` / `content`）→ write hunk
- `read`（`filePath` + `offset` / `limit`）→ `AiToolFileTarget` 含行范围
- `bash`（`command`）→ shell target 不受影响
- snake_case（`file_path`）→ 仍可解析（向后兼容）

## 验证

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```
