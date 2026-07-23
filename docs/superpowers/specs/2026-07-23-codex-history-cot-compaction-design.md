# Codex / History chain-of-thought compaction

## Goal

Stop Codex (and similarly fragmented) History from rendering as a long alternating list of「推理」and「已使用工具」rows. Align the in-memory message model with assistant-ui (one assistant turn = one `AiMessage` with many parts), and default-collapse leading reasoning + tool-call parts into a single「思考过程」block so the visible transcript stays short without losing detail on expand.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product UX | **A+B**: coalesce messages (A) + default-collapsed chain-of-thought presentation (B) |
| Architecture | Shared **coalesce** in `ai_message_core` + Cot grouping in `ai_message_ui` (approach 2) |
| Scope | All CLI History that produces adjacent assistant fragments; not Codex-only UI hacks |
| Cot default | Collapsed; trigger label includes step count |
| Disk / resume | No change to Codex rollout JSONL or CLI protocols |
| Settings | No v1 “hide reasoning” toggle (optional later) |

## Non-goals (v1)

- UI-only cross-bubble fake merge without changing `AiMessage` lists
- Persisting coalesced IR to disk
- Changing seat isolation / live refresh ownership (orthogonal)
- History list virtualization overhaul
- User setting to permanently hide reasoning

## Problem

Codex rollout logs each agent step as separate events (`agent_reasoning` / `response_item.reasoning`, then `function_call`, …). TeamPilot’s Codex adapter maps each event to its own `AiMessage` with a single part. `ai_message_ui` already groups **consecutive** reasoning/tool parts **within one message**, but alternating R→T→R→T never becomes consecutive, so the UI shows one collapsible row per event. assistant-ui expects one assistant message with many parts and can wrap leading R+T as chain-of-thought.

## Product UX

For a turn with many tool steps:

- **Default:** one row `思考过程 · N 步` (collapsed) + final assistant text below.
- **Expanded:** existing reasoning and tool-call widgets inside the Cot (including consecutive reasoningGroup / toolGroup).
- Pure-text assistant turns unchanged (no Cot chrome).
- Turns with only R/T and no text: entire message is one Cot block.

## Architecture

```
CLI adapters (Codex / Claude / …)
  → List<AiMessage>   // may still be one event per message
  → coalesceAdjacentAssistants()   // NEW, shared
  → finalizeAiMessagesForHistory() // existing tool-status normalize
  → AiMessageView / groupMessageParts (Cot-aware)
```

### Data: `coalesceAdjacentAssistants`

- Location: `client/packages/ai_message_core` (called from `finalizeAiMessagesForHistory` or immediately before it from every adapter’s finalize path — prefer **inside** `finalizeAiMessagesForHistory` so no adapter can forget).
- Rule: merge runs of **adjacent `AiRole.assistant`** messages; cut on `user` / `system`.
- Concatenate `parts` in order; keep the **first** message’s `id` and `createdAt` (and status if present).
- Do not invent merges across user turns.
- Tool results continue to use `applyAiToolResult` (call_id match); coalesce must not break that — apply results before or after coalesce as long as parts retain `toolCallId` (today Codex applies during parse, before finalize → OK).

### Presentation: chain-of-thought grouping

- Extend `groupMessageParts` in `ai_message_ui` with an `AiRenderChainOfThought` node (assistant-ui `group-chainOfThought` analogue). Also extend `AiPartRegistry.buildNode` with a Cot branch / optional `chainOfThoughtBuilder` hook (same pattern as tool/reasoning groups).
- **Algorithm (single left-to-right scan):** walk `parts`; whenever the current part is R or T, open a Cot and consume the maximal contiguous R|T run; when a non–R/T part appears (typically `AiTextPart`), emit it via the existing consecutive reasoning/tool/text grouping path, then continue — so `R→T→text→R→T→text` yields Cot, text, Cot, text.
- Default widget: collapsed trigger; `N` = count of reasoning + tool-call parts inside (empty reasoning already skipped by adapters).
- **Expand semantics:** opening the Cot must reveal reasoning text and tool args/results **without a second click**. Prefer rendering dense / force-open inners inside an expanded Cot (do not nest another default-collapsed `AiReasoningPartView` / tool chrome that hides the payload again). Collapsed Cot remains a single row.
- Strings: add host-injectable copy on `AiMessageStrings` (e.g. `thinkingProcess` / `formatThinkingProcessSteps`); TeamPilot wires l10n.

### Codex adapter

- Keep dual-write reasoning dedupe and event parsing as today.
- Rely on shared coalesce for turn compaction (no requirement to rewrite append-into-open-assistant in v1, though that remains a compatible optimization later).
- Update fixtures/tests so a R→T→R→T→text rollout yields **one** assistant message with ordered parts.

## Error handling / stability

- Coalesce is pure and total: malformed empty part lists still merge structurally; UI skips empty Cot.
- softReload re-parses full transcript → same coalesce path as cold load.
- Pending / seed / sticky local user messages stay separate `user` rows and never enter assistant coalesce.
- Prefer stable first `id` to reduce softReload / tip-hold churn; content identity paths should not require per-event assistant ids after merge.

## Testing

| Case | Expectation |
|------|-------------|
| Coalesce R/T fragment assistants between users | One assistant; parts order preserved; first id kept |
| User message between assistants | No cross-turn merge |
| Codex fixture R→T→R→T→text | Single assistant after parse+finalize |
| Dual-write reasoning | Still one reasoning part (adapter dedupe) |
| Cot grouping | Leading R/T → one Cot node; trailing text outside |
| No R/T | No Cot node |
| Cot widget | Default collapsed; expand shows tools/reasoning |

Prefer unit tests in `ai_message_core` and `ai_message_ui` plus existing `codex_ai_transcript_test`. No matrix harness expansion required for v1.

## Migration / compatibility

- No on-disk format change.
- Claude / OpenCode paths that already emit fewer assistants: coalesce is a no-op or merges only true fragments; Cot benefits multi-tool turns the same way.
- Existing `AiReasoningPartView` / tool views remain the expanded inner chrome.

## Success criteria

1. The long alternating「推理 / 已使用工具」list collapses by default to「思考过程 · N 步」+ final answer.
2. Expand reveals full reasoning and tool results.
3. Disk rollout unchanged; resume unaffected.
4. Shared IR path — not a Codex-only UI special case.
5. Other CLIs unchanged or improved; no History seat isolation regressions.
