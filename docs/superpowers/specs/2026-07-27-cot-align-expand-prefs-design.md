# Chain-of-Thought Align + Expand Preferences

## Goal

Make the chat “思考过程” (chain-of-thought) chrome align with other assistant
rows (tool calls / body text), and stop auto-expanding nested reasoning and
tool payloads when the outer CoT opens. Expose fine-grained user preferences
for those nested expand defaults.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Visual style | Match `AiToolGroupView` / tool trigger rows — no bordered card panels |
| Outer CoT default | Stay collapsed (unchanged) |
| Nested default | Reasoning and tools both collapsed when CoT opens |
| Preferences | Separate toggles for reasoning vs tools |
| Pref storage | `LayoutPreferences` |
| Settings UI | Layout → Appearance → “思考过程” subsection |
| Injection | `AiMessageTheme` bools → `AiChainOfThoughtView` |
| Per-message expand memory | Out of scope (session UI state only, not persisted) |

## Problem

1. `AiChainOfThoughtView` wraps content in a full-width `DecoratedBox` border
   panel; nested `AiReasoningPartView` adds another bordered box. Tool rows and
   assistant text are flat trigger/body rows — CoT looks misaligned.
2. Opening CoT hard-codes `initiallyExpanded: true` for both nested reasoning
   and tools (`chain_of_thought_view.dart`), so every step dumps payloads at
   once. Existing tests encode that behavior.
3. There is no user-facing control for nested expand policy.

## Architecture

```
LayoutPreferences
  cotExpandReasoningOnOpen (default false)
  cotExpandToolsOnOpen     (default false)
        │
        ▼
LayoutCubit → chat Theme overlay
        │
        ▼
AiMessageTheme
  cotExpandReasoningOnOpen
  cotExpandToolsOnOpen
        │
        ▼
AiChainOfThoughtView (flat trigger chrome)
  └─ nested parts with initiallyExpanded from theme
```

### Visual

- **Outer CoT:** Same structure as `AiToolGroupView` — psychology icon +
  “思考过程 · N 步” + chevron; no outer border card. Left edge aligns with
  assistant body / tool triggers. Expanded children indent like ToolGroup
  (`left: 8`).
- **Nested reasoning:** Drop the bordered `DecoratedBox`. Use a tool-row-like
  trigger (icon + existing `strings.reasoning` / l10n label + chevron); body
  only when expanded.
- **Nested tools:** Keep `AiToolCallPartView`; only change default
  `initiallyExpanded` driven by theme.

Standalone reasoning outside a multi-step CoT (if any) follows the same
flat reasoning chrome so style stays consistent.

### Preferences

| Field | Default | Meaning |
|-------|---------|---------|
| `cotExpandReasoningOnOpen` | `false` | When outer CoT opens, expand nested reasoning rows |
| `cotExpandToolsOnOpen` | `false` | When outer CoT opens, expand nested tool rows |

Settings copy (l10n EN/ZH): title “思考过程” / “Thinking process”; two
preference rows with short subtitles describing “auto-expand when opening
the thinking process”.

`LayoutCubit` setters + JSON round-trip on `LayoutPreferences`. Missing keys
in old prefs files read as `false`.

### Theme injection

Add the two bools to `AiMessageTheme` (default `false`). Primary host wire is
the chat `Theme` overlay in `session_chat_view.dart` (copy from
`LayoutCubit.state.preferences` via `AiMessageTheme.copyWith`). Do not
duplicate prefs wiring in `session_history_thread` unless that path builds its
own independent `AiMessageTheme` without inheriting the chat overlay.

`AiChainOfThoughtView` reads theme and passes:

```dart
AiReasoningPartView(part: part, initiallyExpanded: aiTheme.cotExpandReasoningOnOpen)
AiToolCallPartView(part: part, initiallyExpanded: aiTheme.cotExpandToolsOnOpen)
```

No `AiPartRegistry` API change.

## Testing

- Update `chain_of_thought_view_test.dart`:
  - Default: open CoT → reasoning body and tool result **not** visible until
    nested rows are tapped.
  - Theme `cotExpandReasoningOnOpen: true` / tools `true` restores auto-expand
    for the corresponding nested kind.
- `LayoutPreferences` fromJson/toJson round-trip for the new fields.
- Optional widget smoke: appearance section shows the two switches (if cheap).

## Out of scope

- Changing outer CoT default open state
- Persisting per-message or per-step expand state
- Redesigning user bubbles or assistant text bubbles into cards
- Changing `AiToolGroupView` behavior outside CoT
- Transcript / history parsing changes

## Files (expected)

| Area | Path |
|------|------|
| CoT UI | `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart` |
| Reasoning UI | `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` |
| Theme | `client/packages/ai_message_ui/lib/src/theme.dart` |
| CoT tests | `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` |
| Prefs model | `client/lib/models/layout_preferences.dart` |
| Cubit | `client/lib/cubits/layout_cubit.dart` |
| Settings UI | `client/lib/pages/config/layout_appearance_in_layout_section.dart` |
| Theme wire | `session_chat_view.dart` Theme overlay (primary) |
| l10n | `client/lib/l10n/app_en.arb`, `app_zh.arb` |
