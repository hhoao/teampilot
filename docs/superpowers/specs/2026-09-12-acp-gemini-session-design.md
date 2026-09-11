# ACP Gemini Session Design

## Goal

Introduce the Agent Client Protocol (ACP) into TeamPilot with Gemini CLI as
the first agent, as a terminal-less standalone chat session. This is the
first ACP integration: protocol mechanics live in a CLI-agnostic service
layer; Gemini is only the first declarer. Remote (SSH) transports, team
roster integration, and additional ACP CLIs (claude/codex adapters,
opencode native) are explicitly out of scope for this phase.

Decisions locked with the user (2026-09-12):

- **Scope: desktop-local only.** SSH exec transport is a later phase behind
  the `AcpTransport` seam.
- **Dependency: vendored acpd** (git submodule under `client/packages/`,
  same pattern as dartssh2/xterm). acpd is ~1 month old; we vendor to pin
  the version and retain patch rights.
- **Session shape: standalone single chat.** No team roster, no TeamBus,
  no member-shell flow.
- **Install: full auto-install** via the existing npm installer channel.
- **Permission UI: reuse the existing `AgentPermissionRequest` card**,
  with the answer channel mapped to the ACP outcome.

## Layering

Mechanism vs declaration separation — the core rule this design follows:

```
services/acp/                          ← protocol mechanics (CLI-agnostic)
  acp_transport.dart         Transport abstraction: byte-stream in, write out,
                             independent stderr, close. Local subprocess and
                             the future SSH exec channel are its two
                             implementations.
  acp_process_transport.dart Process.start implementation (no PTY; stderr is
                             NEVER merged into stdout — deliberately opposite
                             to SshPtyTransport's merge semantics; stderr is
                             routed to AppLogger).
  acp_connection.dart        One agent-process connection: transport mount,
                             acpd initialize handshake, negotiated-capability
                             cache, disconnect/exit lifecycle.
  acp_session.dart           Session handle: newSession/loadSession/prompt/
                             cancel, session/update event stream,
                             request_permission answer channel (seat single
                             slot, reusing SeatHoldGate semantics).
  acp_agent_translator.dart  Per-agent protocol-quirk absorption interface.
                             Gemini's cancel-error translation and flag
                             fallback live in its implementation, injected per
                             CliTool — adapter quirks never leak into the
                             mechanics layer.
  acp_frame_logger.dart      Bidirectional frame ring-buffer logger
                             (in/out/stderr, 200-entry backlog), with API-key
                             redaction.

services/cli/registry/capabilities/
  acp_capability.dart        Interface: launchArgs(env), ACP flag probing
                             declaration, translator instance, auth env.

services/cli/gemini/         ← Gemini declaration layer
  gemini_cli_tool.dart       CliToolDefinition registration (executable /
                             installer / acp capabilities).
  capabilities/acp.dart      `gemini --acp` launch, `--experimental-acp`
                             fallback probing, GEMINI_API_KEY env assembly,
                             GeminiAcpTranslator.
```

Key seams (extensibility contract):

- `AcpTransport` is the reserved seam for remote. Phase 2 adds
  `SshExecTransport` (`SshMemberSession` gains `openExec` — no PTY);
  everything below `AcpConnection` stays untouched.
- `AcpAgentTranslator` is the reserved seam for adapter quirks. Future
  claude/codex adapter integrations declare their own translators in their
  own capability files — no `if (cli == …)` anywhere.
- One process = one isolated env = one sessionToolDir domain. No process
  pooling across sessions (env is process-scoped; pooling would break
  config isolation).

## Session model

Gemini ACP session is a new terminal-less session kind, parallel to
terminal sessions:

- `CliTool` enum gains a sixth value `gemini` (update the doc comment list).
- Launch pipeline takes a gemini branch: `AcpSessionRuntime` attaches to
  `ChatTab` directly. It does NOT go through `session_shell_connector` /
  `memberShells`; chat center view is the only view (no live-terminal
  toggle for this session kind). The chat-vs-terminal decoupling already
  present in `ChatTab` is what makes this a branch, not a rewrite.
- Config isolation applies unchanged: gemini config/cache env points at the
  session's `sessionToolDir` (DefaultCliConfigLayout slot via
  NoopCliSessionCapability-style layout); `GEMINI_API_KEY` injected via the
  existing credential injection system.
- Auth is key-only in this phase. No OAuth flow; guidance copy points
  users to `gemini /auth` in an external terminal if they prefer OAuth.
- Client capabilities advertised in initialize: `fs/*` and `terminal/*`
  are false (isolation boundary stays closed). MCP tools registered during
  initialize: none in this phase.
- Session modes / config options from negotiation are recorded but no
  mode-switching UI ships.

`AcpSessionRuntime` responsibilities:

- **Start:** resolve/auto-install gemini (CliExecutableCapability) →
  AcpConnection(ProcessTransport, GeminiAcpTranslator) → initialize →
  session/new (cwd = workspace root).
- **Input:** chat composer → session/prompt.
- **Output:** session/update message chunks and tool calls map into the
  existing chat message model (thought blocks → collapsed style, tool
  calls → tool card components, mapped through the shared tool-category
  model).
- **Permission:** session/request_permission → existing
  `AgentPermissionRequest` card; answer → ACP outcome; agent-side
  always-allow options surface as optionId echo.
- **State:** stop reason drives the member idle/running state.
- **End:** session close → connection close with process-tree cleanup
  (SIGTERM → 5s timeout SIGKILL, process-group sweep).

Persistence: record the session/update stream into the app-side message
table (single source, works identically for every future ACP CLI). Do not
read Gemini's own on-disk transcript. `session/load` resume UI is
explicitly not shipped even when negotiated (later phase).

## Error handling

| Failure | Handling |
|---|---|
| Gemini not installed / probe fails | Auto-install via npm installer channel; install failure → l10n user error + manual guidance |
| `--acp` unsupported (old version) | Probe `--acp` first, fall back to `--experimental-acp`; both fail → explicit version-message, never a silent failure |
| initialize handshake timeout | Error report auto-attaches the frame log |
| InternalError + "aborted" text during prompt | GeminiAcpTranslator maps to Cancelled stop reason (mirrors Zed's workaround for gemini-cli#6656) |
| Agent process crash/exit | Inline system message in chat (with exit code) + session marked ended; no global error dialog |
| User cancel | session/cancel notification; keep accepting trailing tool-call updates (protocol requirement) before the cancelled stop reason |
| Process leftover | SIGTERM → 5s SIGKILL sweep |
| JSON-RPC protocol errors (non-InternalError) | Surface code + data as-is; frame log available |

## Logging

`AcpFrameLogger` records every in/out frame plus stderr into a 200-entry
ring buffer and AppLogger disk output, with credential redaction. A
developer entry point to view the buffer ships in this phase (Zed's
`dev: open acp logs` pattern). This is mandatory, not optional: with no
terminal fallback view, the frame log is the only diagnostic surface when
an agent stalls.

## Testing

Per CODE_QUALITY injection-mock conventions:

- **Unit (fast inner loop):** frame logger ring buffer + redaction;
  GeminiAcpTranslator aborted-error translation matrix; NDJSON framing
  across chunk boundaries; stderr-never-pollutes-stdout; flag probe
  decision table; env assembly (sessionToolDir isolation + key injection).
- **Integration (acpd_test in-memory transport pairs):** AcpConnection
  lifecycle (handshake, capability cache, disconnect); AcpSession
  prompt → update stream → stop reason full chain against a mock agent;
  request_permission → card → outcome timing (including cancel race);
  process cleanup SIGTERM/SIGKILL paths with real subprocesses (not
  mocked).
- **Acceptance (manual, desktop-local):** real `gemini --acp` —
  conversation, tool cards, permission card, cancel, crash copy.

acpd is vendored as a git submodule; upgrades are ref swaps. If upstream
breaks, patches land on a fork branch and the submodule points at the
fork.

## Out of scope (tracked follow-ups)

- SSH remote ACP transport (`SshExecTransport` + `SshMemberSession.openExec`)
- TeamBus / roster integration for ACP members (session/update → TeamBus
  event mapping)
- claude / codex adapter ACP capabilities; opencode native `opencode acp`
- OAuth login flow; fs/* and terminal/* client capabilities
- session/load resume UI; session mode switching
- ACP registry-driven agent discovery/installation
