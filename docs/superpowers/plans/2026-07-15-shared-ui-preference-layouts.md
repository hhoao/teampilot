# Shared UI preference layouts Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or execute inline.

**Goal:** Extract reusable settings/preference layouts from `workspace_settings_widgets.dart` into `shared_ui` as `Tp*` primitives (no aliases).

**Architecture:** Preference list patterns (`TpPreferenceRow` / `TpPreferenceStack`), section chrome, card header, disclosure, status badge, compact select, typed segmented picker. Strip `workspace_surface_layers` and l10n from package widgets.

**Tech Stack:** Flutter, existing `shared_ui` / `TpTheme` / `TpTextStyles` / `TpSelect` / `TpSegmentedControl`.

---

### Task 1: Package APIs + tests
- Create preference / section / card header / disclosure / badge / compact select / segmented picker
- Enhance `TpCard` with optional outline border + zero padding
- Export from barrel; widget tests

### Task 2: Client migration
- Repo-wide rename; `SettingsConfiguredBadge` → `TpStatusBadge` with host labels
- `WorkspaceSettingsToggleStrip` → `TpSegmentedPicker`
- Delete `workspace_settings_widgets.dart` / toggle strip sources (or leave thin l10n-only if needed)

### Task 3: Verify
- `shared_ui` tests + client analyze
