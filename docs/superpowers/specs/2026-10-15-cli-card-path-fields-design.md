# CLI Readiness Card Path Fields Design

Delta on [2026-10-14-cli-acp-readiness-card-design.md](2026-10-14-cli-acp-readiness-card-design.md).
Boot discovery, chips, registry-driven Settings, no `if (cli == …)` in
`pages/config/`, Cursor no Upgrade, Android skip detect — unchanged.

## Goal

The card's read-only path + version row is harder to scan and edit than the
old single-line `TextField`. Restore an editable path field, put the
installed version in the field suffix, and keep Install / Browse / Locate /
Upgrade as text buttons on the same row.

## Locked decisions (2026-10-15)

- One card per launchable CLI (keep header icon, name, Ready / Needs setup /
  Update available chip).
- Path is a single-line `TextField`. Version is a suffix inside the field
  (unknown → `—`). Not a second row of text.
- Action buttons sit **outside** the field, same pattern as Git / Node:
  Install (missing), Upgrade (npm outdated), Browse, Locate (empty stored
  path) or Reset (stored path set).
- Claude / Codex: **two** field rows — CLI and ACP. ACP path is editable
  and **persisted**.
- Cursor / OpenCode / Gemini: **one** CLI field row only. Personal ACP
  switch (when `AcpSettingsCapability.showsPersonalAcpSwitch`) sits at the
  card bottom. Gemini has no switch.
- Toolchain (git / node) rows unchanged.

## Card layout

```
[icon] Claude Code                          [就绪]
CLI  [ /usr/bin/claude              2.0.14 ]  Browse  Reset
ACP  [ /usr/bin/claude-agent-acp    0.9.1  ]  Browse  Locate
     [ switch: New personal / mixed sessions use ACP ]
```

Cursor / OpenCode omit the ACP field row; the switch (if any) stays under
the CLI row. Empty field: show Install + Browse + Locate. Outdated npm:
add Upgrade. Cursor never shows Upgrade.

Extract a private path-field row widget (label + `TextField` + version
suffix + action buttons) used for CLI and ACP so
`cli_readiness_card.dart` does not grow a second copy of debounce /
controller logic.

## Persistence

CLI keeps `SessionPreferences.cliExecutablePaths`.

Add `SessionPreferences.acpAdapterPaths` (`Map<String, String>`, keyed by
`CliTool.value`, default `{}`). Round-trip in JSON. Cubit:
`setAcpAdapterPathFor` / `configuredAcpAdapterPath`, mirroring CLI.

Priority (same as CLI):

1. User-stored absolute path wins over boot discovery.
2. Empty stored path → show the boot-discovered path in the field. Persist
   only when the user Locate, Browse, or edits the text to a value other
   than the current stored path. Blurring a field that is only showing a
   discovered path must not copy discovery into `cliExecutablePaths` or
   `acpAdapterPaths`.
3. Reset clears the stored path and returns the field to discovery / empty.
4. Launch adapter executable: stored absolute path → discovered absolute
   path → `AcpCapability.agentExecutable` bare name.

`mergeLocatedAcpAdapters` must not overwrite a non-empty stored user path.

## Typing and Locate

Debounce + blur persist, same as the old CLI path row
(`kSessionPathPersistDebounce`). Browse uses `FilePicker`. Locate uses
existing CLI / adapter locators (`locateOverride` in tests). Android:
adapter Install / Locate / Browse hidden; switch disabled.

## Tests

Update `cli_config_section_test.dart` and cubit persistence tests:

- Empty CLI/ACP: `TextField` present; Install + Locate on that row.
- Configured path: field text is the absolute path; suffix shows version;
  Reset replaces Locate.
- Blur / debounce writes `cliExecutablePaths` / `acpAdapterPaths`.
- Locate success fills the field (`locateOverride`).
- Cursor: no Upgrade. Gemini: no ACP field, no personal switch.
- Android: switch disabled, no adapter buttons.
- Smoke: Claude card still opens from Settings; assert the Claude CLI
  `TextField` key, not the old “Claude Code CLI path” label.

Covering files: `cli_config_section_test.dart`,
`session_preferences_cubit_test.dart`, `app_shell_smoke_test.dart`.
No full-suite gate for this UI delta.

## Out of scope

Launch ACP-vs-PTY policy, permission chips, remote SSH adapter install,
toolchain rows, splitting the card into a new public file beyond the
private path-field row, changing chip rules or `npm view` timing.
