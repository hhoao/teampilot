# Unified Compose Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `WorkspaceComposeCard` with sealed `ComposeChrome` (unbound | bound), shared file-drop/attach/paste path, and Ask AI hosting the unbound body directly instead of nesting `WorkspaceChatLanding`.

**Architecture:** Rename compose drop ingestor; extract `ComposeFileDropRegion`; merge the two parallel compose cards into `WorkspaceComposeCard` driven by `UnboundComposeChrome` / `BoundComposeChrome`; extract `UnboundComposeBody` (Landing state without page chrome) for Landing + Ask AI; Session continues via bound chrome with required drop.

**Tech Stack:** Flutter / `flutter_bloc`; existing `ComposeFocusShell` / `ComposeTriggerField` / DnD primitives (`ExternalFileDropRegion`, `WorkspaceFileDropRegion`); `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-28-unified-compose-card-design.md`

## Global Constraints

- Prefer best extensibility: single card + sealed chrome; do **not** stop at a Session-only drop patch.
- Keep full unbound and bound toolbar capabilities (no product redesign).
- Drop inserts `@` path references via compose ingestor; do **not** change `TerminalDropIngestor`.
- Ask AI must not nest `WorkspaceChatLanding`; it hosts unbound compose body + dismiss.
- `dropTarget` is **required** on `WorkspaceComposeCard` (hosts always pass `ComposeFileDropIngestor`).
- `deferFieldMount: true` only on primary Landing page path; Ask AI / Session default `false`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and the test commands listed in Task 8.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/compose/compose_file_drop_ingestor.dart` | Renamed from `compose_landing_drop_ingestor.dart`; `@` ref ingest |
| `client/lib/widgets/compose/compose_file_drop_region.dart` | Wraps External + Workspace drop regions |
| `client/lib/widgets/compose/compose_chrome.dart` | Sealed `ComposeChrome` + unbound/bound field bags |
| `client/lib/widgets/compose/workspace_compose_card.dart` | Unified card UI (shell, field, chrome toolbar, trailing actions, drop) |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Extracted Landing compose state (draft/enhance/voice/attach/drop/submit hooks) without page chrome |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Page chrome host around `UnboundComposeBody` |
| `client/lib/pages/chat/session_chat_view.dart` | Bound host; builds `ComposeFileDropIngestor` + `WorkspaceComposeCard` |
| `client/lib/services/selection_ai/selection_ask_ai.dart` | Dialog hosts `UnboundComposeBody` + dismiss `×` |
| **Delete** | `workspace_chat_landing_compose_card.dart`, `session_review_compose_card.dart`, `compose_landing_drop_ingestor.dart` |

---

### Task 1: Rename `ComposeFileDropIngestor`

**Files:**
- Create: `client/lib/services/compose/compose_file_drop_ingestor.dart`
- Delete: `client/lib/services/compose/compose_landing_drop_ingestor.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` (import + type name)
- Create: `client/test/services/compose/compose_file_drop_ingestor_test.dart`
- Delete: `client/test/services/compose/compose_landing_drop_ingestor_test.dart`

**Interfaces:**
- Consumes: `resolveComposeFileReference`, `WorkspaceDropTarget`, `WorkspaceDragPayload`
- Produces:
  ```dart
  class ComposeFileDropIngestor implements WorkspaceDropTarget {
    ComposeFileDropIngestor({
      required this.workspaceRoot,
      required this.onInsertReferences,
    });
    final String workspaceRoot;
    final void Function(List<String> references) onInsertReferences;
    @override
    bool accepts(DragPayloadKind kind);
    @override
    Future<DropOutcome> consume(WorkspaceDragPayload payload);
  }
  ```

- [ ] **Step 1: Write the renamed failing test file**

Copy `compose_landing_drop_ingestor_test.dart` to `compose_file_drop_ingestor_test.dart`, replace all `ComposeLandingDropIngestor` → `ComposeFileDropIngestor` and update the import to `compose_file_drop_ingestor.dart`. Keep the three tests (`imports external image drops…`, `inserts @ references for non-image files`, `skips directories`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/compose/compose_file_drop_ingestor_test.dart`

Expected: FAIL — `compose_file_drop_ingestor.dart` / `ComposeFileDropIngestor` not found.

- [ ] **Step 3: Implement rename**

Create `compose_file_drop_ingestor.dart` with the same body as today’s landing ingestor, class renamed and doc comment:

```dart
/// Compose drop target: inserts `@` path references (any file type).
class ComposeFileDropIngestor implements WorkspaceDropTarget {
  // same fields + accepts/consume as ComposeLandingDropIngestor
}
```

Update Landing to import/use `ComposeFileDropIngestor`. Delete old ingestor + old test file. Grep for `ComposeLandingDropIngestor` / `compose_landing_drop_ingestor` and clear leftovers.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/compose/compose_file_drop_ingestor_test.dart`

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/compose/compose_file_drop_ingestor.dart \
  client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/test/services/compose/compose_file_drop_ingestor_test.dart
git rm client/lib/services/compose/compose_landing_drop_ingestor.dart \
  client/test/services/compose/compose_landing_drop_ingestor_test.dart
git commit -m "$(cat <<'EOF'
refactor(compose): rename ComposeLandingDropIngestor to ComposeFileDropIngestor

EOF
)"
```

---

### Task 2: `ComposeFileDropRegion`

**Files:**
- Create: `client/lib/widgets/compose/compose_file_drop_region.dart`
- Create: `client/test/widgets/compose/compose_file_drop_region_test.dart`

**Interfaces:**
- Consumes: `ExternalFileDropRegion`, `WorkspaceFileDropRegion`, `WorkspaceDropTarget`, `DropOutcome`
- Produces:
  ```dart
  class ComposeFileDropRegion extends StatelessWidget {
    const ComposeFileDropRegion({
      required this.target,
      required this.child,
      this.onOutcome,
      super.key,
    });
    final WorkspaceDropTarget target;
    final Widget child;
    final ValueChanged<DropOutcome>? onOutcome;
  }
  ```

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_file_drop_region.dart';
import 'package:teampilot/widgets/workspace_dnd/external_file_drop_region.dart';
import 'package:teampilot/widgets/workspace_dnd/workspace_file_drop_region.dart';

void main() {
  testWidgets('ComposeFileDropRegion wraps External and Workspace drop regions',
      (tester) async {
    final target = ComposeFileDropIngestor(
      workspaceRoot: '/repo',
      onInsertReferences: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ComposeFileDropRegion(
          target: target,
          child: const SizedBox(key: Key('child')),
        ),
      ),
    );
    expect(find.byType(ExternalFileDropRegion), findsOneWidget);
    expect(find.byType(WorkspaceFileDropRegion), findsOneWidget);
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/compose_file_drop_region_test.dart`

Expected: FAIL — library/widget not found.

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';

import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../workspace_dnd/external_file_drop_region.dart';
import '../workspace_dnd/workspace_file_drop_region.dart';

/// Compose-card drop surface: OS files + in-app file-tree drags.
class ComposeFileDropRegion extends StatelessWidget {
  const ComposeFileDropRegion({
    required this.target,
    required this.child,
    this.onOutcome,
    super.key,
  });

  final WorkspaceDropTarget target;
  final Widget child;
  final ValueChanged<DropOutcome>? onOutcome;

  @override
  Widget build(BuildContext context) {
    return ExternalFileDropRegion(
      target: target,
      onOutcome: onOutcome,
      child: WorkspaceFileDropRegion(
        target: target,
        onOutcome: onOutcome,
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test**

Run: `cd client && flutter test test/widgets/compose/compose_file_drop_region_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_file_drop_region.dart \
  client/test/widgets/compose/compose_file_drop_region_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): add ComposeFileDropRegion wrapper

EOF
)"
```

---

### Task 3: `ComposeChrome` sealed types

**Files:**
- Create: `client/lib/widgets/compose/compose_chrome.dart`
- Create: `client/test/widgets/compose/compose_chrome_test.dart`

**Interfaces:**
- Consumes: types already used by the two cards (`TpActionMenuSpec`, `CliPreset`, `IconData`, etc.)
- Produces: sealed `ComposeChrome` with `UnboundComposeChrome` and `BoundComposeChrome` carrying the **same fields** today’s left toolbars need (copy field lists from `WorkspaceChatLandingComposeCard` unbound args and `SessionReviewComposeCard` continue args). Bound also includes: `composeEnabled`, `launchError`, `onRemapDeadTarget`, `floating`, identity/preset/permission/team-settings fields.

Exact unbound fields (required unless noted):

```dart
sealed class ComposeChrome {
  const ComposeChrome();
}

final class UnboundComposeChrome extends ComposeChrome {
  const UnboundComposeChrome({
    required this.conversationModeLabel,
    required this.autoChipLabel,
    required this.dangerouslySkipPermissions,
    required this.defaultPermissionsLabel,
    required this.fullAccessPermissionsLabel,
    required this.conversationModeSpecs,
    required this.autoChipSpecs,
    required this.onConversationModeSelected,
    required this.onAutoChipSelected,
    required this.onPermissionSelected,
    this.autoChipLeading,
    this.expertChipLabel,
    this.expertChipSpecs = const [],
    this.onExpertChipSelected,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
  });
  // fields matching WorkspaceChatLandingComposeCard toolbar args
}

final class BoundComposeChrome extends ComposeChrome {
  const BoundComposeChrome({
    this.composeEnabled = true,
    this.launchError,
    this.onRemapDeadTarget,
    this.floating = false,
    this.identityLabel,
    this.identityIcon,
    this.sameCliPresets = const [],
    this.selectedPresetId,
    this.modelPresetLabel,
    this.emptyPresetHintLabel,
    this.onPresetSelected,
    this.dangerouslySkipPermissions = false,
    this.defaultPermissionsLabel,
    this.fullAccessPermissionsLabel,
    this.onPermissionSelected,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
  });
  // fields matching SessionReviewComposeCard continue chrome
}
```

- [ ] **Step 1: Write a small type test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';

void main() {
  test('ComposeChrome exhaustiveness covers unbound and bound', () {
    const ComposeChrome unbound = UnboundComposeChrome(
      conversationModeLabel: 'Simple',
      autoChipLabel: 'Preset',
      dangerouslySkipPermissions: false,
      defaultPermissionsLabel: 'Default',
      fullAccessPermissionsLabel: 'Full',
      conversationModeSpecs: [],
      autoChipSpecs: [],
      onConversationModeSelected: _noop,
      onAutoChipSelected: _noop,
      onPermissionSelected: _noopBool,
    );
    const ComposeChrome bound = BoundComposeChrome(identityLabel: 'Team');
    expect(unbound, isA<UnboundComposeChrome>());
    expect(bound, isA<BoundComposeChrome>());
  });
}

void _noop(Object? _) {}
void _noopBool(bool _) {}
```

(Adjust `const` if callbacks prevent const — use non-const constructors if needed.)

- [ ] **Step 2: Run test — expect FAIL (types missing)**

Run: `cd client && flutter test test/widgets/compose/compose_chrome_test.dart`

- [ ] **Step 3: Implement `compose_chrome.dart`** with the field bags above (import `shared_ui` for `TpActionMenuSpec`, `cli_preset.dart` for `CliPreset`).

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_chrome.dart \
  client/test/widgets/compose/compose_chrome_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): add sealed ComposeChrome for unbound and bound toolbars

EOF
)"
```

---

### Task 4: `WorkspaceComposeCard`

**Files:**
- Create: `client/lib/widgets/compose/workspace_compose_card.dart`
- Create: `client/test/widgets/compose/workspace_compose_card_test.dart`
- Reference implementations to merge (do not leave duplicates after Task 5/6 deletes):
  - `client/lib/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart`
  - `client/lib/pages/chat/session_review_compose_card.dart`

**Interfaces:**
- Consumes: `ComposeChrome`, `ComposeFileDropRegion`, `ComposeFocusShell`, `ComposeTriggerField`, palette/voice bar from landing helpers, chips
- Produces:
  ```dart
  class WorkspaceComposeCard extends StatelessWidget {
    const WorkspaceComposeCard({
      required this.controller,
      required this.focusNode,
      required this.hint,
      required this.canSubmit,
      required this.onSubmit,
      required this.onChanged,
      required this.chrome,
      required this.dropTarget,
      required this.attachTooltip,
      required this.enhanceTooltip,
      required this.voiceTooltip,
      required this.voiceCancelTooltip,
      required this.voiceStopTooltip,
      required this.isEnhancing,
      required this.isVoiceListening,
      required this.voiceElapsed,
      required this.voiceSoundLevel,
      required this.onAttach,
      required this.onEnhance,
      required this.onVoice,
      required this.onVoiceCancel,
      required this.onVoiceStop,
      required this.workspaceRoot,
      required this.skills,
      required this.plugins,
      required this.slashBundle,
      this.isSubmitting = false,
      this.onPasteImage,
      this.submitBlockedTooltip,
      this.deferFieldMount = false,
      super.key,
    });
    // …
  }
  ```

Build rules:
- Always wrap with `ComposeFileDropRegion(target: dropTarget, child: …)`.
- Switch on `chrome`: unbound → Landing left toolbar; bound → continue toolbar + optional launch-error banner (copy from `SessionReviewComposeCard`).
- Trailing attach/enhance/voice/send shared; voice recording row shared.
- When `deferFieldMount == true`, wrap field in `TpDeferredMountShell(delayFrames: 2, …)` (reuse `kLandingComposeFieldDelayFrames` — move constant next to the card or keep a public const in the new file).
- When chrome is `BoundComposeChrome`, honor `composeEnabled`, `floating`, send `canSubmit: composeEnabled && canSubmit`.
- Deduplicate `_SendButton` / `_ComposeActionIcon` / `_TeamSettingsButton` / `_ContinueIdentityChip` into this file (one copy).

- [ ] **Step 1: Write failing widget tests**

```dart
// workspace_compose_card_test.dart — key cases:
// 1) unbound chrome shows conversation mode label; finds ComposeFileDropRegion
// 2) bound chrome shows identityLabel + ComposeModelPresetChip; no 'Simple'/'Team' mode labels
// 3) deferFieldMount true → TpDeferredMountShell present
```

Use `MaterialApp` + `AppLocalizations` delegates like `expert_landing_chip_test.dart`. Pass a real `ComposeFileDropIngestor` as `dropTarget`.

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/widgets/compose/workspace_compose_card_test.dart`

- [ ] **Step 3: Implement `WorkspaceComposeCard`** by merging the two card `build` methods and private widgets. Prefer Landing send throttle key name `workspace_chat_landing_send` for unbound and keep session throttle key `session_review_compose_send` for bound if both exist today (match existing keys so tests/telemetry stay stable).

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/workspace_compose_card.dart \
  client/test/widgets/compose/workspace_compose_card_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): add WorkspaceComposeCard with sealed chrome and required drop

EOF
)"
```

---

### Task 5: Wire Landing to `WorkspaceComposeCard`; delete landing compose card

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/test/pages/expert_hub/expert_landing_chip_test.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart`
- Delete: `client/lib/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart`

**Interfaces:**
- Consumes: `WorkspaceComposeCard`, `UnboundComposeChrome`, `ComposeFileDropIngestor`
- Produces: Landing still exposes `WorkspaceChatLanding`; builds:

```dart
WorkspaceComposeCard(
  // shared field/action args as today
  chrome: UnboundComposeChrome( /* map existing chip args */ ),
  dropTarget: ComposeFileDropIngestor(
    workspaceRoot: _activeLaunchDirectory(),
    onInsertReferences: _insertComposeReferences,
  ),
  deferFieldMount: widget.showLandingChrome, // true on page; false when chrome-off until Task 7 removes flag
  // …
)
```

- [ ] **Step 1: Update `expert_landing_chip_test.dart` to construct `WorkspaceComposeCard` + `UnboundComposeChrome` + required `dropTarget` (ingestor with empty callback). Assert same expert chip visibility / deferred mount behavior.**

- [ ] **Step 2: Run expert chip tests — expect FAIL until Landing card deleted/rewired**

Run: `cd client && flutter test test/pages/expert_hub/expert_landing_chip_test.dart`

- [ ] **Step 3: Replace `WorkspaceChatLandingComposeCard(...)` in Landing with `WorkspaceComposeCard` + `UnboundComposeChrome`. Remove `_wrapDropTarget` usage from the deleted card. Delete `workspace_chat_landing_compose_card.dart`. Update chrome test expectations to `WorkspaceComposeCard`.**

- [ ] **Step 4: Run**

```bash
cd client && flutter test \
  test/pages/expert_hub/expert_landing_chip_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -u client/lib/pages/home_workspace/workspace/ \
  client/test/pages/expert_hub/expert_landing_chip_test.dart \
  client/test/pages/home_workspace/workspace/
git commit -m "$(cat <<'EOF'
refactor(landing): host WorkspaceComposeCard and remove landing compose card

EOF
)"
```

---

### Task 6: Wire Session bound chrome + drop; delete `SessionReviewComposeCard`

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/test/pages/chat/session_history_continue_chrome_test.dart`
- Modify: `client/test/pages/chat/session_chat_submit_gate_test.dart`
- Delete: `client/lib/pages/chat/session_review_compose_card.dart`
- Create: `client/test/pages/chat/session_compose_drop_test.dart` (or extend continue chrome test)

**Interfaces:**
- Consumes: `WorkspaceComposeCard`, `BoundComposeChrome`, `ComposeFileDropIngestor`, `insertComposeReferences`
- Produces: Session host methods:

```dart
void _insertComposeReferences(List<String> references) {
  insertComposeReferences(_controller, references);
  if (!mounted) return;
  setState(() {});
  _focusNode.requestFocus();
}

ComposeFileDropIngestor _composeDropIngestor() => ComposeFileDropIngestor(
  workspaceRoot: _workspaceRoot,
  onInsertReferences: _insertComposeReferences,
);
```

Replace `SessionReviewComposeCard(...)` with:

```dart
WorkspaceComposeCard(
  chrome: BoundComposeChrome(
    composeEnabled: !permissionWaiting,
    launchError: …,
    onRemapDeadTarget: …,
    floating: …,
    identityLabel: …,
    // remaining continue fields as today
  ),
  dropTarget: _composeDropIngestor(),
  deferFieldMount: false,
  // shared action args
)
```

- [ ] **Step 1: Update continue-chrome and submit-gate tests to use `WorkspaceComposeCard` + `BoundComposeChrome` + `dropTarget`. Add assertion `find.byType(ComposeFileDropRegion)`.**

- [ ] **Step 2: Run those tests — expect FAIL (old type / missing drop on session)**

Run: `cd client && flutter test test/pages/chat/session_history_continue_chrome_test.dart test/pages/chat/session_chat_submit_gate_test.dart`

- [ ] **Step 3: Implement Session wiring + delete `session_review_compose_card.dart`. Grep for `SessionReviewComposeCard` and fix leftovers.**

- [ ] **Step 4: Run**

```bash
cd client && flutter test \
  test/pages/chat/session_history_continue_chrome_test.dart \
  test/pages/chat/session_chat_submit_gate_test.dart \
  test/widgets/compose/workspace_compose_card_test.dart
```

Expected: PASS. Bound path has drop region.

- [ ] **Step 5: Commit**

```bash
git add -u client/lib/pages/chat/ client/test/pages/chat/
git commit -m "$(cat <<'EOF'
feat(chat): use WorkspaceComposeCard with file drop on session continue

EOF
)"
```

---

### Task 7: Extract `UnboundComposeBody`; Ask AI hosts it directly

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` (thin page chrome around body)
- Modify: `client/lib/services/selection_ai/selection_ask_ai.dart`
- Modify: `client/test/services/selection_ai/selection_ask_ai_test.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart` (Landing still has chrome on/off **or** remove `showLandingChrome` if unused)

**Interfaces:**
- Consumes: existing Landing state machine (draft, enhance, voice, attach, drop, submit callback)
- Produces:
  ```dart
  class UnboundComposeBody extends StatefulWidget {
    const UnboundComposeBody({
      required this.workspace,
      required this.onSubmit, // void Function(String message, LandingLaunchContext draft)
      this.initialText,
      this.isSubmitting = false,
      this.deferFieldMount = false,
      super.key,
    });
  }
  ```

  Moves today’s `WorkspaceChatLanding` **State** logic that builds `WorkspaceComposeCard` into this widget. `WorkspaceChatLanding` becomes:

  ```dart
  // build:
  // child = UnboundComposeBody(..., deferFieldMount: true, onSubmit: …)
  // if show page chrome: Stack(header + back + centered child) else child
  ```

  Ask AI dialog:

  ```dart
  TpDialog(
    child: Stack(
      children: [
        UnboundComposeBody(
          workspace: widget.workspace,
          initialText: widget.initialText,
          isSubmitting: _submitting,
          deferFieldMount: false,
          onSubmit: (message, draft) => unawaited(_submit(message, draft)),
        ),
        Positioned(… dismiss × …),
      ],
    ),
  );
  ```

  **Do not** mount `WorkspaceChatLanding` inside Ask AI.

  After Ask AI migration: if nothing else needs `showLandingChrome: false`, **delete** the flag and always render Landing with page chrome; update/delete `workspace_chat_landing_chrome_test.dart` accordingly (keep a test that Landing page still shows back + header + `WorkspaceComposeCard`).

- [ ] **Step 1: Update selection Ask AI expectations**

```dart
void _expectComposeOnlyAskAiDialog() {
  expect(find.text('Ask AI…'), findsNothing);
  expect(find.byType(TpDialogHeader), findsNothing);
  expect(find.byType(WorkspaceChatLanding), findsNothing);
  expect(find.byType(UnboundComposeBody), findsOneWidget);
  expect(find.byType(WorkspaceComposeCard), findsOneWidget);
  expect(find.byKey(AppKeys.workspaceChatLandingBackButton), findsNothing);
  expect(find.byType(WorkspaceLandingHeaderRow), findsNothing);
}
```

- [ ] **Step 2: Run selection tests — expect FAIL**

Run: `cd client && flutter test test/services/selection_ai/selection_ask_ai_test.dart`

- [ ] **Step 3: Extract `UnboundComposeBody`, thin Landing, rewire Ask AI, remove obsolete `showLandingChrome` if unused.**

Move carefully: keep BlocListeners that belong to unbound draft sync with the body; page-only back button stays on Landing.

- [ ] **Step 4: Run**

```bash
cd client && flutter test \
  test/services/selection_ai/ \
  test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: PASS (chrome test updated or deleted per flag removal).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/lib/services/selection_ai/selection_ask_ai.dart \
  client/test/services/selection_ai/ \
  client/test/pages/home_workspace/workspace/
git commit -m "$(cat <<'EOF'
refactor(compose): extract UnboundComposeBody for Landing and Ask AI

EOF
)"
```

---

### Task 8: Final gate + leftover cleanup

**Files:**
- Grep sweep across `client/`

- [ ] **Step 1: Grep for forbidden leftovers**

```bash
cd client && rg -n 'SessionReviewComposeCard|WorkspaceChatLandingComposeCard|ComposeLandingDropIngestor|compose_landing_drop_ingestor|session_review_compose_card|workspace_chat_landing_compose_card' lib test
```

Expected: no matches (except maybe historical docs outside `client/`).

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no errors related to this change.

- [ ] **Step 3: Run focused regression suite**

```bash
cd client && flutter test \
  test/services/compose/compose_file_drop_ingestor_test.dart \
  test/widgets/compose/compose_file_drop_region_test.dart \
  test/widgets/compose/compose_chrome_test.dart \
  test/widgets/compose/workspace_compose_card_test.dart \
  test/pages/expert_hub/expert_landing_chip_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart \
  test/pages/chat/session_chat_submit_gate_test.dart \
  test/services/selection_ai/ \
  test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: all PASS.

- [ ] **Step 4: Commit any leftover test/doc fixes**

```bash
git add -u client/
git commit -m "$(cat <<'EOF'
chore(compose): finish unified compose card leftover cleanup

EOF
)"
```

(Skip empty commit if working tree clean.)

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Rename to `ComposeFileDropIngestor` | 1 |
| `ComposeFileDropRegion` | 2 |
| Sealed `ComposeChrome` unbound/bound | 3 |
| `WorkspaceComposeCard` + required drop | 4 |
| Landing hosts unified card; delete landing card | 5 |
| Session bound + drop; delete session card | 6 |
| `UnboundComposeBody`; Ask AI direct host; no nested Landing | 7 |
| Keep full chrome capabilities | 3–6 (field bags preserved) |
| Terminal DnD unchanged | Non-goal / no task touches it |
| Final analyze + tests | 8 |

## Plan self-review notes

- No TBD placeholders in task steps.
- Type names consistent: `ComposeFileDropIngestor`, `ComposeFileDropRegion`, `WorkspaceComposeCard`, `UnboundComposeChrome`, `BoundComposeChrome`, `UnboundComposeBody`.
- Ask AI migration is Task 7 (after card exists and Landing already uses it), so extraction is mechanical.
- `showLandingChrome` removal is conditional in Task 7 once Ask AI no longer needs it.
