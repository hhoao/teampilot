# Subagent Preview Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open Agent/Task tool rows into a stacked, read-only Chat overlay that shows inflated subagent transcripts (side JSONL when present, else tool result), refreshed with parent history reloads.

**Architecture:** After each History parse, host `SubagentAttachmentInflater` builds `toolCallId → AiSubagentAttachment` (Claude `subagents/agent-*.jsonl` preferred; else synthetic result). Index lives on `AiHistorySeat`. UI adds `AiToolSubagentActions` + tappable Agent/Task chrome + `SubagentPreviewScaffold`. `SubagentPreviewController` owns a `toolCallId` stack; overlay covers the full Chat body (hides parent compose) while non-empty.

**Tech Stack:** Dart / Flutter; `ai_message_core`, `ai_message_ui`; TeamPilot `AiHistoryLoader` / `AiHistorySeat` / `session_chat_view`.

**Spec:** `docs/superpowers/specs/2026-07-28-subagent-preview-overlay-design.md`

> **Superseded (tool names):** The v1 `Agent`/`Task` lock below is replaced by per-CLI `AiHistoryCapability.subagentToolNames` and host-injected `isSubagentTool` — see `2026-07-28-multi-cli-subagent-side-resolvers` plan.

### Plan locks (from spec review)

| Topic | Lock |
|-------|------|
| Tool names (v1) | Case-insensitive exact: `Agent`, `Task` only (no extra aliases until discovered) |
| Depth limit | `8`. At max depth: still create **tool-result degrade** attachment for Agent/Task parts; **do not recurse** into those messages |
| Overlay chrome | Covers **entire** Chat body (thread + parent compose). Parent compose hidden while stack non-empty |
| Inflate placement | Host inflater with workspace `Filesystem`; called from `AiHistoryLoader` after parse (cache stores messages **and** attachments) |
| Claude side match | **Primary:** `{stem}/subagents/agent-*.meta.json` → `toolUseId` == `toolCallId` → read sibling `agent-*.jsonl` (Orca-aligned). **Secondary:** `agent_id` / `agentId` from tool **args**. **Tertiary:** if `part.result` is a `Map` with `agentId`, use it. Do **not** rely on content-only `tool_result` text for id (current Claude parser drops event-level `toolUseResult`) |
| `parentTranscriptPath` | `AiHistoryWatchMeta.fromHints(bundle.hints).cacheTokenPaths` → first non-empty path. If null/empty → **skip side FS**, degrade-only inflate |
| Empty preview body | Inflate with **`messages: []`** when no side file and no usable result text. Host scaffold shows ARB `subagentPreviewEmpty`. Do **not** bake English placeholder into `AiTextPart` |
| Overlay stack safety | `ChangeNotifier` for push/pop/clear (notifies). `pruneToAvailable` is **silent** (mutates stack, no notify) and may run at start of build. Overlay reads `seat.subagentAttachments` inside a builder that rebuilds when seat state includes an **attachment epoch** (see Task 3). Never `!` on missing id; clear on seat change |
| Attachment rebuild signal | `AiHistoryState` gains `subagentAttachmentEpoch` (int, bumped whenever `_subagentAttachments` is replaced). Include in Equatable `props` so BlocBuilder rebuilds overlay on soft reload even if message count unchanged |

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/subagent_attachment.dart` | `AiSubagentAttachment`, source enum, `isAiSubagentToolName`, title/result helpers, empty synthetic message |
| `client/packages/ai_message_core/lib/ai_message_core.dart` | Export |
| `client/packages/ai_message_core/test/subagent_attachment_test.dart` | Name gate + helpers |
| `client/lib/services/session/subagent_side_transcript_path.dart` | Claude dir/path helpers (pure): `subagentsDirFor`, `agentTranscriptPath`, `agentMetaPath` |
| `client/lib/services/session/subagent_attachment_inflater.dart` | List meta → match toolUseId → read JSONL; args/result id fallback; recurse |
| `client/lib/services/session/ai_history_load_result.dart` | `{messages, subagentAttachments}` |
| `client/lib/services/session/ai_history_loader.dart` | Return `AiHistoryLoadResult`; cache both |
| `client/lib/cubits/ai_history_seat.dart` | Store/expose attachment index; prune hook for UI optional |
| `client/test/services/session/subagent_side_transcript_path_test.dart` | Path join |
| `client/test/services/session/subagent_attachment_inflater_test.dart` | Meta match / miss / depth / recurse |
| `client/packages/ai_message_ui/lib/src/tool_subagent_actions.dart` | Inherited actions scope |
| `client/packages/ai_message_ui/lib/src/parts/subagent_preview_scaffold.dart` | Back bar + read-only message list |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Agent/Task summary chrome + open |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export |
| `client/packages/ai_message_ui/lib/src/strings.dart` (+ en/zh if needed) | Preview chrome strings if package-local |
| `client/packages/ai_message_ui/test/tool_call_subagent_preview_test.dart` | Widget tests |
| `client/lib/pages/chat/subagent_preview_controller.dart` | Stack push/pop/prune |
| `client/test/pages/chat/subagent_preview_controller_test.dart` | Stack tests |
| `client/lib/pages/chat/session_chat_view.dart` | Wire actions + overlay; hide compose when open |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Toast + empty preview + back title |

---

### Task 1: Core attachment types + tool-name gate (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/subagent_attachment.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Create: `client/packages/ai_message_core/test/subagent_attachment_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('isAiSubagentToolName accepts Agent/Task case-insensitive', () {
    expect(isAiSubagentToolName('Agent'), isTrue);
    expect(isAiSubagentToolName('task'), isTrue);
    expect(isAiSubagentToolName('Bash'), isFalse);
    expect(isAiSubagentToolName('Read'), isFalse);
  });

  test('subagentTitleFromPart prefers description then prompt', () {
    expect(
      subagentTitleFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Agent',
        args: {'description': 'Explore auth', 'prompt': 'long…'},
      )),
      'Explore auth',
    );
    expect(
      subagentTitleFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Task',
        args: {'prompt': 'Do the thing'},
      )),
      'Do the thing',
    );
  });

  test('syntheticSubagentMessagesFromResult null/blank → empty list', () {
    expect(
      syntheticSubagentMessagesFromResult(toolCallId: '1', result: null),
      isEmpty,
    );
    expect(
      syntheticSubagentMessagesFromResult(toolCallId: '1', result: '  '),
      isEmpty,
    );
  });

  test('syntheticSubagentMessagesFromResult keeps non-empty result text', () {
    final msgs = syntheticSubagentMessagesFromResult(
      toolCallId: '1',
      result: 'done',
    );
    expect(msgs, hasLength(1));
    expect((msgs.single.parts.single as AiTextPart).text, 'done');
  });

  test('subagentAgentIdFromPart reads args then Map result', () {
    expect(
      subagentAgentIdFromPart(const AiToolCallPart(
        toolCallId: '1',
        toolName: 'Agent',
        args: {'agentId': 'from-args'},
      )),
      'from-args',
    );
    expect(
      subagentAgentIdFromPart(AiToolCallPart(
        toolCallId: '1',
        toolName: 'Task',
        result: {'agentId': 'from-result', 'status': 'completed'},
      )),
      'from-result',
    );
  });
}
```

- [ ] **Step 2: Run — expect FAIL (undefined symbols)**

```bash
cd client/packages/ai_message_core && dart test test/subagent_attachment_test.dart
```

- [ ] **Step 3: Implement minimal types + helpers**

```dart
// subagent_attachment.dart
enum AiSubagentAttachmentSource { sideTranscript, toolResult }

class AiSubagentAttachment {
  const AiSubagentAttachment({
    required this.toolCallId,
    required this.messages,
    required this.source,
    this.title,
    this.sidePath,
  });

  final String toolCallId;
  final List<AiMessage> messages;
  final AiSubagentAttachmentSource source;
  final String? title;
  final String? sidePath;
}

const kAiSubagentToolNames = {'agent', 'task'};

bool isAiSubagentToolName(String toolName) =>
    kAiSubagentToolNames.contains(toolName.trim().toLowerCase());

String? subagentTitleFromPart(AiToolCallPart part) { /* description > prompt; trim; null if empty */ }

String? subagentAgentIdFromPart(AiToolCallPart part) {
  // 1) args agent_id / agentId (string)
  // 2) if result is Map, agentId / agent_id
  // Do NOT parse free-form tool_result content strings for ids (unreliable).
}

List<AiMessage> syntheticSubagentMessagesFromResult({
  required String toolCallId,
  required Object? result,
}) {
  // null/blank → []; else one assistant AiTextPart with result string
}
```

Export from `ai_message_core.dart`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/subagent_attachment.dart \
  client/packages/ai_message_core/lib/ai_message_core.dart \
  client/packages/ai_message_core/test/subagent_attachment_test.dart
git commit -m "feat: add AI subagent attachment core types"
```

---

### Task 2: Side path + inflater (TDD)

**Files:**
- Create: `client/lib/services/session/subagent_side_transcript_path.dart`
- Create: `client/lib/services/session/subagent_attachment_inflater.dart`
- Create: `client/test/services/session/subagent_side_transcript_path_test.dart`
- Create: `client/test/services/session/subagent_attachment_inflater_test.dart`

- [ ] **Step 1: Path tests**

```dart
test('claude subagents dir + agent paths', () {
  // Use path package or fs.pathContext helpers consistently.
  expect(
    claudeSubagentsDirFor('/projects/enc/uuid.jsonl'),
    '/projects/enc/uuid/subagents',
  );
  expect(
    claudeSubagentTranscriptPath(subagentsDir: '/x/subagents', agentId: 'abc'),
    '/x/subagents/agent-abc.jsonl',
  );
  expect(
    claudeSubagentMetaPath(subagentsDir: '/x/subagents', agentId: 'abc'),
    '/x/subagents/agent-abc.meta.json',
  );
});
```

- [ ] **Step 2: Inflater tests with fake FS (Orca-shaped fixtures)**

Cover:

1. **Meta match (primary):** parent path set; write `agent-abc.meta.json` with `toolUseId: toolu_1` + `agent-abc.jsonl` with one user/assistant turn; messages contain Agent part `toolCallId: toolu_1` → attachment `source == sideTranscript`, `sidePath` ends with `agent-abc.jsonl`  
2. **Args id fallback:** no meta; args `agentId: abc` + jsonl present → side hit  
3. **Miss → degrade:** Agent part, no meta/jsonl → `toolResult` with result text  
4. **Nested:** side jsonl itself contains Agent + its own `…/agent-child.meta.json` under the **child transcript stem** → both ids in index  
5. **Depth 8:** deepest Agent still degrade-attached; no recursion past cap  

Use real `parseClaudeCompatibleJsonl` for side bytes when possible.

- [ ] **Step 3: Run tests — expect FAIL**

```bash
cd client && flutter test --exclude-tags integration \
  test/services/session/subagent_side_transcript_path_test.dart \
  test/services/session/subagent_attachment_inflater_test.dart
```

- [ ] **Step 4: Implement**

```dart
class SubagentAttachmentInflater {
  const SubagentAttachmentInflater({this.maxDepth = 8});
  final int maxDepth;

  Future<Map<String, AiSubagentAttachment>> inflate({
    required List<AiMessage> messages,
    required Filesystem fs,
    required String? parentTranscriptPath,
  }) async { … }
}
```

No `emptyPlaceholder` parameter. Blank degrade → `messages: []`.

Algorithm:
1. If `parentTranscriptPath` non-null, build `toolUseId → agentId` by listing `{stem}/subagents/`, reading each `agent-*.meta.json` (`toolUseId` field). Ignore bad JSON.
2. Walk parts; for each Agent/Task `toolCallId`:
   - Resolve agentId: meta map[toolCallId] → else `subagentAgentIdFromPart`
   - If agentId + parent path: read `agent-{id}.jsonl`; on success → `sideTranscript`
   - Else → `toolResult` via `syntheticSubagentMessagesFromResult` (may be `[]`)
3. Recurse into attachment.messages when `depth < maxDepth`, using `attachment.sidePath` as the parent transcript path for nested meta listing when present; if no `sidePath`, recurse degrade-only.
4. At `depth == maxDepth`: create degrade attachments for Agent/Task; **do not** recurse.

Also assert in tests: miss + blank result → index still contains `toolCallId` with `messages.isEmpty` (row remains openable).

- [ ] **Step 5: Run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/subagent_side_transcript_path.dart \
  client/lib/services/session/subagent_attachment_inflater.dart \
  client/test/services/session/subagent_side_transcript_path_test.dart \
  client/test/services/session/subagent_attachment_inflater_test.dart
git commit -m "feat: inflate subagent attachments from side transcripts"
```

---

### Task 3: Wire loader + seat index

**Files:**
- Create: `client/lib/services/session/ai_history_load_result.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Update any tests that mock `AiHistoryLoader.load` return type

- [ ] **Step 1: Introduce result type**

```dart
class AiHistoryLoadResult {
  const AiHistoryLoadResult({
    required this.messages,
    this.subagentAttachments = const {},
  });
  final List<AiMessage> messages;
  final Map<String, AiSubagentAttachment> subagentAttachments;
}
```

Change `load` to return `Future<AiHistoryLoadResult>`. Update `_AiHistoryCacheEntry` to store attachments. On cache hit, return both.

After `adapter.parse`, call inflater:

```dart
final watch = bundle == null
    ? null
    : AiHistoryWatchMeta.fromHints(bundle.hints);
final parentPath = () {
  final paths = watch?.cacheTokenPaths ?? const <String>[];
  for (final p in paths) {
    final t = p.trim();
    if (t.isNotEmpty) return t;
  }
  return null; // degrade-only; never invent a path from fragment basename
}();

final attachments = await const SubagentAttachmentInflater().inflate(
  messages: messages,
  fs: ctx.fs,
  parentTranscriptPath: parentPath,
);
// empty result → attachment.messages == [] ; UI uses ARB
```

**Empty copy lock:** When degrade has no usable result text, attachment uses `messages: []` (and `source: toolResult`). Do not pass/bake `kSubagentEmptyPlaceholderEn` into message text. Scaffold/host renders ARB `subagentPreviewEmpty` when `messages.isEmpty`. Toast/back labels always ARB.

- [ ] **Step 2: Seat stores map**

```dart
Map<String, AiSubagentAttachment> _subagentAttachments = {};
Map<String, AiSubagentAttachment> get subagentAttachments =>
    Map.unmodifiable(_subagentAttachments);

// AiHistoryState: add final int subagentAttachmentEpoch;
// bump when replacing _subagentAttachments; include in props.
```

On every successful load / soft reload path that sets `_cliMessages`, also set attachments from `AiHistoryLoadResult`. Clear on seat reset.

**Soft-reload lock:** if an early-return keeps prior `_cliMessages` (empty CLI / unchanged), also **keep** prior `_subagentAttachments` and **do not** bump epoch — never assign empty attachments then return. When messages+attachments are replaced together, bump `subagentAttachmentEpoch` and emit so BlocBuilder rebuilds.

Expose via `AiHistoryCubit` if UI reads focused seat — mirror pattern used for messages (check how thread gets messages today: likely `seat` methods). Grep `allMessages` / `visibleMessages` and expose `subagentAttachments` the same way.

- [ ] **Step 3: Fix compile + unit tests that call `load`**

```bash
cd client && flutter test --exclude-tags integration \
  test/cubits/ai_history_seat_test.dart \
  test/services/session/ai_history_loader_test.dart
```

(Adjust paths to whatever exists.)

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/session/ai_history_load_result.dart \
  client/lib/services/session/ai_history_loader.dart \
  client/lib/cubits/ai_history_seat.dart \
  client/test/
git commit -m "feat: attach subagent index to history seat loads"
```

---

### Task 4: UI actions + Agent/Task chrome (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/tool_subagent_actions.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`
- Create: `client/packages/ai_message_ui/test/tool_call_subagent_preview_test.dart`

- [ ] **Step 1: Widget tests (fail first)**

1. `Agent` with `onOpenSubagent` → tap summary title calls callback with `toolCallId`  
2. Chevron still expands args without opening  
3. `Bash` unchanged (legacy Used tool)  
4. File-target tools still prefer file chrome when resolver hits (Read) — Agent is not a file tool  

Priority in `build`: if `isAiSubagentToolName` && `onOpenSubagent != null` → subagent summary chrome; else if file target → file chrome; else legacy.

- [ ] **Step 2: Implement `AiToolSubagentActions`** (mirror `tool_file_actions.dart`)

```dart
class AiToolSubagentActions {
  const AiToolSubagentActions({this.onOpenSubagent});
  final Future<void> Function(String toolCallId)? onOpenSubagent;
  static AiToolSubagentActions of(BuildContext context) { … }
}
```

- [ ] **Step 3: Chrome** — `{toolName} {title?}` tappable; muted if cancelled; expand chevron separate.

- [ ] **Step 4: Tests PASS + commit**

```bash
cd client/packages/ai_message_ui && flutter test test/tool_call_subagent_preview_test.dart
git commit -m "feat: make Agent/Task tool rows open subagent preview"
```

---

### Task 5: Preview scaffold + stack controller (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/parts/subagent_preview_scaffold.dart`
- Create: `client/lib/pages/chat/subagent_preview_controller.dart`
- Create: `client/test/pages/chat/subagent_preview_controller_test.dart`
- Extend: `client/packages/ai_message_ui/test/tool_call_subagent_preview_test.dart`

- [ ] **Step 1: Controller tests**

```dart
test('push pop prune', () {
  final c = SubagentPreviewController();
  c.push('a');
  c.push('b');
  expect(c.stack, ['a', 'b']);
  c.pop();
  expect(c.stack, ['a']);
  c.pruneToAvailable({'b'}); // a missing → clear or drop to empty
  expect(c.stack, isEmpty);
  c.push('b');
  c.pruneToAvailable({'b'});
  expect(c.stack, ['b']);
});
```

`SubagentPreviewController extends ChangeNotifier`. `push` / `pop` / `clear` / `pruneToAvailable` call `notifyListeners`.

`pruneToAvailable`: walk from root; keep prefix while each id ∈ index; drop the rest.

- [ ] **Step 2: Scaffold widget**

```dart
class SubagentPreviewScaffold extends StatelessWidget {
  const SubagentPreviewScaffold({
    required this.title,
    required this.messages,
    required this.onBack,
    required this.emptyLabel, // ARB when messages.isEmpty
    this.threadBuilder, // prefer AiMessageView / same path as SessionHistoryThread
  });
}
```

Must **not** include a compose `TextField`. Back button calls `onBack`. If `messages.isEmpty`, show `emptyLabel` centered (no fake assistant bubble). Else render message list.

**Actions:** Scaffold does **not** invent scopes. Host wraps the scaffold (or its body) with the same `AiToolFileActionsScope` + `AiToolSubagentActionsScope` used on the main thread so nested Agent / Read-Write keep working.

- [ ] **Step 2b: Widget regression** — inside scaffold with both scopes, a `Read` file-target row still invokes `onOpenFile` when tapped (spec: file open works in preview).

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat: add subagent preview scaffold and stack controller"
```

---

### Task 6: Wire `session_chat_view` + l10n

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated locals)

- [ ] **Step 1: ARB keys**

- `subagentPreviewUnavailable` — toast when toolCallId missing  
- `subagentPreviewBack` — back affordance  
- `subagentPreviewEmpty` — zh「暂无子会话内容」/ en equivalent (host empty body)  
- `subagentPreviewTitleAgent(title)` / fallback `Agent`  

- [ ] **Step 2: State**

Hold `SubagentPreviewController` (`ChangeNotifier`) in `SessionChatView` State; `addListener` → `setState` (or `ListenableBuilder`).

**API lock:** `pruneToAvailable` / `push` / `pop` / `clear` / getter `stack` only.

**Notify lock:**
- `push` / `pop` / `clear` → `notifyListeners` (drive `ListenableBuilder` / `setState`).
- `pruneToAvailable` → **silent** (no notify). Safe to call at the start of build to drop stale ids before reading `stack`.

**Rebuild + live reload lock:**
- Chat body builder must depend on seat state **including** `subagentAttachmentEpoch` (BlocBuilder `buildWhen` / props). Soft reload that replaces attachments bumps epoch → overlay rebuilds `top.messages`.
- At start of that builder: `controller.pruneToAvailable(seat.subagentAttachments.keys);` (silent).
- `final top = stack.isEmpty ? null : seat.subagentAttachments[stack.last];` — show overlay iff `top != null`.
- On seat identity change (`didUpdateWidget` session/member): `controller.clear()`.

- [ ] **Step 3: Layout lock**

```dart
// Inside BlocBuilder listening to seat (incl. subagentAttachmentEpoch):
controller.pruneToAvailable(seat.subagentAttachments.keys); // silent
final stack = controller.stack;
final top = stack.isEmpty ? null : seat.subagentAttachments[stack.last];

ListenableBuilder(
  listenable: controller, // push/pop rebuild
  builder: (context, _) {
    // re-read stack/top after push/pop; prune again silently if desired
    return Column(
      children: [
        Expanded(
          child: AiToolFileActionsScope(
            actions: fileActions,
            child: AiToolSubagentActionsScope(
              actions: AiToolSubagentActions(
                onOpenSubagent: (id) async {
                  if (!seat.subagentAttachments.containsKey(id)) {
                    AppToast.show(… l10n.subagentPreviewUnavailable …);
                    return;
                  }
                  controller.push(id);
                },
              ),
              child: Stack(
                children: [
                  mainThread,
                  if (top != null)
                    Positioned.fill(
                      child: Material(
                        color: cs.surface,
                        child: SubagentPreviewScaffold(
                          title: …,
                          messages: top.messages,
                          emptyLabel: l10n.subagentPreviewEmpty,
                          onBack: controller.pop,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (top == null) composeFooter,
      ],
    );
  },
);
```

Note: after `push`/`pop`, `ListenableBuilder` rebuilds; recompute `top` **inside** the listenable builder from current `controller.stack` + latest seat attachments (don’t close over a stale `top` from outside).

`onOpenSubagent`: if index contains id → `push`; else AppToast warning.

Nested opens from scaffold use the same callback (inherited scope).

- [ ] **Step 4: Manual smoke checklist (document in commit body)**

1. Fixture / session with Agent + side JSONL → open overlay → see nested tools  
2. Agent without side file → see result text  
3. Back returns to parent; compose reappears  
4. Soft reload while open updates preview content  

- [ ] **Step 5: Analyze + targeted tests + commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration \
  test/pages/chat/subagent_preview_controller_test.dart \
  test/services/session/subagent_attachment_inflater_test.dart
# + package tests from earlier tasks
git commit -m "feat: wire subagent preview overlay in session chat"
```

---

### Task 7: Verification

- [ ] **Step 1: Run full package + host suite for this feature**

```bash
cd client/packages/ai_message_core && dart test test/subagent_attachment_test.dart
cd ../ai_message_ui && flutter test test/tool_call_subagent_preview_test.dart
cd ../.. && flutter test --exclude-tags integration \
  test/services/session/subagent_side_transcript_path_test.dart \
  test/services/session/subagent_attachment_inflater_test.dart \
  test/pages/chat/subagent_preview_controller_test.dart
```

- [ ] **Step 2: `flutter analyze --no-fatal-infos --no-fatal-warnings`** in `client/`

- [ ] **Step 3: Confirm non-goals untouched** — no session tab API, no Agent allowlist change in personal launch, no `subagents/` watch meta expansion (parent watch only)

---

## Execution notes

- Follow TDD order inside each task; do not skip “fail first” for pure/new APIs.
- Prefer `@superpowers:subagent-driven-development` with one task per subagent.
- If `AiHistoryLoader.load` signature churn is large, keep a deprecated private wrapper only inside the same PR if tests need it — do not leave permanent dual APIs.
