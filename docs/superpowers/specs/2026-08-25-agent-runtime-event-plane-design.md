# Agent Runtime Event Plane Design

**Status:** Proposed

## Goal

Replace the current direct coupling between CLI hook HTTP handling, terminal
screen probing, and prompt-delivery retries with one session-scoped runtime
event plane. The first consumer is reliable Codex prompt delivery: a hook
confirmation must prevent every pending or queued retry from writing another
submit key.

This is an intentional replacement design. It does not preserve the current
`AgentStatusHttpHandler -> PromptSubmitAckTracker -> TabMemberPtyDelivery`
integration or its public constructors.

## Non-goals

- Claiming protocol-level exactly-once delivery when a CLI hook cannot return
  a client-supplied delivery identifier.
- Changing a CLI's native hook protocol.
- Rebuilding user-authored hooks or extension hook configuration. Those remain
  resource-provisioning concerns; this design owns TeamPilot runtime events.

## Architecture

```text
CLI hook / plugin payload
  -> AgentEventGateway
  -> CliRuntimeEventAdapter
  -> RuntimeEventJournal (durable append-only records)
  -> SeatEventStream (ordered per session + member)
  -> Runtime projections and state machines
       - PromptDeliveryCoordinator
       - AgentAttentionProjection
       - AskUserQuestionCoordinator
       - ExitPlanModeCoordinator
       - History / presence projections
```

### Event gateway

`AgentEventGateway` is the sole app-wide HTTP ingress for agent runtime
events. It authenticates the existing session/bus credentials, resolves the
seat's CLI, delegates payload parsing to that CLI's capability, writes the
normalized record to the journal, then publishes it to the seat stream. It
does not mutate UI cubits or terminal input directly.

The normalized envelope contains:

- immutable `eventId` and `occurredAt`;
- `sessionId`, `memberId`, and `cli`;
- event type (for example `userPromptSubmitted`, `permissionRequested`, or
  `toolStarted`);
- a typed normalized payload plus retained raw metadata for diagnostics;
- an optional CLI-native correlation id.

Each `(sessionId, memberId)` stream is serialized. Ordering across different
seats is deliberately unspecified.

### CLI runtime-event capability

Replace `ChatInteractionCapability.normalize` as the runtime hook surface with
`RuntimeEventCapability`. A CLI capability declares:

- supported runtime event kinds;
- hook installation and authentication requirements;
- conversion of raw hook/plugin payloads to normalized events;
- the prompt-confirmation correlation strength it can provide;
- full-screen input confirmation semantics and fallback policy.

No caller switches on `CliTool`. Codex, Claude-family, OpenCode, and Cursor
adapters can expose different native payload grammars while consumers receive
the same envelope type.

### Durable journal and projections

`RuntimeEventJournal` appends envelope records before publication and supports
reading a seat stream from a sequence offset. It is stored under the session
runtime directory and is owned by the session lifecycle: opening replays it to
rebuild projections; disposing a session closes the stream without deleting
the journal.

Projection state that affects writes is also durable. In particular, prompt
delivery records survive an application restart so recovery can present
`submittedUnknown` rather than blindly re-send user content.

## Prompt delivery state machine

`PromptDeliveryCoordinator` is the sole owner of automated user-input writes.
It accepts a `PromptDeliveryRequest` and creates a durable `deliveryId`.
Commands sent to the PTY carry that id; neither the retry queue nor the
full-screen input channel may write a command without checking the live state
for its id immediately before the write.

```text
created -> waitingForInputSurface -> staged -> submitIssued
submitIssued -> confirmed
submitIssued -> submittedUnknown
submitIssued -> failed
```

- `confirmed` is terminal and atomically invalidates every queued write and
  retry for the delivery.
- `submittedUnknown` is used when neither a reliable hook confirmation nor a
  CLI-specific fallback can prove the outcome before the deadline. The UI
  exposes recovery; automatic re-paste is forbidden from this state.
- `failed` means the process/input surface disappeared before a submit could
  have been issued.

For Codex, the primary confirmation is `userPromptSubmitted` from its hook.
Screen-grid observation is only a pre-confirmation fallback to determine
whether a first CR can be issued. It must never schedule a re-paste after the
delivery entered `confirmed` or `submittedUnknown`.

### Correlation

When a CLI includes an application-supplied delivery id in its hook payload,
the event confirms exactly that delivery. For a CLI such as current Codex that
does not, the coordinator enforces at most one unconfirmed delivery per seat
and matches the hook event against the active delivery's normalized prompt and
submission epoch. This gives reliable user-visible at-most-once delivery but
is explicitly not distributed-protocol exactly-once.

The protocol-level upgrade path is defined now: adapters with native delivery
ids set `correlationStrength = exact`; adapters without them set
`serializedPromptEpoch`. Consumers do not change when Codex gains a native
correlation id.

### Cancellation fence

The write boundary is the correctness boundary. `TerminalInputCommandQueue`
serializes commands, but each command has a `canExecute` fence owned by the
delivery coordinator. An ACK that arrives while a CR is queued changes the
delivery state before the command runs; the queue then drops it. This closes
the current race where an ACK stops later retry scheduling but cannot stop a
previously queued CR.

## Error handling and recovery

- Duplicate hook delivery is harmless: journal de-duplicates by event id (or
  adapter-provided idempotency key) before publication; projections are
  idempotent by sequence number.
- An out-of-order confirmation is retained in the journal and applied when its
  delivery becomes visible during replay.
- Hook absence or timeout never causes unlimited CR retries. The coordinator
  transitions to `submittedUnknown` after its bounded policy.
- Session shutdown cancels in-memory work but preserves the delivery state.
  Reopening displays unresolved delivery rather than automatically submitting
  it again.

## Migration scope

Remove `PromptSubmitAckTracker`, the direct `promptAckTracker` dependency from
`AgentStatusHttpHandler`, and terminal-owned retry decisions. Replace the
current agent-status handler with the gateway and move attention/question/plan
handling into event-stream projections.

The existing HTTP endpoint, scripts, and CLI config writers are replaced at
the same time by the runtime-event capability's provisioning contract. No
compatibility facade is retained.

## Tests and acceptance criteria

Tests use a deterministic fake clock, fake journal, seat stream, and PTY
command queue. Required cases:

1. A Codex confirmation arriving after the first CR but before a queued retry
   prevents that retry from writing.
2. A confirmation arriving while a CR command waits in the serial queue drops
   the command at the execution fence.
3. Repeated hook events confirm only once and do not produce additional PTY
   writes.
4. A restart after `submitIssued` restores `submittedUnknown`; it never
   re-pastes automatically.
5. Two same-text sends on one seat are serialized and cannot cross-confirm.
6. Event adapters are tested independently from projections; projections are
   tested by replaying journal events.
7. A CLI adapter with an exact native delivery id confirms only that id.

Acceptance is met when a prompt injected once can create at most one Codex
user message under delayed terminal rendering, delayed hook delivery, duplicate
hook delivery, and application restart simulations. A missing confirmation
must surface an unresolved state rather than cause another automatic submit.
