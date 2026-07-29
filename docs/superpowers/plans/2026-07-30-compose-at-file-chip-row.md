# Compose `@` File Chip Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show clickable mirror chips (thumbnail/icon + basename) above the compose input for every `@` file reference, opening files via `WorkbenchEditorOpener`, without changing the text/`@path` submit model.

**Architecture:** Pure parse of `@` tokens from `TextEditingController.text` (same boundary-aware pattern as the textarea); a horizontal `ComposeAtFileChipRow` above `ComposeTriggerField` inside `WorkspaceComposeCard`; hosts pass `onOpenAtFile` that calls `WorkbenchEditorOpener.openFile` with workspace id and filesystem when available.

**Tech Stack:** Flutter, existing compose card / `WorkspaceChatLandingPalette`, `defaultInlineTokenPattern`, `isImagePreviewPath`, `WorkbenchEditorOpener`, `normalizeWorkspacePath`.

**Spec:** `docs/superpowers/specs/2026-07-30-compose-at-file-chip-row-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/compose/compose_at_file_refs.dart` | Parse `@` file refs → absolute path + display name; dedupe |
| `client/test/services/compose/compose_at_file_refs_test.dart` | Unit tests for parse / resolve / dedupe |
| `client/lib/widgets/compose/compose_at_file_chip_row.dart` | Horizontal chip list UI + tap |
| `client/test/widgets/compose/compose_at_file_chip_row_test.dart` | Widget tests for visibility / tap / image vs icon |
| `client/lib/widgets/compose/workspace_compose_card.dart` | Insert chip row above field; new `onOpenAtFile` param |
| `client/test/widgets/compose/workspace_compose_card_test.dart` | Assert chip row appears when controller has `@file` |
| `client/lib/pages/chat/session_chat_view.dart` | Wire `onOpenAtFile` → opener |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Wire `onOpenAtFile` → opener |

**Do not change:** attach / paste / drop / submit / `TpTokenTextField` inline pills / `/skill` handling.

---

### Task 1: Parse `@` file refs (TDD)

**Files:**
- Create: `client/lib/services/compose/compose_at_file_refs.dart`
- Test: `client/test/services/compose/compose_at_file_refs_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_at_file_refs.dart';

void main() {
  group('parseComposeAtFileRefs', () {
    test('parses relative and absolute @ refs', () {
      final refs = parseComposeAtFileRefs(
        'see @src/main.dart and @/tmp/Attachments/a.png please',
        workspaceRoot: '/repo',
      );
      expect(refs.map((r) => r.absolutePath).toList(), [
        '/repo/src/main.dart',
        '/tmp/Attachments/a.png',
      ]);
      expect(refs.map((r) => r.displayName).toList(), [
        'main.dart',
        'a.png',
      ]);
    });

    test('ignores /skill tokens and email-like @', () {
      final refs = parseComposeAtFileRefs(
        'user@host /commit @docs/readme.md',
        workspaceRoot: '/repo',
      );
      expect(refs.single.absolutePath, '/repo/docs/readme.md');
    });

    test('dedupes by path key keeping first order', () {
      final refs = parseComposeAtFileRefs(
        '@src/a.dart hello @src/a.dart @src/b.dart',
        workspaceRoot: '/repo',
      );
      expect(refs.map((r) => r.displayName).toList(), ['a.dart', 'b.dart']);
    });

    test('empty or skills-only yields empty', () {
      expect(
        parseComposeAtFileRefs('/commit /review', workspaceRoot: '/repo'),
        isEmpty,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/compose/compose_at_file_refs_test.dart`

Expected: FAIL (library / symbol not found)

- [ ] **Step 3: Implement minimal parser**

Create `client/lib/services/compose/compose_at_file_refs.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../inline_token/inline_token_palette.dart';
import '../../utils/workspace/workspace_path_utils.dart';

class ComposeAtFileRef {
  const ComposeAtFileRef({
    required this.absolutePath,
    required this.displayName,
  });

  final String absolutePath;
  final String displayName;
}

bool _isWindowsStylePath(String path) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path.trim());

String _pathKey(String path) {
  if (Platform.isWindows || _isWindowsStylePath(path)) {
    return path.toLowerCase();
  }
  return path;
}

bool _isAbsoluteRefBody(String body) =>
    body.startsWith('/') || _isWindowsStylePath(body);

String resolveComposeAtFileAbsolutePath(
  String refBody, {
  required String workspaceRoot,
}) {
  final body = refBody.trim();
  if (body.isEmpty) return '';
  if (_isAbsoluteRefBody(body)) {
    return normalizeWorkspacePath(body.replaceAll(r'\', '/'));
  }
  final root = normalizeWorkspacePath(workspaceRoot);
  if (root.isEmpty) return normalizeWorkspacePath(body.replaceAll(r'\', '/'));
  final joined = p.Context(style: p.Style.posix).join(
    root.replaceAll(r'\', '/'),
    body.replaceAll(r'\', '/'),
  );
  return normalizeWorkspacePath(joined);
}

List<ComposeAtFileRef> parseComposeAtFileRefs(
  String text, {
  required String workspaceRoot,
}) {
  final seen = <String>{};
  final out = <ComposeAtFileRef>[];
  for (final match in defaultInlineTokenPattern.allMatches(text)) {
    final token = match.group(0)!;
    if (!token.startsWith('@')) continue;
    final body = token.substring(1);
    if (body.isEmpty) continue;
    final absolute = resolveComposeAtFileAbsolutePath(
      body,
      workspaceRoot: workspaceRoot,
    );
    if (absolute.isEmpty) continue;
    final key = _pathKey(absolute);
    if (!seen.add(key)) continue;
    out.add(
      ComposeAtFileRef(
        absolutePath: absolute,
        displayName: p.basename(absolute),
      ),
    );
  }
  return out;
}
```

- [ ] **Step 4: Run tests and confirm PASS**

Run: `cd client && flutter test test/services/compose/compose_at_file_refs_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/compose/compose_at_file_refs.dart \
  client/test/services/compose/compose_at_file_refs_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): parse @ file refs for chip row

EOF
)"
```

---

### Task 2: `ComposeAtFileChipRow` widget (TDD)

**Files:**
- Create: `client/lib/widgets/compose/compose_at_file_chip_row.dart`
- Test: `client/test/widgets/compose/compose_at_file_chip_row_test.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/services/compose/compose_at_file_refs.dart';
import 'package:teampilot/widgets/compose/compose_at_file_chip_row.dart';

void main() {
  testWidgets('renders basenames and invokes onOpen', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposeAtFileChipRow(
            refs: const [
              ComposeAtFileRef(
                absolutePath: '/repo/src/a.dart',
                displayName: 'a.dart',
              ),
              ComposeAtFileRef(
                absolutePath: '/tmp/photo.png',
                displayName: 'photo.png',
              ),
            ],
            onOpen: opened.add,
          ),
        ),
      ),
    );

    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);

    await tester.tap(find.text('a.dart'));
    expect(opened, ['/repo/src/a.dart']);
  });

  testWidgets('empty refs builds nothing interactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposeAtFileChipRow(refs: const [], onOpen: (_) {}),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });
}
```

Prefer plain `MaterialApp` (chip row uses `Theme.of(context).colorScheme` + `WorkspaceChatLandingPalette`). If a later change needs `TpTheme`, pass `data: TpThemeData.fromColorScheme(...)` — never bare `TpTheme(child: …)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/compose/compose_at_file_chip_row_test.dart`

Expected: FAIL (widget missing)

- [ ] **Step 3: Implement chip row**

Create `client/lib/widgets/compose/compose_at_file_chip_row.dart`:

- Horizontal `SingleChildScrollView` + `Row` of chips
- Style: reuse landing palette (`WorkspaceChatLandingPalette`) — fill `chipFill`, border `border`, muted label — similar density to toolbar chips but **no** dropdown chevron and **no** ×
- Leading: if `isImagePreviewPath(ref.absolutePath)`, try `Image.file(File(path), width: 20, height: 20, fit: BoxFit.cover, errorBuilder: …)` else `Icons.insert_drive_file_outlined`
- `InkWell` / `Material` tap → `onOpen(ref.absolutePath)`
- Empty `refs` → `SizedBox.shrink()`

Keep the widget under ~120 lines; extract a private `_ComposeAtFileChip` if needed.

- [ ] **Step 4: Run tests PASS**

Run: `cd client && flutter test test/widgets/compose/compose_at_file_chip_row_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_at_file_chip_row.dart \
  client/test/widgets/compose/compose_at_file_chip_row_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): add @ file chip row widget

EOF
)"
```

---

### Task 3: Mount chip row in `WorkspaceComposeCard`

**Files:**
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Modify: `client/test/widgets/compose/workspace_compose_card_test.dart`
- Also update any other test helpers that construct `WorkspaceComposeCard` if a new required param is added — prefer **optional** `ValueChanged<String>? onOpenAtFile` so existing call sites compile unchanged.

- [ ] **Step 1: Write failing card test**

Extend `workspace_compose_card_test.dart`:

```dart
testWidgets('shows at-file chip row when controller has @ refs', (tester) async {
  final controller = TextEditingController(text: '@src/main.dart hello');
  addTearDown(controller.dispose);
  final opened = <String>[];

  await tester.pumpWidget(
    // same pumpCard shell, but pass controller + onOpenAtFile: opened.add
    pumpCard(
      chrome: unboundChrome,
      controller: controller,
      onOpenAtFile: opened.add,
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('main.dart'), findsWidgets); // chip (+ maybe nowhere else)
  expect(find.byType(ComposeAtFileChipRow), findsOneWidget);

  await tester.tap(find.descendant(
    of: find.byType(ComposeAtFileChipRow),
    matching: find.text('main.dart'),
  ));
  expect(opened.single, '/tmp/src/main.dart'); // workspaceRoot in pumpCard is '/tmp'
});
```

Update `pumpCard` to accept optional `onOpenAtFile` and forward it.

- [ ] **Step 2: Run test — expect FAIL** (no chip row yet)

Run: `cd client && flutter test test/widgets/compose/workspace_compose_card_test.dart`

- [ ] **Step 3: Wire chip row into the card**

In `WorkspaceComposeCard`:

1. Add `final ValueChanged<String>? onOpenAtFile;`
2. In the `Column` children (inside `ComposeFocusShell` padding), **above** `field`:

```dart
ListenableBuilder(
  listenable: controller,
  builder: (context, _) {
    final refs = parseComposeAtFileRefs(
      controller.text,
      workspaceRoot: workspaceRoot,
    );
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: ComposeAtFileChipRow(
        refs: refs,
        onOpen: onOpenAtFile ?? (_) {},
      ),
    );
  },
),
field,
```

Import `compose_at_file_refs.dart` and `compose_at_file_chip_row.dart`.

- [ ] **Step 4: Run card tests PASS**

Run: `cd client && flutter test test/widgets/compose/workspace_compose_card_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/workspace_compose_card.dart \
  client/test/widgets/compose/workspace_compose_card_test.dart
git commit -m "$(cat <<'EOF'
feat(compose): show @ file chips above compose input

EOF
)"
```

---

### Task 4: Host wiring (open on tap)

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart` (~`WorkspaceComposeCard(` call)
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` (~`WorkspaceComposeCard(` call)

- [ ] **Step 1: Session continue compose**

Near the existing `WorkspaceComposeCard(` in `session_chat_view.dart`, add:

```dart
onOpenAtFile: (path) {
  unawaited(
    context.read<WorkbenchEditorOpener>().openFile(
      widget.session.workspaceId,
      path,
      preview: true,
    ),
  );
},
```

Ensure `WorkbenchEditorOpener` is already imported / provided (session view already reads it elsewhere ~line 1325). Prefer passing `fs:` only if this host already has a clear `Filesystem` for the workspace (e.g. from `EditorCubit` / file-tree cubit); otherwise rely on opener default — do not invent a new FS lookup.

- [ ] **Step 2: Landing unbound compose**

Same pattern in `unbound_compose_body.dart`:

```dart
onOpenAtFile: (path) {
  unawaited(
    context.read<WorkbenchEditorOpener>().openFile(
      widget.workspace.workspaceId,
      path,
      preview: true,
    ),
  );
},
```

Add imports: `flutter_bloc` / `WorkbenchEditorOpener` if missing; `dart:async` `unawaited` if missing.

- [ ] **Step 3: Analyze + focused tests**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/compose/compose_at_file_refs.dart \
  lib/widgets/compose/compose_at_file_chip_row.dart \
  lib/widgets/compose/workspace_compose_card.dart \
  lib/pages/chat/session_chat_view.dart \
  lib/pages/home_workspace/workspace/unbound_compose_body.dart

cd client && flutter test \
  test/services/compose/compose_at_file_refs_test.dart \
  test/widgets/compose/compose_at_file_chip_row_test.dart \
  test/widgets/compose/workspace_compose_card_test.dart
```

Expected: no errors; tests PASS

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart \
  client/lib/pages/home_workspace/workspace/unbound_compose_body.dart
git commit -m "$(cat <<'EOF'
feat(compose): open @ file chips in workbench editor

EOF
)"
```

---

### Task 5: Manual smoke (human or agent with UI)

- [ ] **Step 1: Smoke checklist**

1. Landing: paste image → chip row shows basename; tap opens image preview; Backspace removes `@` token and chip disappears.
2. Landing: `@` mention a workspace file → chip appears; tap opens editor.
3. Session continue: same for attach + `@`.
4. `/skill` only → no chip row.
5. Inline teal pills still present in the textarea.

- [ ] **Step 2: Final commit only if smoke found fixes; otherwise done**

---

## Out of scope (do not implement)

- Chip × / attachment disk cleanup  
- Hiding / shortening inline `@` pills  
- Structured attachment list / submit format changes  
- OS default-app open  
