# CLI + ACP Readiness Card Design

## Goal

Replace the settings AI CLI block (path row + `SwitchListTile` + hanging
adapter Install) with one **readiness card per launchable CLI**. Cards show
detect / install / locate / version / upgrade for the CLI binary and, when
the CLI uses a separate ACP adapter, for that adapter too.

Decisions locked with the user (2026-10-14):

- Layout **A1**: unified readiness card. Header chip Ready / Update available
  / Needs setup. CLI and ACP are sibling rows. Version on each row. Upgrade
  only when a newer npm package exists. Install only when that binary is
  missing. Long ACP `SwitchListTile` copy becomes a one-line switch plus a
  short caption.
- **Boot-time detect** (same shape as today's CLI discovery): on desktop
  startup, background-locate CLI binaries **and** separate ACP adapters so
  the card is already filled when Settings opens. User-configured CLI paths
  always win over discovery. Locate in the card re-runs the same locators.
- Claude / Codex ACP: separate adapter (`claude-agent-acp`, `codex-acp`) —
  detect, install, locate, version, upgrade. Path is shown, not a second
  text field. Browse stays on the CLI row only.
- Cursor / OpenCode ACP: `cli acp` (same binary). ACP row says
  “uses CLI · acp”. No adapter install. Version is not duplicated.
- Gemini: CLI readiness only. No personal-ACP switch (unchanged).
- Cursor CLI is a curl/PowerShell installer, not npm: no Upgrade (cannot
  compare registry versions). Missing Cursor still shows Install.
- Android: card visible, ACP switch disabled, adapter actions hidden.
- Toolchain (git / node) group unchanged.
- Connect never installs. Upgrade reuses the existing install /
  `installAdapter` job (install already pulls latest).
- Settings UI is registry-driven. No new `if (cli == …)` in the page.

This does not change launch policy (when a session uses ACP vs PTY),
permission chips, or remote SSH adapter install (adapter jobs stay
local-only).

## Why

CLI already has path + Install / Browse / Locate, plus boot
`CliExecutableDiscovery`. ACP only has a preference switch and, for
Claude / Codex, an Install button with no found/missing/path/version.
`SwitchListTile` does not match `TpPreferenceStack`. Codex's install
label currently reuses Claude l10n. Adapter locate on Windows returns
the bare name.

## Card UI

One card per `CliToolRegistry.builtIn().launchable` entry that has
`CliExecutableCapability`. Brand icon + name + chip. Two resource rows
when `AcpCapability` is present; Gemini omits the ACP switch; Cursor /
OpenCode ACP row is “uses CLI”.

| Chip | When |
|------|------|
| Ready | CLI found (and adapter found if separate), no newer npm version |
| Update available | At least one npm-backed binary is outdated |
| Needs setup | CLI missing, or separate adapter missing |

Row actions (contextual, never all at once):

| Action | When |
|--------|------|
| Install | That binary is missing and `supportsInstaller` / adapter installer exists |
| Upgrade | npm-backed, installed version known, `npm view` returned a different latest |
| Locate | Shown for ACP adapter rows; CLI Locate remains when the stored path is empty (same as today) |
| Browse / Reset | CLI row only (Reset when the user has a stored path) |

Switch: “New personal / mixed sessions use ACP” with a short caption that
native teams and remote members still use the terminal. Missing adapter
does not force the switch off; launch still fails with existing
`acpChatLaunchFailed` copy until Install / Locate succeeds.

## Boot-time detect

Today (`app_shell.dart`, non-Android): background
`CliExecutableDiscovery.locateLocal()` + `ToolchainExecutableDiscovery`,
then `SessionPreferencesCubit.mergeLocatedExecutables` /
`mergeLocatedToolchains`. User `cliExecutablePaths` always win. Discovery
is in-memory (`_locatedExecutables`), not written to JSON.

**Extend that same callback** (do not add a second boot task):

1. Locate CLI paths (existing).
2. Locate separate ACP adapters for every launchable CLI whose
   `AcpCapability.usesSeparateAdapter` is true (Claude, Codex).
3. `mergeLocatedAcpAdapters` — same rules as CLI: skip empty, skip if
   unchanged, bump `locatedExecutablesRevision`. v1 has no user-overridden
   adapter path (no ACP text field).
4. After paths merge, **local `--version` only** for each absolute located
   CLI and adapter path. Cache versions on the cubit (in-memory). Do
   **not** call `npm view` at boot (network, slow). Latest-version checks
   run when the settings card is visible.

Android: still skip this block (same as today's CLI discovery).

Locate / Install / Upgrade in the card refresh the same in-memory maps
and re-probe `--version` for that binary. Settings must not require a
manual Locate to show a path that boot already found.

Adapter locate order (Claude / Codex, including Windows): `PATH` entries
for the adapter name, then `~/.local/bin` (Unix), then TeamPilot node
prefix, else the bare name (spawn still fails closed). Windows currently
returns the bare name only — fix as part of this work (`PATH` split on
`;`, `PATHEXT`).

Spawn (`AcpCapability.agentExecutable` / launch wiring): if the cubit has
an **absolute** discovered adapter path, use it; otherwise fall back to
`locateAdapter` / bare name. Do not add `acpExecutablePaths` JSON in v1
(no ACP text field / Browse).

## Capabilities

Extend `AcpCapability` with defaults so Cursor / OpenCode / Gemini stay
small:

| Member | Default | Override |
|--------|---------|----------|
| `usesSeparateAdapter` | `false` | Claude, Codex `true` |
| `adapterExecutableName` | `null` | `claude-agent-acp` / `codex-acp` |
| `adapterInstaller` | `null` | existing `ClaudeAcpAdapterInstaller` / `CodexAcpAdapterInstaller` |
| `showsPersonalAcpSwitch` | `true` | Gemini `false` |

The page asks the registry for `CliExecutableCapability` + optional
`AcpCapability`. It does not switch on `CliTool`.

`docs/cli-architecture.md` adds `AcpCapability` to the optional-capability
table (it is missing today) and documents separate-adapter vs `cli acp`.

## Version and upgrade

- Installed version: run `<absolute-path> --version`, take a trimmed first
  line (or a small per-name parser if the first line is noisy). Failure:
  show “—” for version, keep the path.
- Latest: only when the installer is `NpmInstallerCapability` (CLI package
  or adapter package). Background `npm view <pkg> version` when the
  settings page is shown. Failure: no Upgrade, no toast.
- Upgrade: enqueue the existing `install` / `installAdapter` job; button
  label and job title say upgrading. On success, re-locate and re-probe
  `--version`.
- Cursor: `supportsInstaller` still drives Install-when-missing. No npm
  package → no Upgrade.

## Layering

| Piece | Owner |
|-------|--------|
| `CliReadinessCard` | `pages/config/` — one card; settings-only |
| `CliConfigWorkspace` | Iterate launchable → cards; toolchain block stays |
| `AcpAdapterDiscovery` | `services/cli/` — registry `usesSeparateAdapter`, injectable exists/PATH |
| `CliVersionProbe` | `services/cli/` — `--version` + optional `npm view`; injectable runners |
| `SessionPreferencesCubit` | `_locatedAcpAdapters` + version cache; merge at boot |
| `app_shell.dart` | Same non-Android `unawaited` discovery callback |
| Install jobs | Unchanged `InstallJobEnqueue.installCli` / `installClaudeAcpAdapter` / `installCodexAcpAdapter` |
| Launch | Prefer absolute discovered adapter path |

Delete the duplicated `_ClaudeAcpAdapterInstallButton` /
`_CodexAcpAdapterInstallButton` and Codex's one-off `SwitchListTile`.
`CliExecutablePathSettingsRow` is replaced by the card for AI CLIs;
toolchain keeps `ToolchainPathSettingsRow`.

File-size: `cli_config_section.dart` is already 561 lines — split the card
out. New services stay under the ~600-line soft limit. l10n only in
`app_en.arb` / `app_zh.arb` (including a Codex-specific adapter install
string; stop reusing Claude's).

## Data flow

```
boot (desktop)
  CliExecutableDiscovery.locateLocal
  AcpAdapterDiscovery.locateLocal
  --version for absolute paths
  merge into SessionPreferencesCubit (in-memory)
        │
        ▼
CliReadinessCard ──npm view (settings visible, npm-backed only)
        │
        ├── Locate / Install / Upgrade → existing jobs → merge + --version
        └── personal ACP switch → existing *PersonalAcpDefault setters
        │
        ▼
ACP spawn prefers absolute discovered adapter path
```

## Error handling

| Failure | UI |
|---------|----|
| `--version` non-zero / missing | Path stays; version “—” |
| `npm view` fails or empty | No Upgrade; no toast |
| Locate finds nothing | Needs setup; Install if supported |
| Install / Upgrade job fails | Existing toast (`TpToastVariant.error`) |
| Adapter missing, switch on | Chip Needs setup; launch uses existing `acpChatLaunchFailed` |

## Tests

Constructor-inject runners and filesystem. Widget tests for the card;
do not assert pixels. Run with `cd client && dart run tool/run_tests.dart`
— never `flutter test` directly.

**Card** (rewrite `cli_config_section_test.dart`):

- Ready: CLI + adapter found, versions present, no Install / Upgrade.
- Needs setup: adapter missing → Install + Locate; switch still togglable.
- Update available: installed ≠ `npm view` → Upgrade on that row.
- Cursor / OpenCode: ACP “uses CLI”, no adapter Install.
- Gemini: no personal-ACP switch.
- Cursor found: no Upgrade.
- Android: switch disabled, adapter actions hidden.
- Codex adapter button uses Codex copy, not Claude's.

**Boot / cubit:**

- Desktop discovery merge fills CLI and adapter paths without clicking
  Locate. User CLI path still wins.
- Android boot does not run discovery (existing).
- `mergeLocatedAcpAdapters` is a no-op when unchanged.

**Services:**

- Adapter locate: `PATH`, `~/.local/bin`, toolchain node prefix; Windows
  PATH / PATHEXT; missing → bare name.
- `--version` parse; failure → “—”.
- `npm view` failure → no latest, no throw.
- Upgrade enqueues the existing install / adapter job.

**Launch:** absolute discovered adapter path is preferred over a bare name.

**Docs:** `cli-architecture.md` lists `AcpCapability` and the two ACP
binary models.

## Out of scope

- ACP adapter Browse / editable path / `acpExecutablePaths` JSON.
- SSH / remote adapter install or remote adapter discovery at boot.
- Cursor registry version / Upgrade.
- Changing which sessions launch as ACP.
- Onboarding CLI step redesign (status icons there can stay).
- `npm view` at process start.
