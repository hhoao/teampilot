# Simple mode full-access default

## Goal

Simple (unteamed) landing compose defaults to **full access**, and that default is configurable in **Session** app settings. Workspace chip choices still override and persist.

## Behavior

| Case | Result |
|------|--------|
| No workspace landing prefs | `SessionPreferences.simpleModeDefaultFullAccess` (default `true`) |
| Prefs with explicit value | workspace prefs |
| Session setting toggle | Settings → Session → 「简单模式默认：完全访问」 |
| Save chip choice | always write `dangerouslySkipPermissions` |

## Out of scope

Automations new-rule default (except seeding from landing draft), continue/history override semantics, team member defaults (already `true`).
