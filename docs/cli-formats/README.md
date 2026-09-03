# CLI 格式参考库

**日期:** 2026-08-12
**状态:** 完成（5 页全部落地，Task 7 收尾校验通过）

各 CLI 原生 transcript 的消息格式与工具调用格式参考。统一解析体系设计见
[docs/superpowers/specs/2026-08-12-cli-parsing-unification-design.md](../superpowers/specs/2026-08-12-cli-parsing-unification-design.md)；
分层约定见 [docs/tool-call-parsing-convention.md](../tool-call-parsing-convention.md)。

## 总览矩阵

| CLI | transcript 位置 | 文件格式 | 消息 schema 页 | 解析入口 | 增量能力 | 状态 |
|-----|----------------|---------|---------------|---------|---------|------|
| claude | `{config}/projects/{bucket}/{taskId}.jsonl` | JSONL | [claude.md](claude.md) | `services/cli/claude/capabilities/history/ai_transcript.dart` | 有（lineAppend 非空；tailFallbackPrefix=`claude`） | 完成 |
| codex | `$CODEX_HOME/sessions/**/rollout-*.jsonl`（实测日期分层目录 `sessions/YYYY/MM/DD/`） | JSONL | [codex.md](codex.md) | `services/cli/codex/capabilities/history/ai_transcript.dart` | 有（lineAppend 非空；tailFallbackPrefix=`codex`） | 完成 |
| opencode | `$XDG_DATA_HOME/opencode/opencode.db`（实测 `~/.local/share/opencode/opencode.db`；TeamPilot 会话为 `{runtime}/opencode/opencode.db`，走 `OPENCODE_DB`） | SQLite(WAL) | [opencode.md](opencode.md) | `services/cli/opencode/capabilities/history/ai_transcript.dart` | 有（`lineAppend=null`；sqlite 增量 locate `id>afterMessageId` + liveCacheToken store 级指纹） | 完成 |
| cursor | `{configDir}/projects/{project}/agent-transcripts/{chatId}/{chatId}.jsonl`（亦支持扁平 `agent-transcripts/{chatId}.jsonl`；configDir = `$CURSOR_CONFIG_DIR`，缺省 `$HOME/.cursor`） | JSONL | [cursor.md](cursor.md) | `services/cli/cursor/capabilities/history/ai_transcript.dart` | 有（lineAppend 非空；tailFallbackPrefix=`cursor`；resolveParentTranscriptPath + path liveCacheToken） | 完成 |
| flashskyai | `~/.flashskyai/projects/{bucket}/{id}.jsonl`（实测 `projects/`；`layoutSegments: ['projects','workspaces']` 双探针，`workspaces` 为旧布局回退） | JSONL | [flashskyai.md](flashskyai.md) | `services/cli/flashskyai/capabilities/history/ai_transcript.dart` | 有（lineAppend 非空，复用 `appendClaudeJsonlEvent`；tailFallbackPrefix=`flashskyai`） | 完成 |

> 注：位置列与各 CLI 页面「Transcript 存储」表语义一致（token 写法以各页定义为准，如 claude/flashskyai 的 `{root}` = CLI config 目录对应的 transcript roots）；
> 「增量能力」= 该 CLI 的 `AiHistoryCapability.lineAppend` 是否非空（opencode 走 sqlite 增量 locate，机制见 [opencode.md](opencode.md)）。
>
> 工具输出**截断回填可行性**（codex 不可行 / opencode 有条件可行已实现）见 [truncation-backfill-audit.md](truncation-backfill-audit.md)；各页「已知陷阱」相应条目已同步结论。

## 外部参考

| 仓库 | 用途 | 引用方式 |
|------|------|---------|
| [asgeirtj/system_prompts_leaks](https://github.com/asgeirtj/system_prompts_leaks)（CC0） | 各 CLI 泄露系统提示中的工具 JSON schema，工具调用覆盖的第四方证据源 | 固定 commit 快照（本库引用 `@93c999115b300a6faac567830b0450a5478800cd`），禁止"最新版"表述 |

工具调用覆盖的四方证据源汇总矩阵与缺口清单见 [tool-layer-coverage.md](tool-layer-coverage.md)（**状态：完成**——5 CLI × 5 类别全部落结论，6 个缺口全部有状态：G-1/G-3/G-4/G-5 已修复、G-2 接受差异、G-6 观察项）。

## 新增 CLI

接入清单（6 个接入点：CliTool 定义 / history capability / tool call resolvers /
注册 / 测试 / 文档）见 [adding-a-cli.md](adding-a-cli.md)。
