# Compose Model Cascade Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Simple-mode model chip menu (+ Custom modal) with a cascading submenu menu: presets group → CLI → Provider → Model → Effort, selectable in one gesture.

**Architecture:** New `TpActionMenuSpec.submenu` type + nested-`TpPopover` rendering in `shared_ui`'s action menu (hover-intent open, sibling mutex, per-panel search/scroll). App layer adds a pure spec builder (`buildComposeModelCascadeMenuSpecs`) fed by capability-driven resolvers; landing and in-chat chips consume the same builder with different grouping.

**Tech Stack:** Flutter, `flutter_bloc`, shared_ui (`TpPopover`/`TpPortal` overlay stack), existing `ProviderCapability` / `CliEffortCapability` registry APIs.

**Spec:** `docs/superpowers/specs/2026-08-26-compose-model-cascade-menu-design.md`

## Global Constraints

- Analyze gate: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- Test gates: shared_ui → `cd client/packages/shared_ui && flutter test`; app → `cd client && dart run tool/run_tests.dart`
- l10n: add keys to **both** `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` only
- No `if (cli == …)` special cases — all CLI differences via `registry.capability<ProviderCapability>(cli)`
- No comments unless mirroring an adjacent existing comment style; no `print`
- Existing `.item`/`.divider` semantics of `TpActionMenuSpec` must not change (all current callers keep passing)
- Selection values are typed sentinel objects (see Task 4) so one `onSelected(Object?)` path decodes unambiguously

---

### Task 1: shared_ui — submenu spec type, coordinator, nested popover item

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart`
- Modify: `client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart` (append group)

**Interfaces:**
- Produces: `TpActionMenuSpec.submenu({Object? value, IconData? icon, Widget? iconWidget, required String label, Widget? subtitle, bool selected = false, bool enabled = true, bool searchable = false, required List<TpActionMenuSpec> children, VoidCallback? onOpen})`, `bool get isSubmenu`
- Produces: `class TpActionMenuSubmenuCoordinator extends ChangeNotifier { Object? get openId; void open(Object id); void close(Object id); }`
- Produces: `TpActionMenuItem` gains optional `bool highlighted = false` param (OR-ed into hover fill)
- Later tasks rely on: leaf selection anywhere closes the whole cascade through the root controller passed to `buildTpActionMenuChildren`

- [ ] **Step 1: Write failing tests**

Append to `tp_action_menu_test.dart` inside `main()`:

```dart
group('submenu', () {
  List<TpActionMenuSpec> specs({required bool withSubmenu}) => [
        TpActionMenuSpec.item(value: 'plain', label: 'Plain', icon: Icons.star),
        if (withSubmenu)
          TpActionMenuSpec.submenu(
            value: 'branch',
            label: 'Branch',
            icon: Icons.folder,
            children: [
              TpActionMenuSpec.item(value: 'leaf', label: 'Leaf', icon: Icons.leaf),
            ],
          ),
      ];

  Widget host(List<TpActionMenuSpec> specs, {void Function(Object?)? onSelected}) =>
      wrap(
        TpActionMenuButton(specs: specs, onSelected: onSelected ?? (_) {}),
      );

  testWidgets('tap opens submenu and shows child', (tester) async {
    var onOpened = 0;
    await tester.pumpWidget(host([
      TpActionMenuSpec.submenu(
        value: 'branch',
        label: 'Branch',
        icon: Icons.folder,
        onOpen: () => onOpened++,
        children: [
          TpActionMenuSpec.item(value: 'leaf', label: 'Leaf', icon: Icons.leaf),
        ],
      ),
    ]));
    await tester.tap(find.text('Branch'));
    await tester.pumpAndSettle();
    expect(find.text('Leaf'), findsOneWidget);
    expect(onOpened, 1);
  });

  testWidgets('selecting a leaf fires onSelect and closes everything',
      (tester) async {
    final picked = <Object?>[];
    await tester.pumpWidget(host(specs(withSubmenu: true), onSelected: picked.add));
    await tester.tap(find.text('Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leaf'));
    await tester.pumpAndSettle();
    expect(picked, ['leaf']);
    expect(find.text('Leaf'), findsNothing);
    expect(find.text('Plain'), findsNothing);
  });

  testWidgets('opening a sibling submenu closes the previously open branch',
      (tester) async {
    TpActionMenuSpec branch(String label) => TpActionMenuSpec.submenu(
          value: label,
          label: label,
          icon: Icons.folder,
          children: [
            TpActionMenuSpec.item(value: '$label-child', label: '$label-child', icon: Icons.leaf),
          ],
        );
    await tester.pumpWidget(host([branch('A'), branch('B')]));
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('A-child'), findsOneWidget);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('A-child'), findsNothing);
    expect(find.text('B-child'), findsOneWidget);
  });

  testWidgets('hover intent opens after delay', (tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pumpWidget(host(specs(withSubmenu: true)));
    await tester.tap(find.text('Branch'));
    await tester.pumpAndSettle();
    // close again to test hover path from scratch
    await tester.tap(find.text('Branch'));
    await tester.pumpAndSettle();
    await gesture.moveTo(tester.getCenter(find.text('Branch')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Leaf'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Leaf'), findsOneWidget);
  });
});
```

Add import at top of the test file:

```dart
import 'package:flutter/gestures.dart';
import 'dart:async';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: FAIL — `TpActionMenuSpec.submenu` undefined.

- [ ] **Step 3: Implement**

In `tp_action_menu.dart`:

1. Add `import 'dart:async';` at top.

2. Add coordinator class above `TpActionMenuSpec`:

```dart
/// Tracks which sibling submenu is open within one panel level.
/// A fresh coordinator is created per [buildTpActionMenuChildren] invocation,
/// giving each panel level its own mutually-exclusive open slot.
class TpActionMenuSubmenuCoordinator extends ChangeNotifier {
  Object? _openId;

  Object? get openId => _openId;

  void open(Object id) {
    if (_openId == id) return;
    _openId = id;
    notifyListeners();
  }

  void close(Object id) {
    if (_openId != id) return;
    _openId = null;
    notifyListeners();
  }
}
```

3. Extend `TpActionMenuSpec`: add fields + submenu constructor. Add to every existing constructor's initializer list: `children = null, searchable = false, onOpen = null`.

```dart
  const TpActionMenuSpec.submenu({
    this.value,
    this.icon,
    this.iconWidget,
    required this.label,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.searchable = false,
    required List<TpActionMenuSpec> children,
    this.onOpen,
  }) : assert(icon != null || iconWidget != null),
       assert(children.isNotEmpty),
       isDivider = false,
       subtitleSuffix = null,
       trailing = null,
       destructive = false,
       onAction = null,
       tooltip = null,
       children = children;

  /// Non-null for [TpActionMenuSpec.submenu].
  final List<TpActionMenuSpec>? children;
  final bool searchable;
  final VoidCallback? onOpen;

  bool get isSubmenu => !isDivider && children != null;
```

4. Rewrite `buildTpActionMenuChildren`:

```dart
List<Widget> buildTpActionMenuChildren({
  required BuildContext context,
  required List<TpActionMenuSpec> specs,
  required TpActionMenuController menuController,
  required ValueChanged<Object?> onSelect,
}) {
  final coordinator = TpActionMenuSubmenuCoordinator();
  return [
    for (var i = 0; i < specs.length; i++)
      if (specs[i].isDivider)
        const TpActionMenuDivider()
      else if (specs[i].isSubmenu)
        TpActionMenuSubmenuItem(
          id: i,
          spec: specs[i],
          coordinator: coordinator,
          rootMenuController: menuController,
          onSelect: onSelect,
        )
      else
        _specToMenuItem(
          context: context,
          spec: specs[i],
          menuController: menuController,
          onSelect: onSelect,
        ),
  ];
}
```

5. Add the item widget + panel (Task 2 fills search/scroll; here render plain):

```dart
class TpActionMenuSubmenuItem extends StatefulWidget {
  const TpActionMenuSubmenuItem({
    super.key,
    required this.id,
    required this.spec,
    required this.coordinator,
    required this.rootMenuController,
    required this.onSelect,
  });

  final int id;
  final TpActionMenuSpec spec;
  final TpActionMenuSubmenuCoordinator coordinator;
  final TpActionMenuController rootMenuController;
  final ValueChanged<Object?> onSelect;

  @override
  State<TpActionMenuSubmenuItem> createState() =>
      _TpActionMenuSubmenuItemState();
}

class _TpActionMenuSubmenuItemState extends State<TpActionMenuSubmenuItem> {
  final _popover = TpPopoverController();
  Timer? _hoverTimer;

  static const _hoverIntentDelay = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_syncWithCoordinator);
  }

  @override
  void didUpdateWidget(covariant TpActionMenuSubmenuItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_syncWithCoordinator);
      widget.coordinator.addListener(_syncWithCoordinator);
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    widget.coordinator.removeListener(_syncWithCoordinator);
    super.dispose();
  }

  void _syncWithCoordinator() {
    if (widget.coordinator.openId != widget.id && _popover.isOpen) {
      _popover.hide();
    }
  }

  bool get _isOpen => _popover.isOpen;

  void _openNow() {
    if (_isOpen) return;
    widget.coordinator.open(widget.id);
    widget.spec.onOpen?.call();
    _popover.show();
  }

  void _toggle() {
    if (_isOpen) {
      widget.coordinator.close(widget.id);
    } else {
      _openNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return TpPopover(
      controller: _popover,
      padding: TpActionMenuMetrics.panelPadding,
      decoration: TpActionMenuMetrics.panelDecoration(context),
      anchor: const TpAnchor(
        childAlignment: Alignment.topLeft,
        overlayAlignment: Alignment.centerRight,
        offset: Offset(-4, 0),
      ),
      popover: (ctx) => IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buildTpActionMenuChildren(
              context: ctx,
              specs: spec.children!,
              menuController: widget.rootMenuController,
              onSelect: widget.onSelect,
            ),
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) {
          _hoverTimer?.cancel();
          _hoverTimer = Timer(_hoverIntentDelay, _openNow);
        },
        onExit: (_) => _hoverTimer?.cancel(),
        child: TpActionMenuItem(
          icon: spec.icon,
          iconWidget: spec.iconWidget,
          label: spec.label ?? '',
          subtitle: spec.subtitle,
          enabled: spec.enabled,
          highlighted: _popover.isOpen,
          onTap: spec.enabled ? _toggle : null,
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: TpActionMenuMetrics.iconSize(context),
            color: TpTextStyles.of(context).md.color?.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
```

Note: `TpActionMenuItem.trailing` renders only when not `selected`; selected submenu rows show the check instead — acceptable.

6. Add `highlighted` to `TpActionMenuItem` (param, field, and OR into fill):

```dart
this.highlighted = false,
...
final bool highlighted;
// in build:
color: (_hovered || highlighted) && widget.enabled && widget.onTap != null
    ? hoverFill
    : Colors.transparent,
```

7. Scroll support for tall submenus: wrap the inner `Column` of the popover panel in `SingleChildScrollView` — done in Task 2 alongside search; skip here.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: PASS (all pre-existing tests included).

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart
git commit -m "feat(shared-ui): cascade submenu support in TpActionMenu"
```

---

### Task 2: shared_ui — submenu scroll, search filter, edge clamp

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart`
- Modify: `client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart` (append)

**Interfaces:**
- Consumes: Task 1 types.
- Produces: `TpActionMenuMetrics.searchThreshold = 10`; submenu panels taller than 60% viewport scroll; `searchable: true` panels show a filter TextField when `children.length > searchThreshold`.

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('searchable submenu filters items by query', (tester) async {
  await tester.pumpWidget(host([
    TpActionMenuSpec.submenu(
      value: 'models',
      label: 'Models',
      icon: Icons.memory,
      searchable: true,
      children: [
        for (final m in ['sonnet-x', 'opus-y', 'haiku-z'])
          TpActionMenuSpec.item(value: m, label: m, icon: Icons.memory),
      ],
    ),
  ]));
  // >threshold children required; use 11 items instead in real test:
```

Use 11 children in the actual test (threshold 10): generate `for (var i = 0; i < 11; i++) TpActionMenuSpec.item(value: 'model-$i', label: 'model-$i', icon: Icons.memory)` plus none else; then:

```dart
  await tester.tap(find.text('Models'));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'model-1');
  await tester.pumpAndSettle();
  expect(find.text('model-10'), findsOneWidget);
  expect(find.text('model-2'), findsNothing);

testWidgets('tall submenu scrolls and stays clamped in viewport', (tester) async {
  await tester.pumpWidget(host([
    TpActionMenuSpec.submenu(
      value: 'big',
      label: 'Big',
      icon: Icons.list,
      children: [
        for (var i = 0; i < 40; i++)
          TpActionMenuSpec.item(value: 'row-$i', label: 'Row $i', icon: Icons.label),
      ],
    ),
  ]));
  await tester.tap(find.text('Big'));
  await tester.pumpAndSettle();
  expect(find.text('Row 39'), findsNothing);
  await tester.scrollUntilVisible(find.text('Row 39'), 200);
  expect(find.text('Row 39'), findsOneWidget);
});
```

(`scrollUntilVisible` needs the scrollable inside a sized viewport — the ConstrainedBox from Task 1 provides it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: FAIL — no TextField appears; Row 39 unreachable.

- [ ] **Step 3: Implement**

1. `TpActionMenuMetrics`: `static const int searchThreshold = 10;`

2. Extract the popover content into a stateful panel inside `_TpActionMenuSubmenuItemState` file scope:

```dart
class _TpActionMenuSubmenuPanel extends StatefulWidget {
  const _TpActionMenuSubmenuPanel({
    required this.children,
    required this.searchable,
    required this.rootMenuController,
    required this.onSelect,
  });

  final List<TpActionMenuSpec> children;
  final bool searchable;
  final TpActionMenuController rootMenuController;
  final ValueChanged<Object?> onSelect;

  @override
  State<_TpActionMenuSubmenuPanel> createState() =>
      _TpActionMenuSubmenuPanelState();
}

class _TpActionMenuSubmenuPanelState extends State<_TpActionMenuSubmenuPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final visible = needle.isEmpty
        ? widget.children
        : widget.children
              .where((s) => (s.label ?? '').toLowerCase().contains(needle))
              .toList(growable: false);
    final showSearch =
        widget.searchable && widget.children.length > TpActionMenuMetrics.searchThreshold;
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: TpTextStyles.of(context).md,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search,
                        size: TpActionMenuMetrics.iconSize(context)),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: visible.isEmpty
                      ? [const SizedBox(height: 4)]
                      : buildTpActionMenuChildren(
                          context: context,
                          specs: visible,
                          menuController: widget.rootMenuController,
                          onSelect: widget.onSelect,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

3. Point `_TpActionMenuSubmenuItem`'s `popover:` builder at `_TpActionMenuSubmenuPanel(children: spec.children!, searchable: spec.searchable, ...)` (replacing the inline Column).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart
git commit -m "feat(shared-ui): submenu search filter and scroll clamping"
```

---

### Task 3: shared_ui — minimal keyboard navigation

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart`
- Modify: `client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart` (append)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: rows activate with Enter/Space; ←/Esc closes the open submenu level and refocuses its parent row; → opens and focuses first child row.

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('Enter activates focused leaf; Esc closes one submenu level',
    (tester) async {
  final picked = <Object?>[];
  await tester.pumpWidget(host(specs(withSubmenu: true), onSelected: picked.add));
  await tester.tap(find.text('Branch')); // mouse-open for setup
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape); // closes submenu only
  await tester.pumpAndSettle();
  expect(find.text('Leaf'), findsNothing);
  expect(find.text('Plain'), findsOneWidget); // root still open
});

testWidgets('arrow-right opens submenu from focused parent row', (tester) async {
  await tester.pumpWidget(host(specs(withSubmenu: true)));
  await tester.tap(find.text('Branch'));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  // focus returned to parent row; arrow right re-opens
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
  expect(find.text('Leaf'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: FAIL — Esc currently does nothing at submenu level (root Esc binding exists via TpPopover but focus isn't inside it), arrow-right no-op.

- [ ] **Step 3: Implement**

1. `_TpActionMenuSubmenuItemState`: add `final _rowFocus = FocusNode(debugLabel: 'tp-submenu-row');` (dispose it).

2. Wrap the item's `TpActionMenuItem` in keyboard bindings:

```dart
child: CallbackShortcuts(
  bindings: {
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        spec.enabled ? _openViaKeyboard : () {},
  },
  child: Focus(
    focusNode: _rowFocus,
    child: MouseRegion(... existing ...),
  ),
),

void _openViaKeyboard() {
  _openNow(focusPanel: true);
}
```

Change `_openNow` signature: `_openNow({bool focusPanel = false})`; when `focusPanel`, set `_focusPanelNextFrame = true` and `setState`, and in the panel builder pass `autofocusFirstRow: _focusPanelNextFrame` then reset flag post-frame.

3. `_TpActionMenuSubmenuPanel`: accept `VoidCallback onDismiss` + `FocusScopeNode panelScope`; wrap content:

```dart
CallbackShortcuts(
  bindings: {
    const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
    const SingleActivator(LogicalKeyboardKey.arrowLeft): onDismiss,
  },
  child: FocusScope(
    node: panelScope,
    autofocus: autofocusFirstRow,
    child: ...existing column...,
  ),
),
```

`onDismiss` in item state: `{ widget.coordinator.close(widget.id); _rowFocus.requestFocus(); }`. Create `panelScope` per item (dispose). Give rows inside panels activation keys: extend `TpActionMenuItem` build — wrap its GestureDetector's parent in:

```dart
Shortcuts(
  shortcuts: const {
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  },
  child: Actions(
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) { widget.onTap?.call(); return null; },
      ),
    },
    child: Focus(child: row),
  ),
)
```

and wrap each panel's children list in `FocusTraversalGroup(...)`. Enter on a submenu row should toggle like tap: since `onTap: _toggle` flows through the same Actions path, Enter on parent toggles too (acceptable).

4. Root-level Esc already hides root via `TpPopover`'s own CallbackShortcuts when focus sits in the root panel; submenu panels now swallow Esc first (topmost FocusScope wins), matching per-level exit.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client/packages/shared_ui && flutter test test/components/action_menu/tp_action_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/packages/shared_ui/lib/src/components/action_menu/tp_action_menu.dart client/packages/shared_ui/test/components/action_menu/tp_action_menu_test.dart
git commit -m "feat(shared-ui): submenu keyboard navigation"
```

---

### Task 4: app — cascade view models, resolver, and spec builder

**Files:**
- Modify: `client/lib/widgets/compose/compose_model_preset_chip.dart` (add types + builders; keep existing exports until Task 7 deletes them)
- Create: `client/test/widgets/compose/compose_cascade_builder_test.dart`

**Interfaces:**
- Consumes: Task 1–3 `TpActionMenuSpec.submenu`; existing `presetsForCli` not needed here (caller filters).
- Produces:

```dart
sealed class CascadeSelection {
  final CliTool cli;
  final String providerId;
  const CascadeSelection({required this.cli, required this.providerId});
}
final class CascadeModelPick extends CascadeSelection {
  // Direct model-row pick: effort stays empty (identical to today's modal submit).
  final String modelId;
  const CascadeModelPick({required super.cli, required super.providerId, required this.modelId});
}
final class CascadeEffortPick extends CascadeSelection {
  final String modelId;
  final String effort;
  const CascadeEffortPick({required super.cli, required super.providerId, required this.modelId, required this.effort});
}
final class CascadeCustomModelRequest extends CascadeSelection {
  const CascadeCustomModelRequest({required super.cli, required super.providerId});
}

enum ComposeModelPresetChipAction { custom, manage, savePreset }

class ComposeCascadeProvider {
  final String id;
  final String name;
  final bool supportsCustomModelEntry;
  final List<String> models;
  final Map<String, List<String>> effortByModel; // value empty ⇒ model is a leaf
  const ComposeCascadeProvider({...});
}
class ComposeCascadeCliGroup {
  final CliTool cli;
  final List<ComposeCascadeProvider> providers;
  const ComposeCascadeCliGroup({...});
}

List<ComposeCascadeCliGroup> resolveComposeCascadeCliGroups({
  required CliToolRegistry registry,
  required Map<CliTool, List<AppProviderConfig>> providersByCli,
  required List<CliTool> cliItems,
})

List<TpActionMenuSpec> buildComposeModelCascadeMenuSpecs({
  required List<CliPreset> presets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  required String defaultEffortLabel,
  required String customModelIdLabel,
  required String noModelsLabel,
  required String savePresetLabel,
  required String managePresetsLabel,
  required List<ComposeCascadeCliGroup> cliGroups,
  required bool groupByCli, // landing: true; in-chat single locked CLI: false
  void Function(CliTool cli, String providerId)? onModelsOpened,
})
```

- [ ] **Step 1: Write failing tests**

`client/test/widgets/compose/compose_cascade_builder_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

AppProviderConfig provider(String id, {String? name, Map<String, Object?> config = const {}}) =>
    AppProviderConfig(id: id, cli: CliTool.claude, name: name ?? id, config: config);

CliPreset preset(String id, String name) => CliPreset(
      id: id, name: name, cli: CliTool.claude,
      provider: 'p1', model: 'm1', effort: '',
      createdAt: 0, updatedAt: 0,
    );

void main() {
  final registry = CliToolRegistry.builtIn();

  group('resolveComposeCascadeCliGroups', () {
    test('builds providers with models and custom-entry flag', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          CliTool.claude: [
            provider('official', name: 'Claude Official',
              config: {'models': {'m-a': {}, 'm-b': {}}}),
          ],
        },
        cliItems: [CliTool.claude],
      );
      expect(groups, hasLength(1));
      final p = groups.single.providers.single;
      expect(p.supportsCustomModelEntry, isTrue); // claude picker mode
      expect(p.models, containsAll(['m-a', 'm-b']));
    });

    test('skips CLIs without providers or capability', () {
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {CliTool.codex: []},
        cliItems: [CliTool.codex, CliTool.claude],
      );
      expect(groups.where((g) => g.cli == CliTool.codex), isEmpty);
    });
  });

  group('buildComposeModelCascadeMenuSpecs', () {
    test('presets group, provider drill-down, effort leaves, bottom actions', () {
      final groups = [
        ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
          ComposeCascadeProvider(
            id: 'p1', name: 'DeepSeek',
            supportsCustomModelEntry: true,
            models: ['deepseek-chat'],
            effortByModel: {'deepseek-chat': ['low', 'high']},
          ),
        ]),
      ];
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: [preset('preset-1', 'Work')],
        selectedPresetId: 'preset-1',
        emptyHintLabel: 'No presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom model ID…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save as preset…',
        managePresetsLabel: 'Manage',
        cliGroups: groups,
        groupByCli: true,
      );

      final presetRow = specs.first;
      expect(presetRow.selected, isTrue);
      expect(presetRow.value, 'preset-1');

      final cliSubmenu = specs.whereType<TpActionMenuSpec>().toList();
      final providerLevel = cliSubmenu.last.children!;
      final providerSpec = providerLevel.first;
      expect(providerSpec.isSubmenu, isTrue);

      final modelLevel = providerSpec.children!;
      final modelSpec = modelLevel.first;
      expect(modelSpec.isSubmenu, isTrue); // has effort candidates ⇒ submenu

      final effortLevel = modelSpec.children!;
      expect(effortLevel.first.value, isA<CascadeModelPick>()); // 默认 entry
      expect(effortLevel[1].value, isA<CascadeEffortPick>());
      expect(modelLevel.last.value, isA<CascadeCustomModelRequest>());

      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.savePreset),
        isTrue,
      );
      expect(
        specs.any((s) => s.value == ComposeModelPresetChipAction.manage),
        isTrue,
      );
    });

    test('model without effort candidates is a direct leaf', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'No presets',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
            ComposeCascadeProvider(
              id: 'p1', name: 'X',
              supportsCustomModelEntry: false,
              models: ['plain-model'],
              effortByModel: {'plain-model': []},
            ),
          ]),
        ],
        groupByCli: false,
      );
      // top level (no CLI wrapper): divider, provider submenu, divider, save, manage
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      final modelRows = providerSpec.children!;
      final leaf = modelRows.firstWhere((s) => s.value is CascadeModelPick);
      expect(leaf.isSubmenu, isFalse);
      expect((leaf.value as CascadeModelPick).modelId, 'plain-model');
      expect(modelRows.any((s) => s.value is CascadeCustomModelRequest), isFalse);
    });

    test('empty model catalog shows disabled row but keeps custom entry', () {
      final specs = buildComposeModelCascadeMenuSpecs(
        presets: const [],
        selectedPresetId: null,
        emptyHintLabel: 'x',
        defaultEffortLabel: 'Default',
        customModelIdLabel: 'Custom…',
        noModelsLabel: 'No models',
        savePresetLabel: 'Save',
        managePresetsLabel: 'Manage',
        cliGroups: [
          ComposeCascadeCliGroup(cli: CliTool.claude, providers: [
            ComposeCascadeProvider(
              id: 'p1', name: 'X',
              supportsCustomModelEntry: true,
              models: [],
              effortByModel: {},
            ),
          ]),
        ],
        groupByCli: false,
      );
      final providerSpec = specs.firstWhere((s) => s.isSubmenu);
      expect(
        providerSpec.children!.any((s) => !s.isDivider && s.enabled == false && s.label == 'No models'),
        isTrue,
      );
      expect(
        providerSpec.children!.any((s) => s.value is CascadeCustomModelRequest),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/widgets/compose/compose_cascade_builder_test.dart`
Expected: compile errors (types undefined).

- [ ] **Step 3: Implement** in `compose_model_preset_chip.dart`

Sentinels + view models exactly as in Interfaces. Resolver implementation:

```dart
List<ComposeCascadeCliGroup> resolveComposeCascadeCliGroups({
  required CliToolRegistry registry,
  required Map<CliTool, List<AppProviderConfig>> providersByCli,
  required List<CliTool> cliItems,
}) {
  final groups = <ComposeCascadeCliGroup>[];
  for (final cli in cliItems) {
    final capability = registry.capability<ProviderCapability>(cli);
    if (capability == null) continue;
    final providers = [...providersByCli[cli] ?? const <AppProviderConfig>[]]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (providers.isEmpty) continue;
    final cascadeProviders = <ComposeCascadeProvider>[];
    for (final p in providers) {
      final mode = capability.pickerMode(p);
      final models = mode == ProviderModelPickerMode.hidden
          ? const <String>[]
          : capability.modelCandidates(provider: p, providerId: p.id, currentModel: '');
      cascadeProviders.add(ComposeCascadeProvider(
        id: p.id,
        name: p.name,
        supportsCustomModelEntry:
            mode == ProviderModelPickerMode.catalogWithCustomEntry,
        models: models,
        effortByModel: {
          for (final m in models)
            m: capability.isApplicable(model: m)
                ? capability.effortCandidates(model: m, provider: p)
                : const <String>[],
        },
      ));
    }
    groups.add(ComposeCascadeCliGroup(cli: cli, providers: cascadeProviders));
  }
  return groups;
}
```

Builder core (imports: `../../models/app_provider_config.dart`, `../../services/cli/registry/capabilities/provider_capability.dart`, `../../services/cli/registry/cli_tool_registry.dart`, `package:shared_ui/shared_ui.dart` already present):

```dart
List<TpActionMenuSpec> buildComposeModelCascadeMenuSpecs({
  required List<CliPreset> presets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  required String defaultEffortLabel,
  required String customModelIdLabel,
  required String noModelsLabel,
  required String savePresetLabel,
  required String managePresetsLabel,
  required List<ComposeCascadeCliGroup> cliGroups,
  required bool groupByCli,
  void Function(CliTool cli, String providerId)? onModelsOpened,
}) {
  List<TpActionMenuSpec> providerChildren(ComposeCascadeCliGroup group,
      ComposeCascadeProvider p) {
    final rows = <TpActionMenuSpec>[
      if (p.models.isEmpty && !p.supportsCustomModelEntry)
        TpActionMenuSpec.item(
          value: null, icon: Icons.cloud_off_outlined,
          label: noModelsLabel, enabled: false)
      else ...[
        for (final model in p.models)
          if ((p.effortByModel[model]?.isNotEmpty ?? false))
            TpActionMenuSpec.submenu(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              icon: Icons.memory_outlined,
              label: model,
              onOpen: () => onModelsOpened?.call(group.cli, p.id),
              children: [
                TpActionMenuSpec.item(
                  value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
                  icon: Icons.speed_outlined, label: defaultEffortLabel,
                  selected: false),
                for (final e in p.effortByModel[model]!)
                  TpActionMenuSpec.item(
                    value: CascadeEffortPick(cli: group.cli, providerId: p.id,
                      modelId: model, effort: e),
                    icon: Icons.speed_outlined, label: e),
              ],
            )
          else
            TpActionMenuSpec.item(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              icon: Icons.memory_outlined, label: model),
        if (p.supportsCustomModelEntry)
          TpActionMenuSpec.item(
            value: CascadeCustomModelRequest(cli: group.cli, providerId: p.id),
            icon: Icons.edit_outlined, label: customModelIdLabel),
      ],
    ];
    return rows;
  }

  TpActionMenuSpec providerSpec(ComposeCascadeCliGroup group,
      ComposeCascadeProvider p) {
    return TpActionMenuSpec.submenu(
      value: p.id,
      icon: Icons.cloud_outlined,
      label: p.name,
      searchable: true,
      children: providerChildren(group, p),
    );
  }

  final specs = <TpActionMenuSpec>[
    if (presets.isEmpty)
      TpActionMenuSpec.item(value: null, icon: Icons.terminal_outlined,
        label: emptyHintLabel, enabled: false)
    else
      for (final preset in presets)
        TpActionMenuSpec.item(value: preset.id,
          iconWidget: _PresetCliMenuIcon(cli: preset.cli),
          label: preset.name, selected: preset.id == selectedPresetId),
    const TpActionMenuSpec.divider(),
    for (final group in cliGroups)
      if (!groupByCli)
        for (final p in group.providers) providerSpec(group, p)
      else if (group.providers.isNotEmpty)
        TpActionMenuSpec.submenu(
          value: group.cli,
          iconWidget: _PresetCliMenuIcon(cli: group.cli),
          label: group.cli.value,
          children: [for (final p in group.providers) providerSpec(group, p)],
        ),
    const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      value: ComposeModelPresetChipAction.savePreset,
      icon: Icons.bookmark_add_outlined, label: savePresetLabel),
    TpActionMenuSpec.item(
      value: ComposeModelPresetChipAction.manage,
      icon: Icons.add, label: managePresetsLabel),
  ];
  return specs;
}
```

Remove the placeholder `/* caller passes... */ false` comment — just write `false` (selected-state of effort entries is not tracked in v1).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/widgets/compose/compose_cascade_builder_test.dart`
Expected: PASS. Then `flutter analyze --no-fatal-infos --no-fatal-warnings` clean.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_model_preset_chip.dart client/test/widgets/compose/compose_cascade_builder_test.dart
git commit -m "feat(compose): cascade menu view models and spec builder"
```

---

### Task 5: app — custom-model-ID dialog, preset draft prefill, catalog refresh helper

**Files:**
- Modify: `client/lib/widgets/compose/simple_custom_launch_dialog.dart` (add `showComposeCustomModelIdDialog`)
- Modify: `client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart` (add `draft` param)
- Modify: `client/lib/widgets/compose/compose_model_preset_chip.dart` (add `refreshComposeCascadeCatalog`)
- Test: `client/test/widgets/compose/compose_custom_model_dialog_test.dart`

**Interfaces:**
- Consumes: `CascadeCustomModelRequest` (Task 4), `CliPresetEditDialog({existing, lockCli})`.
- Produces:

```dart
Future<String?> showComposeCustomModelIdDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}); // returns trimmed non-empty id or null

Future<void> refreshComposeCascadeCatalog(
  BuildContext context, {
  required CliTool cli,
  required String providerId,
}); // fire-and-forget refreshModelCatalog via RefreshableProviderModelCapability
```

`CliPresetEditDialog` gains `final CliPreset? draft;` (default null): `initState` uses `widget.existing ?? widget.draft` for cli/provider/model/effort seeds; `isEditing` remains based on `existing` only, so saving goes through `addPreset`.

- [ ] **Step 1: Write failing test**

```dart
testWidgets('showComposeCustomModelIdDialog returns trimmed input', (tester) async {
  String? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async {
          result = await showComposeCustomModelIdDialog(
            context, title: 'Model ID', confirmLabel: 'OK');
        },
        child: const Text('open'),
      ),
    )),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '  my-model  ');
  await tester.tap(find.widgetWithText(FilledButton, 'OK'));
  await tester.pumpAndSettle();
  expect(result, 'my-model');
});
```

- [ ] **Step 2: Run to verify failure** — function undefined. Command: `cd client && flutter test test/widgets/compose/compose_custom_model_dialog_test.dart`

- [ ] **Step 3: Implement**

In `simple_custom_launch_dialog.dart` append:

```dart
Future<String?> showComposeCustomModelIdDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => TpDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: title, onClose: () => Navigator.pop(dialogContext)),
          const SizedBox(height: 16),
          TextField(controller: controller, autofocus: true),
          TpDialogActions(children: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.cancel)),
            FilledButton(
              onPressed: () {
                final id = controller.text.trim();
                if (id.isEmpty) return;
                Navigator.pop(dialogContext, id);
              },
              child: Text(confirmLabel)),
          ]),
        ],
      ),
    ),
  );
}
```

In `cli_preset_edit_dialog.dart`:

```dart
const CliPresetEditDialog({this.existing, this.lockCli, this.draft, super.key});
/// Prefill-only four-tuple (save-as-preset); ignored when [existing] != null.
final CliPreset? draft;
// initState:
final p = widget.existing ?? widget.draft;
```

In `compose_model_preset_chip.dart`:

```dart
Future<void> refreshComposeCascadeCatalog(
  BuildContext context, {
  required CliTool cli,
  required String providerId,
}) async {
  final registry = CliToolRegistryScope.maybeOf(context);
  final capability = registry?.capability<ProviderCapability>(cli);
  if (capability is! RefreshableProviderModelCapability) return;
  SessionPreferencesCubit? prefs;
  try {
    prefs = context.read<SessionPreferencesCubit>();
  } on ProviderNotFoundException {
    prefs = null;
  }
  try {
    await capability.refreshModelCatalog(
      providerId: providerId,
      executable: prefs?.resolveExecutable(cli),
    );
  } on Object {
    // Catalog refresh is best-effort; cached candidates stay usable.
  }
}
```

Imports: `package:flutter_bloc/flutter_bloc.dart`, `../../cubits/session_preferences_cubit.dart`, `../../services/cli/registry/cli_tool_registry_scope.dart`.

- [ ] **Step 4: Run to verify pass + analyze**

Run: `cd client && flutter test test/widgets/compose/compose_custom_model_dialog_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/simple_custom_launch_dialog.dart client/lib/pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart client/lib/widgets/compose/compose_model_preset_chip.dart client/test/widgets/compose/compose_custom_model_dialog_test.dart
git commit -m "feat(compose): custom model id dialog, preset draft prefill, catalog refresh"
```

---

### Task 6: app — l10n keys + landing wiring (UnboundComposeBody)

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (then regenerate: `cd client && flutter gen-l10n`)
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`

**Interfaces:**
- Consumes: Tasks 4–5 outputs.
- Produces: landing Simple chip builds cascade specs and decodes sentinels into `landingDraftSelectingCustom`; new l10n getters used later by Task 7.

- [ ] **Step 1: Add l10n keys**

| Key | en | zh |
|---|---|---|
| `composeCascadeSavePreset` | Save current as preset… | 保存当前为预设… |
| `composeCascadeDefaultEffort` | Default | 默认 |
| `composeCascadeCustomModelId` | Custom model ID… | 自定义模型 ID… |
| `composeCascadeCustomModelIdTitle` | Custom model ID | 自定义模型 ID |
| `composeCascadeNoModels` | No model catalog | 暂无模型目录 |

Regenerate localizations (`flutter gen-l10n`) or run the app once.

- [ ] **Step 2: Write failing handler test (pure decode logic)**

Extract the decode as a testable static on the body file? The body is page code; instead put decode helper in `compose_model_preset_chip.dart`:

```dart
/// Decodes a cascade menu value into a concrete launch four-tuple request.
/// Returns null when [value] needs dialog interaction first (custom model id)
/// or is a pure action (manage/save-preset handled by callers).
SimpleLaunchFourTuple? decodeComposeCascadeValue(Object? value) {
  if (value is CascadeEffortPick) {
    return SimpleLaunchFourTuple(cli: value.cli, providerId: value.providerId,
      modelId: value.modelId, effort: value.effort);
  }
  if (value is CascadeModelPick) {
    return SimpleLaunchFourTuple(cli: value.cli, providerId: value.providerId,
      modelId: value.modelId, effort: '');
  }
  return null;
}

class SimpleLaunchFourTuple {
  final CliTool cli; final String providerId; final String modelId; final String effort;
  const SimpleLaunchFourTuple({...});
}
```

Test in `compose_cascade_builder_test.dart`:

```dart
test('decodeComposeCascadeValue maps picks and ignores actions', () {
  final effort = decodeComposeCascadeValue(CascadeEffortPick(
    cli: CliTool.claude, providerId: 'p', modelId: 'm', effort: 'high'))!;
  expect(effort.effort, 'high');
  final model = decodeComposeCascadeValue(
    CascadeModelPick(cli: CliTool.claude, providerId: 'p', modelId: 'm'))!;
  expect(model.effort, isEmpty);
  expect(decodeComposeCascadeValue(ComposeModelPresetChipAction.manage), isNull);
  expect(decodeComposeCascadeValue(CascadeCustomModelRequest(
    cli: CliTool.claude, providerId: 'p')), isNull);
});
```

Write it first (fails), implement, rerun.

- [ ] **Step 3: Wire the landing**

In `_autoChipSpecs` simple branch replace `buildComposeModelPresetMenuSpecs(...)` with:

```dart
final registry = CliToolRegistryScope.of(context);
final providerCubit = context.read<AppProviderCubit>();
final cliItems = registry.launchable.map((d) => d.id).toList(growable: false);
final groups = resolveComposeCascadeCliGroups(
  registry: registry,
  providersByCli: {
    for (final cli in cliItems) cli: providerCubit.state.providersFor(cli).toList(growable: false),
  },
  cliItems: cliItems,
);
return buildComposeModelCascadeMenuSpecs(
  presets: presets,
  selectedPresetId: _selectedPresetId,
  emptyHintLabel: l10n.workspaceCliPresetsEmptyHint,
  defaultEffortLabel: l10n.composeCascadeDefaultEffort,
  customModelIdLabel: l10n.composeCascadeCustomModelId,
  noModelsLabel: l10n.composeCascadeNoModels,
  savePresetLabel: l10n.composeCascadeSavePreset,
  managePresetsLabel: l10n.workspaceCliAddPresetTitle,
  cliGroups: groups,
  groupByCli: true,
  onModelsOpened: (cli, providerId) => unawaited(
    refreshComposeCascadeCatalog(context, cli: cli, providerId: providerId),
  ),
);
```

Extend `onAutoChipSelected` (1469–1484) before the preset-id fallthrough:

```dart
final tuple = decodeComposeCascadeValue(action);
if (tuple != null) {
  await _applyCascadeLaunch(tuple);
  return;
}
if (action is CascadeCustomModelRequest) {
  await _applyCustomModelId(request: action);
  return;
}
if (action == ComposeModelPresetChipAction.savePreset) {
  _openSaveAsPresetDialog();
  return;
}
```

New methods (alongside `_openCustomLaunchDialog`):

```dart
Future<void> _applyCascadeLaunch(SimpleLaunchFourTuple tuple) async {
  setState(() => _applyDraft(landingDraftSelectingCustom(
    _currentDraft(),
    cli: tuple.cli, provider: tuple.providerId,
    model: tuple.modelId, effort: tuple.effort)));
  _persistDraft();
  _scheduleTeamLaunchReadinessCheck();
}

Future<void> _applyCustomModelId({required CascadeCustomModelRequest request}) async {
  final modelId = await showComposeCustomModelIdDialog(
    context,
    title: l10n.composeCascadeCustomModelIdTitle,
    confirmLabel: l10n.confirm,
    initial: _selectedModel ?? '',
  );
  if (!mounted || modelId == null || modelId.isEmpty) return;
  await _applyCascadeLaunch(SimpleLaunchFourTuple(
    cli: request.cli, providerId: request.providerId,
    modelId: modelId, effort: _selectedEffort ?? ''));
}

void _openSaveAsPresetDialog() {
  final draft = CliPreset(
    id: '', name: '',
    cli: _selectedCli ?? CliTool.claude,
    provider: _selectedProvider ?? '',
    model: _selectedModel ?? '',
    effort: _selectedEffort ?? '',
    createdAt: 0, updatedAt: 0,
  );
  showDialog<void>(
    context: context,
    builder: (_) => CliPresetEditDialog(draft: draft),
  );
}
```

Keep the existing `custom` enum arm removed — `ComposeModelPresetChipAction.custom` is no longer emitted by the cascade builder; delete that branch. Keep `.manage` branch unchanged.

- [ ] **Step 4: Verify**

Run: `cd client && flutter test test/widgets/compose/ && flutter analyze --no-fatal-infos --no-fatal-warnings`
Then manual smoke (optional if headless env): launch app, open Simple landing chip, drill Claude → official → model → Default; select; chip label updates.

Expected: PASS / clean; landing selection persists via existing draft store.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/widgets/compose/compose_model_preset_chip.dart client/test/widgets/compose/compose_cascade_builder_test.dart
git commit -m "feat(landing): cascade CLI→provider→model→effort menu on simple compose"
```

---

### Task 7: app — in-chat wiring; remove flat builder + ComposeModelPresetChip

**Files:**
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Modify: `client/lib/widgets/compose/compose_chrome.dart`
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart`
- Delete: `client/lib/widgets/compose/compose_model_preset_chip.dart` public legacy API (`buildComposeModelPresetMenuSpecs`, `ComposeModelPresetChip`, `ComposeModelPresetChipAction.custom`) — file retains sentinels/builders/dialog helpers
- Modify: `client/test/widgets/compose/compose_chips_test.dart`, delete flat-builder group in `client/test/widgets/compose/compose_model_preset_chip_test.dart`

**Interfaces:**
- Consumes: Task 6 l10n getters, Task 4/5 outputs.
- Produces: `BoundComposeChrome` replaces preset/custom fields with `modelChipLeading: Widget?`, `modelCascadeSpecs: List<TpActionMenuSpec>?`, `onModelCascadeSelected: ValueChanged<Object?>?`; card renders `ComposeMenuChip` when all three present.

- [ ] **Step 1: Update chrome fields**

In `compose_chrome.dart` remove: `sameCliPresets, selectedPresetId, modelPresetLabel, emptyPresetHintLabel, onPresetSelected, customLabel, customSelected, onCustom` and their `CliPreset` import if unused. Add:

```dart
final Widget? modelChipLeading;
final List<TpActionMenuSpec>? modelCascadeSpecs;
final ValueChanged<Object?>? onModelCascadeSelected;
```

In `workspace_compose_card.dart` `_boundLeadingChips` replace the `ComposeModelPresetChip(...)` block with:

```dart
if (chrome.onModelCascadeSelected != null &&
    chrome.modelCascadeSpecs != null &&
    chrome.modelPresetLabel != null) ...[
  ComposeMenuChip(
    palette: palette,
    icon: Icons.terminal_outlined,
    leading: chrome.modelChipLeading,
    label: chrome.modelPresetLabel!,
    minWidth: 200,
    specs: chrome.modelCascadeSpecs!,
    onSelected: chrome.onModelCascadeSelected!,
  ),
  SizedBox(width: spacing.sm),
],
```

(keep `modelPresetLabel: String?` field on chrome; drop `emptyPresetHintLabel` usage there.)

- [ ] **Step 2: Build specs + handler in section**

In `session_chat_compose_section.dart` build():

```dart
final providerState = context.select<AppProviderCubit, AppProviderState>(
  (c) => c.state,
);
final cascadeGroups = session.isSimple
    ? resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          lockedCli: providerState.providersFor(lockedCli).toList(growable: false),
        },
        cliItems: [lockedCli],
      )
    : const <ComposeCascadeCliGroup>[];
final cascadeSpecs = session.isSimple
    ? buildComposeModelCascadeMenuSpecs(
        presets: sameCliPresets,
        selectedPresetId: selectedPresetId,
        emptyHintLabel: l10n.workspaceCliPresetsEmptyHint,
        defaultEffortLabel: l10n.composeCascadeDefaultEffort,
        customModelIdLabel: l10n.composeCascadeCustomModelId,
        noModelsLabel: l10n.composeCascadeNoModels,
        savePresetLabel: l10n.composeCascadeSavePreset,
        managePresetsLabel: l10n.workspaceCliAddPresetTitle,
        cliGroups: cascadeGroups,
        groupByCli: false,
        onModelsOpened: (cli, pid) => unawaited(
          refreshComposeCascadeCatalog(context, cli: cli, providerId: pid),
        ),
      )
    : null;
```

Pass to chrome:

```dart
modelChipLeading: CliBrandIcon(cli: lockedCli, size: context.tpIconSizes.sm, borderRadius: 4, showBorder: false),
modelCascadeSpecs: cascadeSpecs,
onModelCascadeSelected: session.isSimple ? (v) => unawaited(_onCascadeSelected(context: context, session: session, value: v)) : null,
```

Static handler:

```dart
static Future<void> _onCascadeSelected({
  required BuildContext context,
  required AppSession session,
  required Object? value,
}) async {
  if (value is String && value.isNotEmpty) {
    // Preset row: reuse the existing preset flow.
    final preset = context.read<CliPresetsCubit>().state.presets
        .where((p) => p.id == value).firstOrNull;
    if (preset != null) {
      await _onPresetSelected(context: context, presetId: value,
        session: session, team: null, sameCliPresets: [preset],
        lockedCli: preset.cli, selectedMemberId: '');
    }
    return;
  }
  final tuple = decodeComposeCascadeValue(value);
  if (tuple != null) {
    await _applyContinueCustom(context, session: session,
      provider: tuple.providerId, model: tuple.modelId, effort: tuple.effort);
    return;
  }
  if (value is CascadeCustomModelRequest) {
    final modelId = await showComposeCustomModelIdDialog(context,
      title: context.l10n.composeCascadeCustomModelIdTitle,
      confirmLabel: context.l10n.confirm,
      initial: session.model);
    if (!context.mounted || modelId == null || modelId.isEmpty) return;
    await _applyContinueCustom(context, session: session,
      provider: value.providerId, model: modelId, effort: session.effort);
    return;
  }
  if (value == ComposeModelPresetChipAction.savePreset) {
    final cli = session.cli ?? CliTool.claude;
    showDialog<void>(
      context: context,
      builder: (_) => CliPresetEditDialog(draft: CliPreset(
        id: '', name: '', cli: cli,
        provider: session.provider, model: session.model,
        effort: session.effort, createdAt: 0, updatedAt: 0)),
    );
    return;
  }
  if (value == ComposeModelPresetChipAction.manage) {
    showDialog<void>(context: context,
      builder: (_) => const CliPresetsManageDialog());
  }
}

static Future<void> _applyContinueCustom({
  required BuildContext context,
  required AppSession session,
  required String provider,
  required String model,
  required String effort,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final live = _cubitSession(chatCubit, session.sessionId);
  if (live == null) {
    if (context.mounted) _toastContinueSaveFailed(context);
    return;
  }
  try {
    final ok = await chatCubit.setSessionContinueCustom(
      sessionId: live.sessionId, provider: provider, model: model, effort: effort);
    if (!ok && context.mounted) {
      _toastContinueSaveFailed(context);
      return;
    }
    if (context.mounted) {
      await _offerRestartAfterIdentitySwitch(context, session: live, memberId: null);
    }
  } on Object {
    if (context.mounted) _toastContinueSaveFailed(context);
  }
}
```

Clean the draft snippet while writing (no stray `presets` variable). Remove `_openContinueCustomLaunchDialog` and the `customLabel/customSelected/onCustom` arguments at the `BoundComposeChrome(...)` call site. Imports to add: `app_provider_config.dart`, `cli_presets_manage_dialog.dart`, `cli_preset_edit_dialog.dart`, `compose_model_preset_chip.dart` (already imported transitively?), keep alphabetical per file style.

- [ ] **Step 3: Delete legacy API + fix tests**

Delete `buildComposeModelPresetMenuSpecs` and `ComposeModelPresetChip` class; remove `custom` from `ComposeModelPresetChipAction`. Update `compose_chips_test.dart`: replace both `buildComposeModelPresetMenuSpecs` groups with equivalents against `buildComposeModelCascadeMenuSpecs` (bottom-actions ordering + omitted manage when label empty is now always-present — adjust assertions to: savePreset precedes manage; presets selected flag). Remove the flat-builder group from `compose_model_preset_chip_test.dart`, keep `simpleLaunchChipLabel` group.

- [ ] **Step 4: Verify**

Run: `cd client && flutter test test/widgets/compose/ && flutter analyze --no-fatal-infos --no-fatal-warnings`
Grep guard: `rg -n "buildComposeModelPresetMenuSpecs|ComposeModelPresetChip\(" client/lib client/test` → only allowed remaining references are none.
Manual smoke: in-chat simple session chip → DeepSeek → deepseek-chat → high; running session shows restart prompt; idle session applies silently.

Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
git add -A client/lib client/test
git commit -m "feat(chat): cascade model menu for simple sessions; drop flat preset menu"
```

---

### Task 8: full regression + docs touch

**Files:**
- Possibly touch: any file flagged by regression.

- [ ] **Step 1: Full test suites**

```bash
cd client && dart run tool/run_tests.dart
cd packages/shared_ui && flutter test
```

Expected: green. Fix any fallout (e.g., other widgets relying on removed chrome fields — grep `emptyPresetHintLabel`, `sameCliPresets` usages beyond card/section; `session_chat_view.dart:733/807/1024` referenced BoundComposeChrome args — update call sites accordingly).

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: clean.

- [ ] **Step 3: Commit (if fixes were needed)**

```bash
git add -A && git commit -m "fix(compose): cascade menu regression cleanup"
```

---

## Self-Review Notes

- Spec coverage: hierarchy (T4/T6/T7), effort 4th level incl. 默认 (T4), presets coexist + save/manage (T4/T6/T7), immediate apply no modal (T6/T7), custom model ID entry gated on pickerMode (T4/T5/T6/T7), landing CLI layer + chat skips it (T6 `groupByCli: true` vs T7 `false`), refresh-on-open (T5/T6/T7), empty catalog fallback (T4), l10n dual files (T6), shared_ui tests for expand/mutex/search/clamp/keyboard (T1–T3), no persistence changes (all flows reuse `landingDraftSelectingCustom` / `setSessionContinueCustom`).
- Type consistency: `Cascade*` names identical across T4 interfaces, T5 dialog params, T6 handlers, T7 handlers; chrome field names consistent between T7 steps 1–2.
- Known simplifications vs spec text: right-edge behavior uses the portal delegate's clamp (panel slides fully into view) rather than mirror-flip; per-rebuild coordinator means a mid-open catalog rebuild may collapse an open model submenu once.
