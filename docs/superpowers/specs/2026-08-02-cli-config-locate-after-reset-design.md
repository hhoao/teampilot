# CLI config: Reset → Locate after clear

**Date:** 2026-08-02  
**Status:** Draft for review  
**Problem:** On Settings → CLI, clearing a custom executable path disables **Reset** and (when the binary is unknown) leaves only **Install**. Users who already have the CLI on PATH cannot re-discover it without browsing or reinstalling.

## Goal

1. When the path field is empty, the same trailing action that was **Reset** becomes **Locate**.
2. Locate scans PATH (login-shell fallback locally; remote locate on SSH/Termux for **AI CLIs**; toolchain Locate is **local-only** in v1), then on success **writes the absolute path into the field and persists it as the user-configured path** (so **Reset** returns).
3. Apply the same slot swap to AI CLI rows and toolchain rows (Git / Node).

## Non-goals

- Changing Install / Browse visibility or install flows.
- A separate always-visible Locate button beside Reset.
- Only refreshing discovered/hint paths without persisting (rejected; user chose persist-as-config).
- Onboarding detect-step redesign (settings page only; reuse its discovery helpers).

## Behavior

| Field state | Trailing action | Action |
|-------------|-----------------|--------|
| Non-empty user path | **Reset** | Clear field + persist empty (unchanged) |
| Empty path | **Locate** | Discover executable; success → set field + persist + success toast; failure → error toast, field unchanged |
| Locate in progress | Same button, loading, disabled | Prevent double-tap |
| Remote work plane + toolchain empty | **Locate** | Toast `cliExecutablePathLocateRemoteUnsupported`; do not write |

**Install** and **Browse** keep current rules:

- Install: shown when `installKey != null`, field empty, and `hasKnownCliExecutable` / `hasKnownToolchainExecutable` is false. After Reset, Install stays hidden if startup discovery already knows a path (unchanged).
- Browse: disabled on remote work plane (unchanged).

AI CLI Locate remains available on remote work plane (unlike Browse).

## Design

### 1. UI slot swap

Files:

- `client/lib/pages/config/cli_executable_path_settings_row.dart`
- `client/lib/pages/config/toolchain_path_settings_row.dart`

Today: `TextButton(onPressed: isFallback ? null : _reset, child: Reset)`.

Change:

- `isFallback` (stored path empty) → label `cliExecutablePathLocate`, icon optional (`Icons.my_location_outlined` or similar), `onPressed: _locate` (disabled while locating).
- Else → label `cliExecutablePathReset`, `onPressed: _reset`.

Reuse existing `resetKey` for the shared button widget (tests assert label / behavior, not a second key). Optional: add dedicated `locateKey` only if widget tests need both keys simultaneously — not required for v1.

Local state: `_isLocating` (mirror `_isInstalling` pattern). Do not run locate while installing (and vice versa if both visible).

### 2. Locate implementation

**AI CLI row**

- Local: `CliExecutableDiscovery` → locate the single `widget.cli` via registry `ExecutableResolverCapability.defaultExecutableName` + `CliToolLocator` (or extend discovery with `locateLocalCli(CliTool)` if a one-shot helper keeps the row thinner — prefer a small discovery API over duplicating locator wiring in the widget).
- Remote work plane: reuse the same SSH/Termux profile resolution as `_installCli` / onboarding (`ConnectionModeService` + `SshProfileCubit` / Termux), then `CliExecutableDiscovery.locateRemoteCli`.
- On success path `P` (same persist shape as Install / Browse — **do not** call `mergeLocatedExecutables`; that API skips when a user path is set and would no-op after persist):
  1. Cancel persist debouncer; set controller text to `P`.
  2. `await cubit.setCliExecutablePathFor(cli, P)`.
  3. Always show success toast (`cliExecutablePathLocateSuccess`).
- On failure / empty: error toast (`cliExecutablePathLocateFailed`); do not write.

**Toolchain row**

- Local: single-tool helper preferred (`locateLocalTool(toolId)`) so a click does not scan both git and node.
- Git: reuse `GitInstaller.detectGit` / existing discovery path.
- Node: `CliToolLocator('node').locate(...)`.
- On success path `P`: cancel debouncer → set controller → `await cubit.setToolchainPath(toolId, P)` → success toast. **Do not** call `mergeLocatedToolchains` after persist (same reason as AI CLI).
- Remote: toolchain discovery is local-only in bootstrap today. **v1: toolchain Locate is local-only; on remote work plane show `cliExecutablePathLocateRemoteUnsupported` and leave the field empty.** Do not add a new SSH toolchain protocol. AI CLI Locate supports remote.

### 3. l10n

Edit `app_en.arb` / `app_zh.arb` only:

| Key | EN | ZH |
|-----|----|----|
| `cliExecutablePathLocate` | Locate | 定位 |
| `cliExecutablePathLocateFailed` | Could not find {name} on PATH. | 未能在 PATH 上找到 {name}。 |
| `cliExecutablePathLocateSuccess` | Located {name} at {path}. | 已定位 {name}：{path}。 |
| `cliExecutablePathLocateRemoteUnsupported` (toolchain) | Remote locate is not supported for this tool. | 远程工作面不支持定位此工具。 |

Generate localizations via existing flutter gen-l10n flow.

### 4. Tests

Extend `cli_config_section_test.dart` (and/or row-level widget tests):

1. Empty configured path → Locate label visible; Reset label absent for that row.
2. Non-empty configured path → Reset label; Locate absent.
3. Locate success (injectable locator / fake discovery) → field + prefs path updated; button becomes Reset.
4. Locate failure → field stays empty; Install still shown when unknown.
5. Remote work plane + toolchain Locate → `cliExecutablePathLocateRemoteUnsupported` toast; field stays empty.

Mock process / discovery via constructor injection on discovery classes or optional locator callbacks on the row if needed for tests — follow existing `SessionPreferencesCubit(locatedExecutables: …)` patterns; avoid real `Process.run` in widget tests.

## Invariants

1. User-configured path always wins over discovered path (`resolveExecutable` order unchanged).
2. Locate success persists as user config only (same as Browse / Install success) — no post-persist discovery-cache merge.
3. Install visibility still uses `hasKnownCliExecutable` / `hasKnownToolchainExecutable` (discovery cache from startup/onboarding unchanged by Locate).
4. No new always-on Locate button; one slot swaps Reset ↔ Locate.

## Open follow-ups (out of scope)

- Remote toolchain locate parity with AI CLIs.
- Dedicated `locateKey` AppKeys if automation needs them.
