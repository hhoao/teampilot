# Managed Provider per-entry official credentials

Date: 2026-09-03
Status: Approved design

## Problem

The main window "balance & usage" panel offers quick presets (Claude Code,
Codex, Cursor) whose credential source is a shared `cli:<id>` single CLI
provider row (`cursor-account`, `claude-official`, `openai-official`).
Consequences:

1. **No per-entry isolation** — every managed provider entry using the same
   preset resolves credentials from the same CLI provider row.
2. **Silent global fallback** — the official subscription auth readers fall
   back to machine-global logins (`~/.claude/.credentials.json`,
   `~/.codex/auth.json`, `~/.config/cursor/auth.json`, `%APPDATA%\Cursor\`),
   so selecting a preset immediately appears "logged in" without the user
   ever logging in inside TeamPilot.

## Goal

Each managed provider entry (preset instance) that uses a `cli:` credential
source owns an **independent account and login**:

- Every entry is bound to its own dedicated CLI provider row and isolated
  HOME directory.
- No automatic fallback to machine-global CLI/IDE credentials.
- Login, session launch, and usage query all read the same isolated
  directory (single source of truth).
- Scope: all three official CLIs — Claude Code, Codex, Cursor. API-key style
  entries (DeepSeek etc.) are already per-entry and unchanged.

## Design

### 1. Data model — per-entry CLI provider row

The `cli:<id>` credential source semantic changes from "the global single
CLI provider row" to "a CLI provider row dedicated to this managed provider
entry".

- When a managed provider entry with a `cli:` credential source is saved, a
  dedicated `AppProviderConfig` row is ensured to exist, with ID
  `<cli>-mp-<managedProviderId>` (e.g. `cursor-mp-abc123`). The row template
  is derived from the official preset for that CLI (name/icon/official
  flags), with the entry name appended for distinguishability.
- The isolated HOME path `providers/<cli>/<row-id>/home/` follows from the
  existing `providerHome()` mechanism — no new storage layout.
- The legacy shared rows (`cursor-account`, `claude-official`,
  `openai-official`) remain usable as ordinary CLI providers for launch
  profiles; managed provider entries simply no longer bind to them
  automatically.
- **Migration**: existing entries whose `credentialSource` is
  `cli:cursor-account` / `cli:claude-official` / `cli:openai-official` are
  migrated on next load: a dedicated row is generated and the source is
  rewritten to `cli:<cli>-mp-<id>`. Migration is idempotent (skip if the
  dedicated row already exists).

### 2. Credential reads — no global fallback

The three `*OfficialSubscriptionAuthReader` implementations (cursor, claude,
codex) change to:

- Read only the isolated directory of the entry's dedicated row
  (`providers/<cli>/<row-id>/…`). Global machine locations
  (`~/.cursor`, `~/.claude`, `~/.codex`, `%APPDATA%`) are never read for
  usage queries.
- `CliCredentialSourceResolver.read()` parses source strings of the form
  `cli:<row-id>` and resolves the row's isolated directory directly.
- Entries that were never logged in return `missingCredential` — the panel
  shows "credential not configured" instead of silently appearing logged in.
- The explicit "import from global" action remains available (user-initiated
  copy of global `auth.json` into the dedicated isolated directory); only
  the automatic fallback is removed.

### 3. Login UI and session-launch linkage

- `ManagedProviderOfficialCredentials` looks up (or creates) the entry's
  dedicated row instead of the fixed shared row previously ensured by
  `ensureOfficialAppProvider`. The existing OAuth device-code flow in
  `ProviderCredentialActionBar` is reused unchanged.
- Session launch: the cursor session providerId resolution chain
  (member.provider → team default → `CursorProviderSettingsResolver`)
  already resolves per-row isolated HOMEs. Dedicated rows appear in provider
  pickers, so launch profiles and team members can select them — sessions
  then use the same isolated directory the user logged into.
- Usage query: `HttpJsonMappingAdapter` resolves credentials via
  `CliCredentialSourceResolver`; the source string carries the row ID, so
  the token read is the one stored by that entry's login.

Login (write), session launch (read), and usage query (read) all point at
the same `providers/<cli>/<dedicated-row-id>/home/`.

### 4. Error handling

- Dedicated row missing (corrupted entry / manually deleted directory) →
  `missingCredential`.
- Expired OAuth token → existing 401/403 `authenticationFailed` path.
- Migration failure (provider directory write error) → entry keeps the old
  source; migration retries on next load (idempotent by design).

## Testing

- **Reader unit tests**: dedicated directory has token → read succeeds;
  global credential present but dedicated directory empty →
  `missingCredential` (regression lock: no fallback).
- **Migration unit tests**: old `cli:cursor-account` entry → dedicated row
  created + source rewritten; running migration twice is a no-op.
- **Editor widget tests**: creating an entry from the cursor preset shows
  the login action bound to the dedicated row.

## Out of scope

- API-key style entries (already per-entry isolated).
- Changes to launch argument construction or CLI config inheritance.
- Sharing credentials across machines (existing cross-machine credential
  bridge is unaffected).
