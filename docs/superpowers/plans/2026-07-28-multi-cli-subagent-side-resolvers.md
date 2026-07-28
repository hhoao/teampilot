# Multi-CLI Subagent Side Resolvers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve Agent/Task-family side transcripts for all five launch CLIs via a first-class `AiHistoryCapability` (typed side handles, CLI-owned tool names, pluggable resolvers), without changing the subagent preview overlay chrome.

**Architecture:** Fold today’s `kAiHistoryProviders` map into `AiHistoryCapability` on each `CliToolDefinition`. Inflater becomes orchestration only (name gate + depth + degrade + recurse). Claude/flashskyai share `ClaudeCompatibleSideResolver`; Cursor/Codex/OpenCode each get a strict resolver. `AiSubagentAttachment` stores `SubagentSideHandle?`; UI prefers seat-injected `isSubagentTool`.

**Tech Stack:** Dart / Flutter; `ai_message_core`, `ai_message_ui`; `CliToolRegistry` + history capabilities; `AiHistoryLoader` / `SessionHistoryContext`.

**Spec:** `docs/superpowers/specs/2026-07-28-multi-cli-subagent-side-resolvers-design.md`  
**Overlay (UI normative):** `docs/superpowers/specs/2026-07-28-subagent-preview-overlay-design.md`

### Plan locks (from spec)

| Topic | Lock |
|-------|------|
| Capability | Every launch CLI exposes `AiHistoryCapability` (locate + adapter + `subagentToolNames` + `subagentSideResolver`) |
| Policy C | Claude + flashskyai → shared Claude-compatible resolver; Cursor/Codex/OpenCode strict (never probe `subagents/`) |
| Tool names | Owned by capability; core union fallback = `{agent, task, spawn_agent}` (case-insensitive) |
| Handle | `AiSubagentAttachment.handle` is `SubagentSideHandle?`; `sidePath` derived for file handles only |
| Root path | Loader passes `rootTranscriptPath` from watch `cacheTokenPaths` first non-empty; file resolvers treat null `parentHandle` as `SubagentFileHandle(rootTranscriptPath)` when usable |
| Depth | Unchanged: `8`; at max depth degrade, no recurse |
| Map retirement | End state: production loader/locator use registry capability only; delete or test-only `kAiHistoryProviders` |
| Extensibility | New CLI = implement/wire `AiHistoryCapability` on that tool def — no inflater/`AiHistoryLoader` CLI `switch` |

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/subagent_attachment.dart` | `SubagentSideHandle`, attachment.`handle`, union tool-name fallback + helpers |
| `client/packages/ai_message_core/test/subagent_attachment_test.dart` | Handle + `spawn_agent` + existing helpers |
| `client/lib/services/cli/registry/capabilities/ai_history_capability.dart` | `AiHistoryCapability` interface |
| `client/lib/services/cli/registry/capabilities/history/subagent_side_resolver.dart` | `SubagentSideResolver` + `SubagentSideResolveResult` |
| `client/lib/services/cli/registry/capabilities/history/claude_compatible_side_resolver.dart` | Shared Claude/flashskyai side resolve |
| `client/lib/services/cli/registry/capabilities/history/cursor_side_resolver.dart` | Strict Cursor sibling resolve |
| `client/lib/services/cli/registry/capabilities/history/codex_side_resolver.dart` | Strict Codex `spawn_agent` resolve |
| `client/lib/services/cli/registry/capabilities/history/opencode_side_resolver.dart` | Strict OpenCode child session resolve |
| `client/lib/services/cli/registry/capabilities/history/*_ai_history_capability.dart` | Per-CLI capability bindings (or colocated in tool defs) |
| `client/lib/services/cli/registry/capabilities/history/opencode_ai_transcript.dart` | Export locate-by-`sessionId` for child sessions |
| `client/lib/services/cli/registry/tools/*_cli_tool.dart` | Register `AiHistoryCapability` on each tool |
| `client/lib/services/session/subagent_attachment_inflater.dart` | Capability-driven orchestration only |
| `client/lib/services/session/subagent_side_transcript_path.dart` | Keep Claude path helpers; used by compatible resolver |
| `client/lib/services/session/ai_history_locator.dart` | Locate via registry capability |
| `client/lib/services/session/ai_history_loader.dart` | Adapter + inflate via capability; pass `rootTranscriptPath` |
| `client/lib/services/session/ai_history_providers.dart` | Remove production map (or shrink to test helper) |
| `client/packages/ai_message_ui/lib/src/tool_subagent_actions.dart` | Optional `isSubagentTool` |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Prefer injected predicate |
| `client/lib/pages/chat/session_chat_view.dart` | Inject seat CLI `subagentToolNames` predicate |
| Tests under `client/test/services/…` and package tests | Per-resolver + inflater + loader + UI |

---

### Task 1: Core `SubagentSideHandle` + attachment + `spawn_agent` union

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/subagent_attachment.dart`
- Modify: `client/packages/ai_message_core/test/subagent_attachment_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('isAiSubagentToolName accepts spawn_agent', () {
  expect(isAiSubagentToolName('spawn_agent'), isTrue);
  expect(isAiSubagentToolName('Spawn_Agent'), isTrue);
});

test('AiSubagentAttachment stores typed handle', () {
  const file = SubagentFileHandle('/tmp/a.jsonl');
  const att = AiSubagentAttachment(
    toolCallId: '1',
    messages: [],
    source: AiSubagentAttachmentSource.sideTranscript,
    handle: file,
  );
  expect(att.handle, same(file));
  expect(att.sidePath, '/tmp/a.jsonl');

  const session = AiSubagentAttachment(
    toolCallId: '2',
    messages: [],
    source: AiSubagentAttachmentSource.sideTranscript,
    handle: SubagentSessionHandle('ses_x'),
  );
  expect(session.sidePath, isNull);
});
```

- [ ] **Step 2: Run test — expect FAIL** (missing types / `spawn_agent`)

Run: `cd client/packages/ai_message_core && dart test test/subagent_attachment_test.dart`

- [ ] **Step 3: Implement**

In `subagent_attachment.dart`:

```dart
sealed class SubagentSideHandle {
  const SubagentSideHandle();
}

final class SubagentFileHandle extends SubagentSideHandle {
  const SubagentFileHandle(this.path);
  final String path;
}

final class SubagentSessionHandle extends SubagentSideHandle {
  const SubagentSessionHandle(this.sessionId);
  final String sessionId;
}

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.handle,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final SubagentSideHandle? handle;

  /// File-handle path for debug/compat; null for session handles.
  String? get sidePath {
    final h = handle;
    if (h is SubagentFileHandle) return h.path;
    return null;
  }
}

const kAiSubagentToolNames = {'agent', 'task', 'spawn_agent'};
```

Keep constructor backward-compat during migration: **replace** the `sidePath`
field with a getter derived from `handle` (do **not** keep both a deprecated
`sidePath` constructor parameter and a `sidePath` getter). Update all
`sidePath:` constructions to `handle: SubagentFileHandle(...)` in the same
change set / follow-up tasks as call sites break.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/subagent_attachment.dart \
  client/packages/ai_message_core/test/subagent_attachment_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_core): typed subagent side handles and spawn_agent alias

EOF
)"
```

---

### Task 2: `AiHistoryCapability` + resolver contracts

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/ai_history_capability.dart`
- Create: `client/lib/services/cli/registry/capabilities/history/subagent_side_resolver.dart`
- Create: `client/test/services/cli/registry/ai_history_capability_test.dart` (optional smoke)

- [ ] **Step 1: Add interfaces**

```dart
// ai_history_capability.dart
import 'package:ai_message_core/ai_message_core.dart';

import '../../../session/session_history_context.dart';
import '../cli_capability.dart';
import 'history/subagent_side_resolver.dart';

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
}
```

```dart
// subagent_side_resolver.dart
import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';

class SubagentSideResolveResult {
  const SubagentSideResolveResult({
    required this.messages,
    required this.handle,
  });
  final List<AiMessage> messages;
  final SubagentSideHandle handle;
}

abstract interface class SubagentSideResolver {
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
  });
}

/// Always miss — temporary binder until Task 5–8.
final class NullSubagentSideResolver implements SubagentSideResolver {
  const NullSubagentSideResolver();
  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
  }) async => null;
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/ai_history_capability.dart \
  client/lib/services/cli/registry/capabilities/history/subagent_side_resolver.dart
git commit -m "$(cat <<'EOF'
feat(cli): add AiHistoryCapability and subagent side resolver contracts

EOF
)"
```

---

### Task 3: Per-CLI history capabilities + wire into tool defs

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/claude_ai_history_capability.dart` (and flashskyai/codex/opencode/cursor siblings — or one file with five final classes)
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart` (+ flashskyai, codex, opencode, cursor)
- Prefer thin wrappers calling existing `locate*` + adapters; resolvers = `NullSubagentSideResolver` until later tasks (Claude/flashskyai still null here — Task 4 swaps them)

Example:

```dart
final class ClaudeAiHistoryCapability implements AiHistoryCapability {
  const ClaudeAiHistoryCapability({
    this.subagentSideResolver = const NullSubagentSideResolver(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateClaudeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;
}
```

| CLI | `subagentToolNames` |
|-----|---------------------|
| Claude | `{agent, task}` |
| flashskyai | `{agent, task}` |
| Cursor | `{agent, task}` |
| Codex | `{spawn_agent, agent, task}` |
| OpenCode | `{task}` |

Add each capability to the corresponding `capabilities => [...]` list.

- [ ] **Step 1: Implement five capabilities + register**

- [ ] **Step 2: Smoke** — `CliToolRegistry.builtIn().capability<AiHistoryCapability>(CliTool.claude)` non-null for all five

```dart
// client/test/services/cli/registry/ai_history_capability_wiring_test.dart
test('all launch CLIs expose AiHistoryCapability', () {
  final r = CliToolRegistry.builtIn();
  for (final cli in [
    CliTool.claude,
    CliTool.flashskyai,
    CliTool.codex,
    CliTool.opencode,
    CliTool.cursor,
  ]) {
    expect(r.capability<AiHistoryCapability>(cli), isNotNull, reason: '$cli');
  }
});
```

Run: `cd client && flutter test test/services/cli/registry/ai_history_capability_wiring_test.dart`

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(cli): wire AiHistoryCapability onto all launch CLIs

EOF
)"
```

---

### Task 4: Migrate locator + loader **locate/parse** onto capability

**Files:**
- Modify: `client/lib/services/session/ai_history_locator.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/app/app_shell.dart` — pass the existing `cliToolRegistry` into `AiHistoryLoader` / locator when ctors gain `registry:`
- Modify: `client/test/services/session/ai_history_loader_test.dart`
- Modify tests that inject `adapters:` / `providers:` (grep): e.g.
  `ai_history_cubit_test.dart`, `ai_history_seat_isolation_test.dart`,
  `ai_history_live_refresh_controller_test.dart`,
  `session_history_registration_test.dart` (partial — full map removal in Task 11)

**Order note:** Do **not** change `SubagentAttachmentInflater.inflate` signature in
this task. Keep calling the **current** API
(`messages` / `fs` / `parentTranscriptPath`) so Task 4 compiles before Task 5.

- [ ] **Step 1: Locator uses registry**

```dart
class AiHistoryLocator {
  AiHistoryLocator({CliToolRegistry? registry})
      : _registry = registry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _registry;

  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    final cap = _registry.capability<AiHistoryCapability>(cli);
    if (cap == null) {
      throw StateError('AiHistoryCapability missing for launch CLI $cli');
    }
    return cap.locate(ctx);
  }
}
```

- [ ] **Step 2: Loader uses capability adapter; inflate stays old API**

```dart
final cap = _registry.capability<AiHistoryCapability>(cli);
if (cap == null) {
  throw StateError('AiHistoryCapability missing for launch CLI $cli');
}
final messages = bundle == null
    ? const <AiMessage>[]
    : await cap.adapter.parse(bundle);

// UNCHANGED inflater API until Task 5:
final attachments = await const SubagentAttachmentInflater().inflate(
  messages: messages,
  fs: ctx.fs,
  parentTranscriptPath: parentPath,
);
```

Remove `_adapters` map from loader ctor (or keep only as deprecated test path
that builds a tiny registry). Prefer tests registering a fake
`AiHistoryCapability` on `CliToolRegistry()`.

Wire `app_shell.dart` `AiHistoryLoader(...)` with `registry: cliToolRegistry`.

- [ ] **Step 3: Run loader + related tests**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(history): resolve locate/parse via AiHistoryCapability

EOF
)"
```

---

### Task 5: Claude-compatible side resolver + inflater orchestration (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/claude_compatible_side_resolver.dart`
- Modify: `client/lib/services/session/subagent_attachment_inflater.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart` — switch inflate call to new signature **in this task**
- Modify: `client/test/services/session/subagent_attachment_inflater_test.dart`
- Modify: Claude + flashskyai history capabilities to use shared resolver
- Keep: `subagent_side_transcript_path.dart` (used by resolver)

- [ ] **Step 1: Update inflater tests to pass a capability stub**

```dart
class _Cap implements AiHistoryCapability {
  _Cap(this.subagentSideResolver);
  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) async => null;
  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();
  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};
  @override
  final SubagentSideResolver subagentSideResolver;
}

// inflate call:
await SubagentAttachmentInflater().inflate(
  messages: messages,
  ctx: SessionHistoryContext(/* fs + minimal fields */),
  capability: _Cap(const ClaudeCompatibleSideResolver()),
  rootTranscriptPath: parentPath,
);
```

Port existing meta-hit / miss / depth / recurse cases. Recurse must use `attachment.handle` as next `parentHandle` (file path), not string-only.

- [ ] **Step 2: Run — FAIL on new API**

- [ ] **Step 3: Implement `ClaudeCompatibleSideResolver`**

Move meta map + JSONL read/parse from current inflater `_attachOne` / `_loadMetaMap`. Effective parent file:

```dart
String? parentPath(SubagentSideHandle? parentHandle, String? rootTranscriptPath) {
  if (parentHandle is SubagentFileHandle) return parentHandle.path;
  final root = rootTranscriptPath?.trim();
  if (root != null && root.isNotEmpty) return root;
  return null;
}
```

On success return `SubagentSideResolveResult(messages: …, handle: SubagentFileHandle(sidePath))`.

- [ ] **Step 4: Rewrite inflater**

```dart
Future<Map<String, AiSubagentAttachment>> inflate({
  required List<AiMessage> messages,
  required SessionHistoryContext ctx,
  required AiHistoryCapability capability,
  required String? rootTranscriptPath,
  int depth = 0, // or private walk
}) async { … }

// gate:
final name = part.toolName.trim().toLowerCase();
if (!capability.subagentToolNames.contains(name)) continue;

final resolved = await capability.subagentSideResolver.resolve(
  part: part,
  ctx: ctx,
  parentHandle: parentHandle,
  rootTranscriptPath: rootTranscriptPath,
);
final attachment = resolved == null
    ? _degrade(part, title)
    : AiSubagentAttachment(
        toolCallId: part.toolCallId,
        messages: resolved.messages,
        source: AiSubagentAttachmentSource.sideTranscript,
        title: title,
        handle: resolved.handle,
      );
// recurse with parentHandle: attachment.handle
```

Name gate uses **capability set**, not only `isAiSubagentToolName`.

- [ ] **Step 5: Update loader inflate call to the new signature**

```dart
final attachments = await SubagentAttachmentInflater().inflate(
  messages: messages,
  ctx: ctx,
  capability: cap,
  rootTranscriptPath: parentPath,
);
```

Re-run `ai_history_loader_test.dart` after this step.

- [ ] **Step 6: Point Claude + flashskyai capabilities at `const ClaudeCompatibleSideResolver()`**

- [ ] **Step 7: Tests PASS**

Run: `cd client && flutter test test/services/session/subagent_attachment_inflater_test.dart test/services/session/ai_history_loader_test.dart`

- [ ] **Step 8: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): Claude-compatible subagent side resolver and capability inflater

EOF
)"
```

---

### Task 6: Cursor strict side resolver (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/cursor_side_resolver.dart`
- Create: `client/test/services/cli/registry/capabilities/history/cursor_side_resolver_test.dart`
- Modify: Cursor `AiHistoryCapability` to use it

- [ ] **Step 1: Failing tests (memory FS fixtures)**

Cover:
1. `args.resume` / UUID → `{root}/{uuid}/{uuid}.jsonl` hit
2. Prompt heuristic: sibling first user matches normalized prompt; excludes parent stem
3. Never reads `…/subagents/…` even if present next to parent
4. Miss → null

Normalize helper: strip leading timestamp lines / unwrap `user_query` if present (match real Cursor Task shapes from research).

Derive `agent-transcripts` root from parent file handle:
- parent `…/agent-transcripts/{stem}/{stem}.jsonl` → root = `…/agent-transcripts`

- [ ] **Step 2: Implement resolver** — parse with `CursorAiTranscriptAdapter` on a one-fragment bundle (or shared JSONL parse path Cursor already uses)

- [ ] **Step 3: Wire into Cursor capability; tests PASS

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): Cursor subagent side transcript resolver

EOF
)"
```

---

### Task 7: Codex strict side resolver (TDD)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/codex_side_resolver.dart`
- Create: `client/test/services/cli/registry/capabilities/history/codex_side_resolver_test.dart`
- Modify: Codex capability
- Optionally export rollout-id regex helper from `codex_ai_transcript.dart` for reuse (prefer package-private top-level in same library / shared private in new file importing same pattern)

- [ ] **Step 1: Failing tests**

1. `spawn_agent` result/args `agent_id` finds `rollout-*-{agent_id}.jsonl` under `$CODEX_HOME/sessions`
2. Missing id / missing file → null
3. Does not open Claude `subagents/`

Use `ctx.env['CODEX_HOME']` like `locateCodexTranscript`.

- [ ] **Step 2: Implement + wire + PASS**

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): Codex spawn_agent side rollout resolver

EOF
)"
```

---

### Task 8: OpenCode strict side resolver (TDD)

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/history/opencode_ai_transcript.dart` — public `locateOpencodeTranscriptForSession(ctx, sessionId)` (extract from existing sqlite/json paths)
- Create: `client/lib/services/cli/registry/capabilities/history/opencode_side_resolver.dart`
- Create: `client/test/services/cli/registry/capabilities/history/opencode_side_resolver_test.dart`
- Modify: OpenCode capability

- [ ] **Step 1: Extract session-scoped locate**

Ensure child load uses same dataDir resolution as parent `locateOpencodeTranscript`, but with explicit `sessionId` (not only `ctx.persistedNativeId`).

- [ ] **Step 2: Failing tests**

1. Extract `sessionId` from `part.result` map/`metadata` or output `<task id="ses_…">`
2. Locate+parse child → messages; `handle` is `SubagentSessionHandle`
3. Nested: parentHandle session + another task → second child
4. Missing child → null
5. No Claude path access

For unit tests, prefer JSON storage fixtures under a temp dataDir if sqlite harness is heavy; mirror fragment layout `message/` + `part/` that `OpencodeAiTranscriptAdapter` already parses.

When `session.parent_id` is available and mismatches the parent session id from
`ctx` / `parentHandle`, log a diagnostic (`appLogger.w`) but still prefer the
explicit tool `sessionId`.

- [ ] **Step 3: Implement link extract**

```dart
String? opencodeChildSessionId(AiToolCallPart part) {
  // result Map → metadata.sessionId / sessionId
  // else RegExp on result string: <task id="(ses_[^"]+)">
}
```

- [ ] **Step 4: Wire + PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): OpenCode task child-session side resolver

EOF
)"
```

---

### Task 9: UI capability tool-name predicate

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/tool_subagent_actions.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/test/tool_call_subagent_preview_test.dart`

- [ ] **Step 1: Extend actions**

```dart
class AiToolSubagentActions {
  const AiToolSubagentActions({
    this.onOpenSubagent,
    this.isSubagentTool,
  });

  final Future<void> Function(String toolCallId)? onOpenSubagent;
  final bool Function(String toolName)? isSubagentTool;
}
```

In `tool_call_part_view.dart`:

```dart
final isSub =
    (subagentActions.isSubagentTool?.call(part.toolName) ??
        isAiSubagentToolName(part.toolName)) &&
    onOpenSubagent != null;
```

- [ ] **Step 2: Widget test** — with `isSubagentTool: (n) => n == 'spawn_agent'` and `onOpenSubagent`, row is tappable; without predicate, `spawn_agent` still works via core union fallback

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): inject isSubagentTool for CLI-owned names

EOF
)"
```

---

### Task 10: Host wire seat CLI predicate + loader inflate path

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: any remaining inflater call sites
- Fix compile breaks from `sidePath` → `handle`

- [ ] **Step 1: In `AiToolSubagentActions` construction**

Use existing `lockedCli` (or equivalent seat CLI already resolved in
`session_chat_view.dart` ~L990–L1029) — do not invent a parallel `seatCli`
alias.

```dart
final historyCap = registry.capability<AiHistoryCapability>(lockedCli);
AiToolSubagentActions(
  isSubagentTool: historyCap == null
      ? null
      : (name) => historyCap.subagentToolNames
          .contains(name.trim().toLowerCase()),
  onOpenSubagent: (id) async { … },
)
```

- [ ] **Step 2: `flutter analyze` on touched paths; fix attachment `sidePath` references (controller prune unaffected — still keyed by toolCallId)

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(chat): drive subagent tool gate from seat AiHistoryCapability

EOF
)"
```

---

### Task 11: Retire production `kAiHistoryProviders` + docs touch

**Files:**
- Modify or delete: `client/lib/services/session/ai_history_providers.dart`
- Grep purge: `kAiHistoryProviders`, `aiHistoryDefaultAdapters`
- Modify: `AGENTS.md` (one line under CLI registry / History: history is `AiHistoryCapability`)
- Update: `docs/superpowers/plans/2026-07-28-subagent-preview-overlay.md` plan-lock note — tool names superseded (optional short comment at top)

- [ ] **Step 1: Remove map; fix imports**

Explicitly update `session_history_registration_test.dart` (and any remaining
`kAiHistoryProviders` assertions) to assert
`registry.capability<AiHistoryCapability>(cli)` instead of the old map.

- [ ] **Step 2: Full verification**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/services/session/subagent_attachment_inflater_test.dart \
  test/services/session/ai_history_loader_test.dart \
  test/services/cli/registry/ \
  packages/ai_message_core/test/subagent_attachment_test.dart \
  packages/ai_message_ui/test/tool_call_subagent_preview_test.dart
```

Expected: no errors; all listed tests PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(history): retire kAiHistoryProviders in favor of AiHistoryCapability

EOF
)"
```

---

## Execution notes

- Prefer a worktree off `main` that already contains the v1 overlay (`SubagentAttachmentInflater`, preview UI).
- Do not expand overlay UX, side-file watchers, or TeamBus.
- When Codex/Cursor fixtures are thin, synthetic FS trees are enough — do not block on live CLI matrix.
- TDD order inside Tasks 5–8: write miss/hit tests before resolver bodies.

## Done when

- All five CLIs expose `AiHistoryCapability` with working locate/adapter.
- Claude/flashskyai side resolve via shared compatible resolver; Cursor/Codex/OpenCode via strict resolvers.
- Inflater has no Claude path joins; no production `kAiHistoryProviders`.
- UI opens `spawn_agent` / OpenCode `task` when seat capability says so.
- Overlay still read-only, stacked, parent-history refresh only.
