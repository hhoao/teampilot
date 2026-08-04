# CLI message matrix — completion evidence

Branch: `feat/matrix-roster-shape`  
Recorded: **2026-08-04**

L2 cells: History compose → deliver → chat bubbles (≥3 assistant replies; collab for native/mixed). Gateway: `tools/mock_model_gateway`. Run commands: [DEVELOPMENT.md](DEVELOPMENT.md#mock-model-gateway--cli-message-matrix).

## Axes

A matrix cell is **CLI × Mode × RosterShape** plus a gateway recipe.

| Axis | Values |
|------|--------|
| **CLI** | `claude`, `flashskyai`, `codex`, `opencode`, `cursor` |
| **Mode** | `simple`, `native`, `mixed` |
| **RosterShape** | `singleton`, `replicated`, `placementFiltered` |

`RosterShape` applies to team modes only (`native` / `mixed`). **Simple** ignores shape.

| Shape | Meaning |
|-------|---------|
| `singleton` | Lead + one worker type with `replicas=1` (`team-lead`, `developer`) |
| `replicated` | Worker type `replicas≥2` → session/CLI pods `developer-0`, `developer-1`, … |
| `placementFiltered` | Expanded pods minus placement omit list (Machines). **Builders + unit tests only** — no L2 cell yet |

Support: `client/test/integration/support/roster_shape.dart`, `native_roster_assertions.dart`.

## Status (2026-08-04)

Legend: **green** = L2 evidence on Linux PTY; **N/A** = mode or shape not applicable; **BLOCKED** = cannot redirect model traffic; **—** = not registered / deferred.

### Simple (shape N/A)

| CLI | Status |
|-----|--------|
| claude | green |
| flashskyai | green |
| codex | green |
| opencode | green |
| cursor | **BLOCKED** |

### Native

| CLI | singleton | replicated | placementFiltered |
|-----|-----------|------------|---------------------|
| claude | green | **green** | — (deferred) |
| flashskyai | green | — | — (deferred) |
| codex | N/A | N/A | N/A |
| opencode | N/A | N/A | N/A |
| cursor | N/A | N/A | N/A |

### Mixed

| CLI | singleton | replicated | placementFiltered |
|-----|-----------|------------|---------------------|
| claude | green | — | — (deferred) |
| flashskyai | green | — | — (deferred) |
| codex | green | — | — (deferred) |
| opencode | green | — | — (deferred) |
| cursor | **BLOCKED** | — | — (deferred) |

**Cursor:** public `cursor-agent` has no loopback model redirect (Cursor cloud auth only). Spike: `CliTestProfile` for `CliTool.cursor`.

### `claude × native × replicated` (green)

Recipe: **`nativeCollabReplica2Plus`** (`tools/mock_model_gateway/lib/scenarios/native_collab_replica_2plus.dart`).

Round shape: **2 lead History composes + 1 worker-0 reply** (not two full bidirectional ping-pongs).

1. Lead compose round 1 → `TaskCreate` / `SendMessage` to **`developer-0`** → `MARK_REPLICA_LEAD_1`; disk roster/inbox identity (`config.json` pods, `inboxes/developer-0.json`, not bare `developer.json`).
2. Worker-0 Claude process consumes pod inbox → `MARK_REPLICA_W0_1` → reply to lead.
3. Lead compose round 2 → `MARK_REPLICA_LEAD_2`. `developer-1` stays idle (pod-specific targeting).

Test: `cli_message_matrix_claude_test.dart` — `claude native replicated: pods inbox + worker-0 + 2 lead composes`.

### Adding `flashskyai × native × replicated`

Reuse recipe **`nativeCollabReplica2Plus`** (shared scenario) + register one L2 test in `cli_message_matrix_flashskyai_test.dart` with `shape: RosterShape.replicated` — same shape axis, no new recipe file required.

## Unit / harness tests (no PTY)

```bash
cd client && flutter test \
  test/integration/support/roster_shape_test.dart \
  test/integration/support/native_roster_assertions_test.dart \
  test/integration/support/cli_message_matrix_harness_test.dart
```

## L2 integration tests

`client/test/integration/cli_message_matrix_{claude,flashskyai,codex,opencode}_test.dart`

Regression smoke (single cell, ~10 min budget):

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_claude_test.dart \
  --plain-name="simple"
```
