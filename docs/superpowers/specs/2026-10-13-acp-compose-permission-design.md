# ACP Compose Permission Design

## Goal

Put the existing compose permission chip back on **ACP chat only** (personal
ACP sessions, mixed ACP seats, and Landing when that launch will be ACP),
so the user can pick **Ask** or **Full access**. PTY stays
full-access-only and does not show the chip.

Decisions locked with the user (2026-10-13):

- Surfaces: ACP session compose **and** Landing when the selected launch
  will be ACP. Not PTY compose.
- Capability matrix is `(CLI × PTY|ACP) → policies`. Phase 1: PTY is
  `{fullAccess}` (no chip). ACP is `{ask, fullAccess}` for every ACP CLI.
- Default for new ACP sessions and mixed ACP seats: **Full access**.
- Persist a session/seat fact **and** a global
  `SessionPreferences.acpPermissionDefault` (Landing remembers the last
  pick). One preference for all ACP CLIs, not per-CLI, not personal-vs-mixed.
- Changing the preference does not rewrite existing sessions or seats.
- teammate-bus / host MCP is always auto-allowed.
- Handshake (`session/new`) auto-allows every permission (MCP init cannot
  wait on a card).
- After the session is open, Full access auto-allows; Ask shows
  `AcpPermissionCard` except host MCP.
- Mid-session chip changes apply to the next `request_permission` without
  reconnect. An in-flight card is not rewritten.
- Do not restore PTY permission flags, continue-override permission
  fields, or a settings-page switch.

This does not change the 2026-09-11 full-access-only **PTY** product
policy. It uses the ACP `session/request_permission` path that PTY skip
flags cannot express.

## Why ACP (not PTY flags)

PTY maps `LaunchSecurityPolicy.fullAccess` to `--force` /
`--dangerously-skip-permissions` / OpenCode config allows. There is no
honest Ask mode on that path today.

ACP already asks the client. TeamPilot can honor Ask vs Full access in
`session/request_permission` without CLI argv. Mixed unattended seats
default to Full access so collaboration does not stall on a card the
user is not looking at.

```
PTY:   LaunchSecurityPolicy.fullAccess → skip-permission flags; no chip
ACP:   preference / session fact → auto-allow or AcpPermissionCard
```

## Layering

Mechanism vs declaration: compose pages ask the registry, not `if (cli == …)`.

| Piece | Owner |
|-------|--------|
| `CliLaunchSecurityCapability.policiesFor({required bool acp})` | Runtime axis. Existing `supportedPolicies` stays the **PTY** set used by `CliLaunchArgAssembler`. |
| `LaunchSecurityPolicy.ask` | Named preset: `approval: ask`. Do **not** reuse `askReadOnlyTrusted`. |
| `SessionPreferences.acpPermissionDefault` | Global last pick. Missing JSON key → `fullAccess`. |
| `AppSession.acpPermission` | Personal ACP session fact. Omit when not ACP or when `fullAccess`. |
| `SessionMemberBinding.acpPermission` | Mixed ACP seat fact. Omit when `acp` is false or `fullAccess`. |
| `services/acp/acp_host_mcp_permission.dart` | Protocol-layer auto-allow / host-MCP detection. Handshake always allows; after open, gate on policy. |
| `AcpAgentSession` | Holds current policy; `setPolicy` for mid-session chip changes. |
| Compose chip wiring | Extracted helper(s), not inline in oversized compose files. |

No settings row. No `if (cli == …)` in `SessionChatComposeSection` or
unbound Landing compose. Extending the existing personal-ACP allow-list
helper so Gemini counts as “will launch ACP” is the same pattern
`resolveLaunchAcp` already uses.

## Capability

Keep `supportedPolicies` and `supportsUserConfiguration` as the PTY /
assembler view so launch argv validation does not change:

- `supportedPolicies == {fullAccess}`
- `supportsUserConfiguration == false`

Add:

```dart
Set<LaunchSecurityPolicy> policiesFor({required bool acp});

bool supportsUserConfigurationFor({required bool acp}) =>
    policiesFor(acp: acp).length > 1;
```

`FullAccessOnlyCliLaunchSecurityCapability` returns `{fullAccess}` for
both runtimes.

Every CLI that registers `AcpCapability` uses a shared implementation
whose `policiesFor(acp: true)` is `{ask, fullAccess}` and
`policiesFor(acp: false)` is `{fullAccess}`. Today that is Gemini,
Claude, Cursor, and Codex; OpenCode joins when it registers
`AcpCapability`. FlashskyAI stays full-access-only on both runtimes
(no `AcpCapability`).

The chip is shown only when `acp == true` and
`policiesFor(acp: true).length > 1`.

Assembler still rejects any non-`fullAccess` PTY `CliLaunchContext`.
ACP Ask must never reach `permissionLaunch` argv providers.

## Session model

### Named Ask preset

```dart
static const ask = LaunchSecurityPolicy(
  approval: LaunchApprovalPolicy.ask,
  sandbox: LaunchSandboxPolicy.fullAccess,
  hookTrust: LaunchHookTrustPolicy.cliDefault,
);
```

`requiresDangerousExecution` stays false (approval is not `never`).
JSON codec is a **named id**, not the three-tuple:

| Stored value | Policy |
|--------------|--------|
| omitted / `"fullAccess"` / unknown | `LaunchSecurityPolicy.fullAccess` |
| `"ask"` | `LaunchSecurityPolicy.ask` |

Unknown strings load as `fullAccess`. Do not throw on read.

Helpers live next to the preset (`acpPermissionToJson` /
`acpPermissionFromJson`). `toJson` returns null for `fullAccess` so
callers omit the key.

### Preference vs session vs seat

| Store | Role |
|-------|------|
| `SessionPreferences.acpPermissionDefault` | Default for **new** personal ACP launches and **new** mixed ACP seats. Default `fullAccess`. Missing JSON key → `fullAccess`. Omit JSON key when `fullAccess`. |
| `AppSession.acpPermission` | Durable fact for a **personal** ACP session. Reconnect / open-existing uses it. Team sessions omit it (`AppSession.acp` is already forced false). |
| `SessionMemberBinding.acpPermission` | Durable fact for a mixed ACP seat. Reconnect uses it. |

Changing the preference does not rewrite existing sessions or seats.
An ACP session created before this feature has no key and is Full
access.

Include the field in `==` / `hashCode` / `copyWith`. Do not revive
permission fields on `SessionContinueOverrides`.

### Create / stamp

Personal create writes `AppSession.acpPermission` from the Landing
draft (which tracks the preference because the chip writes preference
immediately). Only persist when `AppSession.acp` is true.

Mixed create: `stampMemberAcp` (or a sibling) stamps
`acpPermission` on every binding that ends `acp: true`, from the same
global preference / Landing draft. PTY seats omit the field.

`SessionCreateRequest` carries one `acpPermission` seed (default
`fullAccess`). Call sites that already thread personal ACP defaults
also thread this seed from `readAcpPermissionDefault`. Do not invent a
per-CLI permission seed map.

### Landing “will be ACP”

Personal Landing shows the chip when the launch will be ACP:

- Gemini simple (existing infer-ACP path), or
- `resolveLaunchAcp(...)` true (personal desktop Claude / Cursor /
  Codex, and any CLI later added to that allow-list, when that CLI’s
  ACP default is on)

Put that disjunction in one helper next to `resolveLaunchAcp`. Compose
calls the helper.

Team Landing shows the chip when `stampMemberAcp` would mark **at
least one** mixed local seat ACP. The pick stamps every such seat.
Android / SSH / native teams never show it.

## Launch / runtime

ACP connect is unchanged (still `AcpSessionRuntime` / per-seat cubit).
The session object learns the policy from `AppSession.acpPermission`
(personal) or `SessionMemberBinding.acpPermission` (mixed). Missing
field → `fullAccess`.

### Handshake

Agents ask `session/request_permission` during `session/new` (MCP
init). No `AcpAgentSession` exists yet; method-not-found makes Cursor
remember “User rejected MCP”.

`AcpAgentConnection.openSession` keeps an early
`session/request_permission` handler. That handler **always
auto-allows** (prefer allow-always, else allow-once). It does not
read Ask vs Full access. Reject-only options still cannot be
auto-allowed; answer cancelled and log.

### After open

`AcpAgentSession` registers the permission handler and applies:

| Request | Full access | Ask |
|---------|-------------|-----|
| teammate-bus / host MCP | auto-allow | auto-allow |
| other, has allow-always or allow-once | auto-allow (prefer always) | surface `AcpPermissionCard` |
| reject-only | surface card | surface card |

Detect host MCP from the raw tool-call title / input / meta
(`isTeammateBusToolCall`), not only from the later
`AgentPermissionRequest`. Remove cubit-level `_autoAllowTeammateBus`
once the protocol layer covers handshake and post-open host MCP. One
source of truth.

`autoAllowAcpPermission(params, {required bool allowNonHost})`:

- Handshake and Full access pass `allowNonHost: true` (every allowable
  option).
- Ask after open passes `allowNonHost: false` (host MCP only).

Prefer allow-always, else allow-once. Return null when nothing is
auto-allowed so the session can surface a card.

### Mid-session change

Chip on an ACP session/seat:

1. Persist the session or binding fact.
2. Write `acpPermissionDefault`.
3. `AcpAgentSession.setPolicy` (or cubit equivalent) immediately.

The next `request_permission` uses the new policy. A card already
held is answered with the user’s click; do not auto-complete it when
switching to Full access.

No reconnect. No PTY fallback.

## UI

Reuse `ComposePermissionChip` / `ComposePermissionControl`. Extend the
chip to render `LaunchSecurityPolicy.ask` (new `askLabel`). Do not
overload `askReadOnlyTrusted`.

l10n: `client/lib/l10n/app_en.arb` and `app_zh.arb` only.

| Key | EN | ZH |
|-----|----|----|
| `acpPermissionAskLabel` | Ask | 询问 |
| `acpPermissionFullAccessLabel` | Full access | 完全访问 |

`ComposePermissionControl.defaultLabel` stays required; pass the Ask
label. `cliDefault` is not in the ACP set, so the chip will not
render a Default row.

Landing chip `onSelected`: write preference immediately (even if the
user never creates). Session chip `onSelected`: persist fact +
preference + runtime policy.

No Landing visible “ACP vs PTY” extra control in this spec. The
permission chip simply appears when the launch/seat is ACP.

PTY Landing, PTY seats, Android: no chip.

## File size / placement

These files are already over the services/pages soft limits. **Do not**
grow them with policy branching:

| File | Rule |
|------|------|
| `unbound_compose_body.dart` (~1756) | Pass a ready `ComposePermissionControl?` from a helper. |
| `session_chat_compose_section.dart` (~1182) | Same: helper builds the control. |
| `acp_session.dart` (~719) | Call `autoAllowAcpPermission`; do not inline host-MCP parsing. |
| `acp_chat_runtime_cubit.dart` (~917) | Policy lives on the session/runtime. Remove `_autoAllowTeammateBus`; protocol layer is the source of truth. |
| `cli_config_section.dart` | No new settings row. |

New / small files:

| File | Rule |
|------|------|
| `services/acp/acp_host_mcp_permission.dart` | Auto-allow + option-id pick. Policy argument. |
| `models/launch_security_policy.dart` | Add `.ask` + named-id codec. |
| `services/cli/registry/capabilities/cli_launch_security_capability.dart` | `policiesFor`. ACP-capable implementation (shared class, registered by each ACP CLI tool). |
| Helper next to `claude_acp_launch_switch.dart` | `willLaunchPersonalAcp`, `readAcpPermissionDefault`, Landing/session `ComposePermissionControl` builder. |

`AppKeys` for the chip if tests need a stable finder; otherwise existing
`ComposeMenuChip` text finders are enough.

## Error handling

| Failure | Handling |
|---------|----------|
| Malformed `request_permission` | `PermissionCancelled` + `AppLogger`. |
| Timeout / dispose / user reject | Existing cancelled default. |
| Reject-only options | Surface the card; cannot auto-allow. |
| Policy not in `policiesFor(acp: true)` | Do not persist it; chip only renders capability policies. Load unknown as `fullAccess`. |
| Ask persisted on a later CLI that only supports fullAccess | Treat as `fullAccess` at runtime (capability wins). |
| PTY context with Ask | Assembler `CliLaunchCapabilityException`; should be unreachable from UI. |
| Handshake with no allow option | Cancelled + log; session/new may then fail (existing attach failure, no PTY fallback). |

User-visible copy stays existing permission-card l10n. Diagnostics stay
`AppLogger`. No `print`.

## Out of scope

- Restoring PTY `--permission-mode` / sandbox / hook-trust mappings
- Restoring team / automation / continue-override permission editors
- Per-CLI or mixed-vs-personal permission preferences
- Settings-page switch
- Path-level sandbox, `session/set_mode`, Cursor ask/plan cards
  (those stay Cursor extension methods, unrelated to this chip)
- Handshake permission cards
- Android / SSH ACP
- FlashskyAI ACP

## Testing

Constructor-injected fakes; cubit tests that need a home plane use
`setUpTestAppStorage()` / `tearDownTestAppStorage()`. Never invoke
`flutter test` directly; use `cd client && dart run tool/run_tests.dart`.

| Layer | Cases |
|-------|--------|
| `LaunchSecurityPolicy.ask` | Named-id codec; omit `fullAccess`; unknown → `fullAccess`; `requiresDangerousExecution` is false. |
| Capability | FlashskyAI both runtimes `{fullAccess}`; every CLI with `AcpCapability` has ACP `{ask, fullAccess}` and PTY `{fullAccess}`; `supportsUserConfigurationFor(acp: true)` true only for those CLIs. |
| Assembler | PTY + Ask still throws `CliLaunchCapabilityException` for each CLI. |
| Preferences | Default fullAccess; missing key → fullAccess; round-trip `"ask"`; cubit setter. |
| `AppSession` / binding | Personal ACP writes/omits `acpPermission`; team session omits it; mixed only on `acp: true` seats; equality. |
| `stampMemberAcp` / create | ACP seats receive the seed; PTY seats do not; preference change does not mutate an already-created session. |
| Handshake | bash-style and teammate-bus during `session/new` auto-allow even when session fact is Ask. |
| After open, Full access | bash auto-allows without a card; prefer allow-always. |
| After open, Ask | bash surfaces a card; teammate-bus does not. |
| Reject-only | still surfaces a card. |
| `setPolicy` | next request follows the new policy; held card unchanged. |
| Compose | personal ACP Landing (including Gemini) shows chip; PTY Landing does not; ACP session shows chip; PTY seat does not; team Landing shows chip iff at least one mixed ACP seat would be stamped. |
| Chip | selecting Ask writes preference immediately; session select persists fact. |

No live agent in CI. Manual desktop check: new Gemini/Claude ACP
session defaults Full access (no bash card); switch to Ask in compose
→ next tool asks; teammate-bus on a mixed ACP seat never asks;
handshake MCP still connects under Ask; PTY Claude compose has no
chip; new session after picking Ask on Landing starts in Ask.

## Logging

Reuse `AcpFrameLogger`. Log auto-allow with tool title / option id at
info. Do not log MCP auth payloads or isolated `auth.json`.
