# Live workspace-open performance driver

## Goal

Fully automate **open workspace on real local app data** (`~/.local/share/com.hhoa.teampilot`), capture DevTools-compatible performance JSON, and print a summary — without the mock `integration_test` harness and without Computer Use.

## Approach

Debug-only loopback HTTP driver inside the real app + external CLI orchestrator.

| Piece | Role |
|-------|------|
| `LivePerfDriver` | Enabled only with `--dart-define=PERF_DRIVER=true`. Serves `127.0.0.1:17999`. Navigates via `appRouter.go`, collects `FrameTiming`. Exposes VM service URI via `dart:developer`. |
| `tool/run_live_workspace_open_perf.dart` | Discovers workspaces on disk, launches or attaches, `capture/start` → open workspace → settle → merge frames + remote Perfetto timeline → analyze summary. |

## Non-goals

- Mock providers / fake PTY harness
- Driving DevTools UI or OS clicking
- Shipping driver behavior in release (compile-time define)

## Default scenario

Open the first workspace under `workspace/workspaces/` (override with `--workspace <id>`).
