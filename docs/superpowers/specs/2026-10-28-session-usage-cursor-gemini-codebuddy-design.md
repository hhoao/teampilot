# Session usage: CodeBuddy, Gemini, and Cursor

## Scope

Adds three usage sources without changing the per-session scanner contract:

- **CodeBuddy Code** — local native JSONL.
- **Gemini CLI** — local session JSON/JSONL.
- **Cursor** — account-level dashboard CSV (manual import + optional sync).

ACP is intentionally not the source. ACP `usage_update` carries only context
`used`/`size` and optional cumulative cost; it does not carry input, output, or
cache splits.

## CodeBuddy

Data: `CODEBUDDY_CONFIG_DIR/projects/**/*.jsonl`.

Assistant records carry `providerData.rawUsage` (fallback
`providerData.usage` / `message.usage`), `providerData.model`, and
`providerData.messageId`. Several JSONL records can share one `rawUsage`, so
the capability dedupes by `messageId` before returning events.

`prompt_tokens` includes cached tokens. The event uses
`UsageInputSemantics.total`; the aggregator subtracts cache once. `credit` is a
CodeBuddy credit amount, not USD, and is not fed into the USD cost engine.

## Gemini

Data: `GEMINI_CONFIG_DIR/tmp/*/chats/session-*.json(l)`.

Completed `type: "gemini"` messages carry `model` and
`tokens.input/cached/output/thoughts`. `input` includes cached tokens, so the
event uses total semantics. `thoughts` are folded into output tokens, matching
Gemini's output-rate billing. Older single-JSON sessions are re-read whole;
JSONL sessions are incremental, with a full re-read when the file was rewritten
so compaction cannot hide history.

## Cursor

Local Cursor IDE/CLI transcripts and `state.vscdb` do not reliably contain
per-request token counts. The implementation therefore consumes Cursor's own
dashboard export:

- Manual: CSV from `cursor.com/dashboard/usage`.
- Sync: `GET https://cursor.com/api/dashboard/export-usage-events-csv?startDate=<ms>&endDate=<ms>&strategy=tokens`
  with the `WorkosCursorSessionToken` cookie derived from a live Cursor OAuth
  token.
- Tokens: `Input (w/o Cache Write)` → input; `Input (w/ Cache Write)` → cache
  write; `Cache Read`; `Output Tokens`.
- `Cost` is kept as reported USD; `Included` / `Free` rows stay unpriced unless
  the user adds a pricing rule.

Auth resolution scans isolated Cursor provider homes first, then global Cursor
auth files, and uses the newest unexpired token. Tokens are never logged.

Storage is separate from `events.jsonl`:

- `usage/cursor_import.json` — imported records + coverage windows + last
  import/sync time.
- The usage page merges these events into the cached event view.
- A sync replaces its own account's rows inside its window; manual rows win over
  the same request id, so a manual export is never silently overwritten.

Sync is manual (footer → Cursor usage → Sync). It is not part of the 10-minute
local sync loop, so a network request never blocks local usage refresh.

## Status bar progress

`SessionUsageProgressBridge` wraps the home-shell status bar. While the
app-level usage sync runs (manual, page-open, resume, or the 10-minute timer),
it starts a `ProgressActivityKind.sessionUsage` activity in
`ProgressActivityCubit`: the status-bar pill shows the percentage, the
activities popover shows scanned sessions/inserted events, and the same row
appears in the notification center. Cancel maps to `SessionUsageCubit.cancelSync`.
The bridge is localized in the widget layer; routine syncs do not write
notification history (`recordHistory: false`).

## Limitations

- Cursor sync requires a live Cursor login and network; it uses an internal
  dashboard endpoint that can change.
- The sync picks one Cursor account (newest valid token). Multiple accounts are
  not merged into one report.
- CodeBuddy/Gemini native file formats are internal and must be treated as
  best-effort parsers.
