# CLI message matrix — completion evidence

Branch: `feat/mock-model-gateway-cli-matrix`  
Recorded: **2026-07-22**

L2 cells: History compose → deliver → chat bubbles (≥3 assistant replies; collab for native/mixed). Gateway: `tools/mock_model_gateway`. Run commands: [DEVELOPMENT.md](DEVELOPMENT.md#mock-model-gateway--cli-message-matrix).

## Status (2026-07-22)

| CLI | simple | native | mixed |
|-----|--------|--------|-------|
| claude | green | green | green |
| flashskyai | green | green | green |
| codex | green | N/A | green |
| opencode | green | N/A | green |
| cursor | **BLOCKED** | N/A | **BLOCKED** |

**Cursor:** public `cursor-agent` has no loopback model redirect (Cursor cloud auth only). Spike: Task 15 / `CliTestProfile` for `CliTool.cursor` (`62f81e77`).

## Evidence commits

| Cell | Commit |
|------|--------|
| claude simple | `c5dff7a6` |
| claude mixed | `fb41cb12` |
| claude native | `cd29b08e` |
| flashskyai simple/native/mixed | `c9a9e67f` |
| codex simple/mixed | `e0a4575d` |
| opencode simple/mixed | `5258d00e` |
| cursor blocked | `62f81e77` |

Tests: `client/test/integration/cli_message_matrix_{claude,flashskyai,codex,opencode}_test.dart`.

## Regression smoke (deliberate break)

Skipped on 2026-07-22 — a full L2 cell (Linux build + PTY + vendor CLI) exceeds the ~10 minute budget for a temporary break/confirm/revert cycle. Rely on green evidence commits above; re-run a single cell locally if product code near History submit / bubble append changes:

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_claude_test.dart \
  --plain-name="simple"
```
