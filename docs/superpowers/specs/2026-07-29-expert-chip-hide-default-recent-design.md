# Expert chip: hide builtin Default from recent

**Date:** 2026-07-29  
**Status:** Approved (option B)

## Problem

Landing expert menu shows both **未选择专家** and **Default**. They look like two choices, but empty selection already launches the builtin Default pack (`teampilot/builtin/default`). Default also lands in “recent” because empty-submit touches that key.

## Decision

Keep **未选择专家** as the none-selected state. **Builtin Default never appears in the recent list** and is never written into recent.

Explicit Default (via 浏览全部) may still be selected for the chip; it simply does not enter recent.

## Behavior

| Path | Change |
|------|--------|
| Chip menu recent | Exclude `kBuiltinDefaultExpertKey` |
| `_touchRecentExpert` / submit `touch` | No-op for builtin default; empty draft does not touch |
| Session launch | Unchanged: empty draft → builtin default via `resolveLandingSessionExpertKey` |

## Non-goals

- Renaming Default / merging none-selected into a single “默认” chip item (option A)
- Changing Simple launch fallback to another expert
