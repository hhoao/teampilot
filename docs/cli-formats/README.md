# CLI 格式参考库

**日期:** 2026-08-12
**状态:** 建立中（每完成一页回填矩阵，Task 6 校验无残留）

各 CLI 原生 transcript 的消息格式与工具调用格式参考。统一解析体系设计见
[docs/superpowers/specs/2026-08-12-cli-parsing-unification-design.md](../superpowers/specs/2026-08-12-cli-parsing-unification-design.md)；
分层约定见 [docs/tool-call-parsing-convention.md](../tool-call-parsing-convention.md)。

## 总览矩阵

| CLI | transcript 位置 | 文件格式 | 消息 schema 页 | 解析入口 | 增量能力 | 状态 |
|-----|----------------|---------|---------------|---------|---------|------|
| claude | `{config}/projects/{bucket}/{taskId}.jsonl` | JSONL | [claude.md](claude.md) | `services/cli/claude/capabilities/history/ai_transcript.dart` | 有（lineAppend 非空；tailFallbackPrefix=`claude`） | 完成 |
| codex | `$CODEX_HOME/sessions/**/rollout-*.jsonl` | JSONL | [codex.md](codex.md) | `services/cli/codex/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| opencode | `$XDG_DATA_HOME/opencode/opencode.db` | SQLite(WAL) | [opencode.md](opencode.md) | `services/cli/opencode/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| cursor | `{configDir}/projects/{project}/agent-transcripts/…` | JSONL | [cursor.md](cursor.md) | `services/cli/cursor/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| flashskyai | `~/.flashskyai/projects/{bucket}/{id}.jsonl` | JSONL | [flashskyai.md](flashskyai.md) | `services/cli/flashskyai/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |

> 注：位置列来自 adapter 源码注释，各 CLI 页面需核实并给出实测结论；
> 「增量能力」= 该 CLI 的 `AiHistoryCapability.lineAppend` 是否非空（opencode 走 sqlite 增量 locate，需在页面中说明机制）。

## 新增 CLI

见 [adding-a-cli.md](adding-a-cli.md)（随子项目 4 落地）。
