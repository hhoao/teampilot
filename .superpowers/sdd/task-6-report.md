# Task 6 Report: Installed row, tools dialog, and page triggers

**Status:** DONE  
**Commit:** `44f6f5b97` — Show MCP online status, tool counts, and a read-only tool list.  
**Worktree:** `/home/hhoa/git/hhoa/teampilot/.worktrees/feat-mcp-installed-probe`

## Files

- Modified: `client/lib/pages/mcp/mcp_shared_widgets.dart` (`McpInstalledServerRow` + `McpProbeStatusLine`)
- Created: `client/lib/pages/mcp/mcp_tools_dialog.dart` (`showMcpToolsDialog`)
- Modified: `client/lib/pages/mcp/mcp_installed_section.dart` (probe triggers, refresh-all, tools tap)
- Modified: `client/lib/pages/mcp/mcp_management_page.dart` (`_openAdd` / `_openEdit` probe after save)
- Created: `client/test/pages/mcp/mcp_installed_probe_test.dart`
- Modified: `client/test/pages/mcp/mcp_management_page_test.dart` (inject `FakeMcpProbeHandshake`)

Did not split `mcp_shared_widgets.dart` (380 lines, under ~500). Team/workspace MCP assignment rows unchanged. Switch / edit / delete / homepage / OAuth stay outside the row body tap target.

## TDD evidence

### Step 1 — existing page test stays green (before UI probes)

```bash
cd client
dart run tool/run_tests.dart test/pages/mcp/mcp_management_page_test.dart
```

**Result:** PASS (2 tests). Cubit constructed with `FakeMcpProbeHandshake` + 2s timeout. No Installed probe UI yet.

### RED — new widget tests fail for missing keys/copy

Wrote `mcp_installed_probe_test.dart` (same `pumpListPage` harness; fake returns `health_check` + `open_files` for `fetch`).

```bash
cd client
dart run tool/run_tests.dart test/pages/mcp/mcp_installed_probe_test.dart
```

**Result:** FAIL (2 failed, 2 passed)

| Case | RED outcome |
|------|-------------|
| Enabled `fetch` shows `Key('mcp-probe-status-fetch')` and `2 tools` | FAIL — `Found 0 widgets with key [<'mcp-probe-status-fetch'>]` |
| Disabled `fetch` hides status key | PASS (vacuous — key did not exist yet) |
| Tap `Fetch` opens tools (`health_check`), not editor (`mcp-id`) | FAIL — `Found 0 widgets with text "health_check"` |
| Edit icon still opens JSON editor | PASS (existing behavior) |

Failures were missing UI, not typos.

### GREEN — implement status line, dialog, triggers

- Row: enabled-only status line (8px grey / `Color(0xFF22C55E)` / `cs.error`; `needsAuth` uses `mcpProbeNeedsAuth`, no green). Left column `GestureDetector` → `onOpenTools`.
- Dialog: `showTpDialog` + `TpDialog` maxHeight 480 + `BlocBuilder` on `probes[server.id]`; Reload `Key('mcp-tools-reload')` → `probeOne`; close via header + `l10n.cancel`.
- Installed: post-frame `probeEnabled()`; `didUpdateWidget` probes enabled ids missing snapshots when status becomes `ready`, server ids change, or the servers list changes (covers re-enable). Header `Key('mcp-probe-refresh-all')` → `refreshAll()`. OAuth success → `probeOne(server.id)`.
- Add/edit success → `probeOne(id)` if the saved server is enabled.

```bash
cd client
dart run tool/run_tests.dart test/pages/mcp/mcp_installed_probe_test.dart test/pages/mcp/mcp_management_page_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/mcp lib/cubits/mcp_cubit.dart lib/services/mcp
```

**Result:** PASS — 6 tests. Analyze: No issues found.

## Concerns

- Disabled-row RED was vacuous (key absent). GREEN covers the hide path.
- `didUpdateWidget` also probes when the servers list object changes (not only ids) so re-enable does not stick on “Checking…”. Snapshots-only cubit updates keep the same servers list, so they do not re-probe.
- Tools dialog `needsAuth` shows `mcpProbeNeedsAuth` (brief specified checking / empty / tools / offline only).
- No dedicated widget test for Reload, refresh-all, or add/edit/OAuth probe triggers.
- `_addFromListing` still relies on Installed `didUpdateWidget` (new id → missing snapshot) rather than `_openAdd`.

## Important review fix — OAuth success before probe

**Finding:** `_connectOAuth` awaited `probeOne` (up to 15s) before `onOAuthConnected` and the success toast.

**Change:** Run `onOAuthConnected`, success toast, then `unawaited(probeOne)` (same fire-and-forget pattern as header `refreshAll`). OAuth status reload is also fire-and-forget so confirmation is not blocked. Added `@visibleForTesting debugShowMcpOAuthConnectDialog` for widget test stub.

**Test:** `OAuth success toast runs before slow probe completes` — stub dialog success, 500ms handshake delay; asserts callback fires while `handshake.inFlight == 1`.

```bash
cd client
dart run tool/run_tests.dart test/pages/mcp/mcp_installed_probe_test.dart test/pages/mcp/mcp_management_page_test.dart
```

**Result:** PASS — 7 tests.
