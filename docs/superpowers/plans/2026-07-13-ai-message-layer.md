# AI Message Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SessionHistoryTurn` review with an assistant-ui-aligned `AiMessage` layer (`ai_message_core` + `ai_message_ui`) and in-app CLI adapters that parse transcripts into parts-based messages for a first-class History Thread UI.

**Architecture:** Pure-Dart `ai_message_core` owns models, ExternalStore runtime, and `AiTranscriptAdapter` interfaces. Flutter `ai_message_ui` renders Thread → Message → Parts. TeamPilot locates transcript bytes, implements per-CLI adapters, and binds the runtime in review; slim compose / PTY stay in the app. No `ai_message_adapters` package. No compatibility with old history types.

**Tech Stack:** Dart 3 / Flutter, `flutter_bloc`, existing CLI registry + `Filesystem`, `flutter_markdown_plus` (UI package), path packages under `client/packages/`.

**Spec:** [docs/superpowers/specs/2026-07-13-ai-message-layer-design.md](../specs/2026-07-13-ai-message-layer-design.md)

**Constraints:**
- No backward compatibility, shims, dual UIs, or feature flags.
- No live-tail / TeamPilot message DB / multi-member merge / TeamBus-in-thread.
- `ai_message_core` must stay Flutter-free (`Stream` notify, not `Listenable`).
- Full-parse then in-memory windowing for load-older (same UX as today).
- Keep mtime cache in the app loader (parity with `SessionHistoryLoader`).

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/pubspec.yaml` | Pure Dart package manifest |
| `client/packages/ai_message_core/lib/ai_message_core.dart` | Barrel export |
| `client/packages/ai_message_core/lib/src/message.dart` | `AiRole`, parts, `AiMessage`, `AiMessageStatus` |
| `client/packages/ai_message_core/lib/src/thread_message_like.dart` | Loose input + `normalizeThreadMessages` |
| `client/packages/ai_message_core/lib/src/runtime.dart` | `AiThreadStatus`, `AiThreadRuntime`, `ExternalStoreAiThreadRuntime` |
| `client/packages/ai_message_core/lib/src/transcript_adapter.dart` | `AiTranscriptFragment`, `AiTranscriptBundle`, `AiTranscriptAdapter` |
| `client/packages/ai_message_ui/pubspec.yaml` | Flutter UI package |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Barrel export |
| `client/packages/ai_message_ui/lib/src/theme.dart` | `AiMessageTheme` |
| `client/packages/ai_message_ui/lib/src/ai_thread.dart` | `AiThread` + status builders + load-older scroll hooks |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | Role layout |
| `client/packages/ai_message_ui/lib/src/ai_message_parts.dart` | Part dispatch + builders |
| `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | Streaming-safe markdown |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Collapsible tool card |
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Collapsed reasoning |
| `client/lib/services/cli/registry/capabilities/history/claude_ai_transcript.dart` | Locate helper + `ClaudeAiTranscriptAdapter` |
| `client/lib/services/cli/registry/capabilities/history/flashskyai_ai_transcript.dart` | Same for flashskyai |
| `client/lib/services/cli/registry/capabilities/history/codex_ai_transcript.dart` | Same for Codex |
| `client/lib/services/cli/registry/capabilities/history/opencode_ai_transcript.dart` | Same for OpenCode |
| `client/lib/services/cli/registry/capabilities/history/cursor_ai_transcript.dart` | Same for Cursor |
| `client/lib/services/session/ai_history_locator.dart` | CLI → locate bundle (uses per-CLI locate helpers) |
| `client/lib/services/session/ai_history_loader.dart` | Locate + parse + mtime cache → `List<AiMessage>` |
| `client/lib/cubits/ai_history_cubit.dart` | Owns `ExternalStoreAiThreadRuntime` + windowing |
| `client/lib/pages/chat/session_history_review.dart` | Host `AiThread` + slim compose (replace turn list) |
| Delete | `session_history_capability.dart` types, old `*_session_history.dart`, `session_history_turn_*`, old cubit/loader names after cutover |
| `client/pubspec.yaml` | Path deps on core + ui |
| Fixtures | Keep under `client/test/fixtures/session_history/`; update expectations to `AiMessage` |

---

### Task 1: Scaffold `ai_message_core` package

**Files:**
- Create: `client/packages/ai_message_core/pubspec.yaml`
- Create: `client/packages/ai_message_core/lib/ai_message_core.dart`
- Create: `client/packages/ai_message_core/analysis_options.yaml` (include root or minimal)
- Modify: `client/pubspec.yaml` — add path dependency

- [ ] **Step 1: Create package manifest (no Flutter)**

```yaml
name: ai_message_core
description: AI message model and ExternalStore thread runtime for TeamPilot.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dev_dependencies:
  test: ^1.25.0
```

- [ ] **Step 2: Empty barrel + path dep**

```dart
/// AI message core — models, runtime, transcript adapter interfaces.
library ai_message_core;
```

In `client/pubspec.yaml` under `dependencies:`:

```yaml
  ai_message_core:
    path: packages/ai_message_core
```

- [ ] **Step 3: Resolve packages**

Run: `cd client && flutter pub get`

Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add client/packages/ai_message_core client/pubspec.yaml client/pubspec.lock
git commit -m "chore: scaffold ai_message_core package"
```

---

### Task 2: Core message model + normalize (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/message.dart`
- Create: `client/packages/ai_message_core/lib/src/thread_message_like.dart`
- Create: `client/packages/ai_message_core/test/message_normalize_test.dart`
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart` — export src

- [ ] **Step 1: Write failing normalize test**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalize merges string content into AiTextPart', () {
    final messages = normalizeThreadMessages([
      const ThreadMessageLike(
        id: 'm1',
        role: AiRole.user,
        content: 'hello',
      ),
    ]);
    expect(messages, hasLength(1));
    expect(messages.single.role, AiRole.user);
    expect(messages.single.parts, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, 'hello');
    expect(messages.single.status, AiMessageStatus.complete);
  });

  test('normalize keeps tool-call parts on assistant messages', () {
    final messages = normalizeThreadMessages([
      ThreadMessageLike(
        id: 'a1',
        role: AiRole.assistant,
        content: [
          const AiTextPart(text: 'Using tool'),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Bash',
            args: {'cmd': 'ls'},
          ),
        ],
      ),
    ]);
    expect(messages.single.parts, hasLength(2));
    final tool = messages.single.parts[1] as AiToolCallPart;
    expect(tool.toolName, 'Bash');
    expect(tool.result, isNull);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client/packages/ai_message_core && dart test test/message_normalize_test.dart`

Expected: FAIL (library / types missing)

- [ ] **Step 3: Implement `message.dart` + `thread_message_like.dart`**

Implement exactly as in the spec (`AiRole`, sealed/`implements` parts, `AiMessage`, `AiMessageStatus`).

`ThreadMessageLike`:

```dart
class ThreadMessageLike {
  const ThreadMessageLike({
    required this.role,
    required this.content,
    this.id,
    this.createdAt,
    this.status = AiMessageStatus.complete,
  });

  final AiRole role;
  /// `String` or `List<AiMessagePart>`.
  final Object content;
  final String? id;
  final DateTime? createdAt;
  final AiMessageStatus status;
}

List<AiMessage> normalizeThreadMessages(List<ThreadMessageLike> input) {
  // For each: resolve id (given or 'msg_$i'); map String → [AiTextPart];
  // if content is List<AiMessagePart>, use as-is; skip empty text-only.
}
```

Export from barrel.

- [ ] **Step 4: Run test — expect PASS**

Run: `cd client/packages/ai_message_core && dart test test/message_normalize_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core
git commit -m "feat(ai_message_core): add AiMessage model and normalize"
```

---

### Task 3: ExternalStore runtime + adapter interfaces (TDD)

**Files:**
- Create: `client/packages/ai_message_core/lib/src/runtime.dart`
- Create: `client/packages/ai_message_core/lib/src/transcript_adapter.dart`
- Create: `client/packages/ai_message_core/test/external_store_runtime_test.dart`
- Modify: barrel exports

- [ ] **Step 1: Write failing runtime test**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('ExternalStore transitions loading → messages → idle', () async {
    final store = ExternalStoreAiThreadRuntime();
    expect(store.status, AiThreadStatus.empty);

    final events = <AiThreadStatus>[];
    final sub = store.changes.listen((_) => events.add(store.status));

    store.setLoading();
    expect(store.status, AiThreadStatus.loading);

    store.setMessages([
      AiMessage(
        id: '1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
        status: AiMessageStatus.complete,
      ),
    ]);
    expect(store.status, AiThreadStatus.idle);
    expect(store.messages, hasLength(1));

    store.setEmpty();
    expect(store.status, AiThreadStatus.empty);
    expect(store.messages, isEmpty);

    store.setError('boom');
    expect(store.status, AiThreadStatus.error);
    expect(store.errorMessage, 'boom');

    await sub.cancel();
    expect(events, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client/packages/ai_message_core && dart test test/external_store_runtime_test.dart`

- [ ] **Step 3: Implement runtime + transcript types**

```dart
enum AiThreadStatus { idle, loading, empty, error }

abstract class AiThreadRuntime {
  List<AiMessage> get messages;
  AiThreadStatus get status;
  String? get errorMessage;
  Stream<void> get changes;
}

class ExternalStoreAiThreadRuntime implements AiThreadRuntime {
  // broadcast stream controller; set* methods update state and add(null)
}

class AiTranscriptFragment {
  const AiTranscriptFragment({required this.name, required this.bytes});
  final String name;
  final List<int> bytes;
}

class AiTranscriptBundle {
  const AiTranscriptBundle({
    required this.adapterId,
    required this.fragments,
    this.hints = const {},
  });
  final String adapterId;
  final List<AiTranscriptFragment> fragments;
  final Map<String, String> hints;
}

abstract class AiTranscriptAdapter {
  String get id;
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle);
}
```

Rules from spec: `setMessages([])` → `empty`; non-empty → `idle`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core
git commit -m "feat(ai_message_core): ExternalStore runtime and transcript adapter API"
```

---

### Task 4: Claude adapter → `AiMessage` (locate + parse split)

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/history/claude_ai_transcript.dart`
- Create: `client/test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`
- Keep temporarily: `claude_session_history.dart` until cutover (or replace in place if all call sites migrate in Task 7–8 — prefer **new files first**, delete old in Task 9)

- [ ] **Step 1: Read fixture, then write failing fixture test**

Open `client/test/fixtures/session_history/claude/basic.jsonl` and note real event shapes (user/assistant text, `tool_use` / `tool_result` ids). Write expects from that file — do not invent fields.

Example structure (replace role/id/tool asserts with values from the fixture):

```dart
test('ClaudeAiTranscriptAdapter parses user text and correlates tool_result', () async {
  final bytes = await File(
    'test/fixtures/session_history/claude/basic.jsonl',
  ).readAsBytes();
  final adapter = const ClaudeAiTranscriptAdapter();
  final messages = await adapter.parse(
    AiTranscriptBundle(
      adapterId: adapter.id,
      fragments: [
        AiTranscriptFragment(name: 'basic.jsonl', bytes: bytes),
      ],
    ),
  );
  expect(messages, isNotEmpty);
  expect(messages.any((m) => m.role == AiRole.user), isTrue);
  expect(
    messages.any(
      (m) =>
          m.role == AiRole.assistant &&
          m.parts.any((p) => p is AiToolCallPart),
    ),
    isTrue,
  );
  // No user message whose only parts are tool results:
  for (final m in messages.where((m) => m.role == AiRole.user)) {
    expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
  }
  final tools = messages
      .expand((m) => m.parts)
      .whereType<AiToolCallPart>()
      .toList();
  expect(tools, isNotEmpty);
  // If fixture includes tool_result for a call id, assert that part.result != null
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`

- [ ] **Step 3: Implement locate helper + adapter**

```dart
/// Locate Claude transcript → bundle (uses existing probePinnedTranscript).
Future<AiTranscriptBundle?> locateClaudeTranscript(SessionHistoryContext ctx);

final class ClaudeAiTranscriptAdapter implements AiTranscriptAdapter {
  const ClaudeAiTranscriptAdapter();
  @override
  String get id => 'claude';
  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async { ... }
}
```

Port event loop from `claude_session_history.dart` with these changes:
- Build `List<AiMessage>` with parts (not `SessionHistoryTurn`).
- On `tool_use` → append/update assistant message with `AiToolCallPart`.
- On `tool_result` (often user turn) → correlate by id onto prior `AiToolCallPart`; **do not** emit tool-only user messages.
- Deterministic ids from event `uuid` / `message.id` when present.

Keep `SessionHistoryContext` for locate only (still in app; can remain in old capability file until Task 9 moves locate context type next to locator).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/history/claude_ai_transcript.dart \
  client/test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart
git commit -m "feat(cli): Claude transcript adapter emits AiMessage parts"
```

---

### Task 5: Remaining CLI adapters (flashskyai, Codex, OpenCode, Cursor)

**Files:**
- Create: `…/flashskyai_ai_transcript.dart` + test
- Create: `…/codex_ai_transcript.dart` + test
- Create: `…/opencode_ai_transcript.dart` + test
- Create: `…/cursor_ai_transcript.dart` + test

For each CLI:
- [ ] **Step 1:** Write fixture-based failing parse test (reuse existing fixtures under `test/fixtures/session_history/{cli}/`)
- [ ] **Step 2:** Run — FAIL
- [ ] **Step 3:** Implement `locate*Transcript` + `*AiTranscriptAdapter` ported from current `*_session_history.dart` with parts + tool correlation rules
- [ ] **Step 4:** Run — PASS
- [ ] **Step 5:** Commit per CLI (or one commit if small)

```bash
git commit -m "feat(cli): AiMessage adapters for flashskyai/codex/opencode/cursor"
```

**OpenCode / Codex:** multiple fragments in `AiTranscriptBundle` when needed; locate helpers read all required files into fragments before parse.

---

### Task 6: Scaffold `ai_message_ui` + `AiThread` shell (TDD)

**Files:**
- Create: `client/packages/ai_message_ui/pubspec.yaml`
- Create: `client/packages/ai_message_ui/lib/ai_message_ui.dart`
- Create: `client/packages/ai_message_ui/lib/src/theme.dart`
- Create: `client/packages/ai_message_ui/lib/src/ai_thread.dart`
- Create: `client/packages/ai_message_ui/test/ai_thread_test.dart`
- Modify: `client/pubspec.yaml` — path dep

- [ ] **Step 1: Package manifest**

```yaml
name: ai_message_ui
description: Flutter Thread/Message/Part UI for ai_message_core.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  ai_message_core:
    path: ../ai_message_core
  flutter_markdown_plus: ^1.0.11

dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Step 2: Failing widget test**

```dart
testWidgets('AiThread shows loadingBuilder when loading', (tester) async {
  final store = ExternalStoreAiThreadRuntime()..setLoading();
  await tester.pumpWidget(
    MaterialApp(
      home: AiThread(
        runtime: store,
        loadingBuilder: (_) => const Text('LOADING'),
        emptyBuilder: (_) => const Text('EMPTY'),
        errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
      ),
    ),
  );
  expect(find.text('LOADING'), findsOneWidget);
});
```

- [ ] **Step 3: Implement `AiThread` with load-older scroll API**

Subscribe to `runtime.changes` in `State`; rebuild on events. Switch on `status`. For `idle`, build a `ListView.builder` of messages via required-or-optional `messageBuilder`. **Do not** default to `AiMessageView` yet (created in Task 7) — default idle row can be plain text from `AiTextPart`s, or require `messageBuilder` until Task 7.

**Load-older chrome lives on `AiThread`** (port from `session_history_turn_list.dart`, do not leave this to a deleted app widget):

```dart
class AiThread extends StatefulWidget {
  const AiThread({
    // ...
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.onLoadOlder,
    this.loadOlderScrollThreshold = 120,
    this.scrollController, // optional; create internal if null
  });
}
```

Behavior to port:
1. `NotificationListener<ScrollNotification>` near top → call `onLoadOlder` when `hasOlder && !isLoadingOlder`
2. After messages prepend (visible window grows upward), restore scroll offset so the viewport does not jump
3. Initial jump to bottom when first non-empty idle list appears
4. Optional `loadOlderHeaderBuilder` (or spinner-only default) at list top — **no package l10n**; app injects “scroll for earlier” copy in Task 9

- [ ] **Step 4: Widget test for load-older callback when scrolled near top** (can use a short fake list + controller.jumpTo)

- [ ] **Step 5: PASS + commit**

```bash
git commit -m "feat(ai_message_ui): scaffold AiThread with status builders"
```

---

### Task 7: Message / Parts views (text, tool, reasoning)

**Files:**
- Create: `ai_message_view.dart`, `ai_message_parts.dart`, `parts/*.dart`, theme
- Create: `client/packages/ai_message_ui/test/ai_message_parts_test.dart`

- [ ] **Step 1: Failing tests**
  - Renders user vs assistant alignment
  - Tool card shows toolName; tap expands args/result
  - Text part renders markdown smoke (`**bold**`)

- [ ] **Step 2: Implement views**
  - `AiTextPartView`: `flutter_markdown_plus`; tolerate incomplete fences (wrap parse in try/catch or preprocess unclosed fence as open code block — document chosen approach in code comment)
  - `AiToolCallPartView`: `ExpansionTile` or custom collapse; default collapsed when result present or always collapsed-by-default for tools
  - `AiReasoningPartView`: collapsed by default
  - `AiMessageParts`: switch on part type; `partBuilders` map override

- [ ] **Step 3: Wire `AiMessageView` as default `messageBuilder` on `AiThread`**

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "feat(ai_message_ui): Message/Parts views with tool cards"
```

---

### Task 8: App locator, loader, cubit → ExternalStore (no DI cutover yet)

**Files:**
- Create: `client/lib/services/session/ai_history_locator.dart`
- Create: `client/lib/services/session/ai_history_loader.dart`
- Create: `client/lib/cubits/ai_history_cubit.dart`
- Create: `client/test/services/session/ai_history_loader_test.dart`
- Create: `client/test/cubits/ai_history_cubit_test.dart`

**Do not** modify `app_shell.dart` / `main.dart` / review UI in this task — keep `SessionHistoryCubit` wired so the tree still compiles until Task 9.

- [ ] **Step 1: Locator**

```dart
class AiHistoryLocator {
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    // switch cli → locateClaudeTranscript / …
  }
}
```

Reuse `SessionHistoryContextBuilder` output (keep builder + `SessionHistoryContext` for now).

- [ ] **Step 2: Loader with mtime cache**

Mirror `SessionHistoryLoader`: key `sessionId+memberId+path mtimes`; return `List<AiMessage>` or throw; map missing bundle → empty list (caller sets empty).

Adapter map: `CliTool` → `AiTranscriptAdapter` instance (constants).

- [ ] **Step 3: `AiHistoryCubit`**

```dart
class AiHistoryCubit extends Cubit<AiHistoryState> {
  final ExternalStoreAiThreadRuntime runtime = ExternalStoreAiThreadRuntime();
  // load(): generation token; runtime.setLoading(); loader; setMessages / setEmpty / setError
  // Keep _allMessages + _visibleCount; window with kSessionHistoryInitialTurns / OlderPageSize
  // On success: runtime.setMessages(visibleSlice) AND emit state for hasOlder/isLoadingOlder
}
```

`AiHistoryState` retains windowing fields (`hasOlder`, `isLoadingOlder`, `totalMessageCount`, `sessionId`, `memberId`); **message bodies live on `runtime`**.

- [ ] **Step 4: Unit tests for stale generation + loadOlder window** (construct cubit in tests; no app provider yet)

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(session): AiHistory locator/loader/cubit on ExternalStore"
```

---

### Task 9: Swap review UI + DI cutover; delete old history stack

**Files:**
- Modify: `client/lib/app/app_shell.dart`, `client/lib/main.dart` — construct/provide `AiHistoryCubit`; remove `SessionHistoryCubit`
- Modify: `client/lib/pages/chat/session_history_review.dart` — use `AiThread` + builders with l10n
- Delete: `session_history_turn_list.dart`, `session_history_turn_tile.dart`
- Delete: old `*_session_history.dart` implementations
- Modify: each `*_cli_tool.dart` — remove `sessionHistory` capability field; registry no longer registers history capability
- Delete: `session_history_cubit.dart`, `session_history_loader.dart`
- **Keep** `SessionHistoryContext` + `SessionHistoryContextBuilder` (or move them into `ai_history_locator.dart` / `session_history_context.dart` in the same task — locate helpers still need the context type). Strip turn/snapshot/`SessionHistoryCapability` from `session_history_capability.dart` (delete file if empty after move).
- Update: all tests referencing old types
- Update: docs that cite `SessionHistoryCapability` as the review model

- [ ] **Step 1: Wire DI and replace history list body in the same change set**

```dart
AiThread(
  runtime: context.read<AiHistoryCubit>().runtime,
  loadingBuilder: (…) => …,
  emptyBuilder: (…) => Text(l10n.…),
  errorBuilder: (…) => … onRetry: () => cubit.load(force: true),
  hasOlder: state.hasOlder,
  isLoadingOlder: state.isLoadingOlder,
  onLoadOlder: () => cubit.loadOlder(),
  loadOlderScrollThreshold: kSessionHistoryLoadOlderScrollThreshold,
)
```

Do **not** keep a parallel app `ListView` for load-older — that chrome is on `AiThread` (Task 6).

- [ ] **Step 2: Remove capability from CLI tool definitions**

Hard-fail if adapter missing for a launch CLI in loader (same spirit as current capability assert). Update/delete `client/test/services/cli/registry/session_history_registration_test.dart` (it currently asserts `SessionHistoryCapability` on every launch CLI) — replace with adapter-map coverage or remove.

- [ ] **Step 3: Relocate or keep `SessionHistoryContext` explicitly; delete turn types + capability interface**

- [ ] **Step 4: `rg SessionHistoryTurn|SessionHistoryCapability|SessionHistoryCubit` → zero hits in `client/lib`**

- [ ] **Step 5: Run focused then full tests**

```bash
cd client && flutter test test/cubits/ai_history_cubit_test.dart \
  test/pages/chat/session_history_review_submit_test.dart \
  test/services/cli/registry/capabilities/history/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: PASS (fix any fallout)

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(chat): History review uses AiThread; remove SessionHistoryTurn"
```

---

### Task 10: Docs + AGENTS touch-up

**Files:**
- Modify: `docs/superpowers/specs/2026-07-10-session-history-review-design.md` — note superseded data model (if not already)
- Modify: `AGENTS.md` or DEVELOPMENT only if they mention `SessionHistoryCapability` as the live API
- Modify: plan/spec cross-links as needed

- [ ] **Step 1: Grep docs for SessionHistoryTurn / SessionHistoryCapability; update**
- [ ] **Step 2: Commit**

```bash
git commit -m "docs: point history review at AiMessage layer"
```

---

## Verification checklist (before claiming done)

- [ ] `cd client/packages/ai_message_core && dart test`
- [ ] `cd client/packages/ai_message_ui && flutter test`
- [ ] `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] `cd client && flutter test --exclude-tags integration`
- [ ] Manual: open existing session → parts Thread, no PTY; tool cards; load older; slim compose still connects

---

## Out of scope (do not implement in this plan)

- Live transcript tailing
- Multi-member timeline / TeamBus in thread
- Edit / branch / cloud assistant-ui primitives
- Moving CLI adapters into a separate package
