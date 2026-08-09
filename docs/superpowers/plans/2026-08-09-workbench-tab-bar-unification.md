# Workbench Tab Bar Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ChatTabStore/WorkbenchCubit dual source of truth with a single `TabStrip` owner per strip, eliminating the "closed session tab reappears at the end" bug class.

**Architecture:** A per-workspace `WorkspaceTabBar { center, floating }` where each strip is a `TabStrip` (ordered `List<WorkbenchTabId>` + `activeId` + `previewIds`). `WorkbenchCubit` is the sole writer of presence/order/active. Domain runtimes (sessions, files, shells) are referenced by id and never stored in the bar. A `WorkbenchChatBridge` feeds the bar on session open and translates bar-close into domain teardown via a `WorkbenchDomainPort`. `ChatState` drops `tabs`/`activeTabIndex`/`newChatActive`; `activeSessionId`/`selectedMemberId` become single-value mirrors written only by the bridge.

**Tech Stack:** Dart, flutter_bloc, Equatable. No new dependencies.

## Global Constraints

- Each strip has exactly one owner for presence, order, active, and preview: `TabStrip`. No reconciliation-by-append anywhere.
- All close operations are by `WorkbenchTabId`, never by index into a `ChatTabStore` bucket.
- The bar never holds payloads (no `ChatTab`, no `FloatingTab`) — only `WorkbenchTabId`.
- `ChatState.activeSessionId` / `selectedMemberId` are mirrors written only by `WorkbenchChatBridge`; no other code mutates them.
- During migration, `WorkbenchCubit` keeps its old method names as thin wrappers over the new core so callers compile; **all wrappers and the `WorkbenchWorkspaceState` facade are deleted in Task 6**.
- Every task ends green: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` passes for the touched area.
- Keep commits small and task-scoped.

---

## Task 1: `TabStrip` model + pure reducer + unit tests

**Files:**
- Create: `lib/cubits/workbench/tab_strip.dart`
- Test: `test/cubits/workbench/tab_strip_test.dart`

**Interfaces:**
- Produces: `TabStrip` (fields `order`, `activeId`, `previewIds`, getter `landingActive`, methods `contains`, `indexOf`) and `TabStripReducer` (methods `add`, `remove`, `reorder`, `activate`, `pin`, `enterLanding`). Later tasks rely on these exact names.

- [ ] **Step 1: Write the failing test**

```dart
// test/cubits/workbench/tab_strip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

const _s1 = WorkbenchTabId.session('s1');
const _s2 = WorkbenchTabId.session('s2');
const _s3 = WorkbenchTabId.session('s3');
const _f = WorkbenchTabId.file('/a.dart');

void main() {
  const r = TabStripReducer();
  const empty = TabStrip();

  group('add', () {
    test('appends at end and activates', () {
      final (s, replaced) = r.add(empty, _s1, preview: false);
      expect(s.order, [_s1]);
      expect(s.activeId, _s1);
      expect(replaced, isNull);
    });

    test('replaces an existing preview slot and returns it', () {
      final (s1, _) = r.add(empty, _f, preview: true);
      final (s2, replaced) = r.add(s1, _s1, preview: true);
      expect(replaced, _f);
      expect(s2.order, [_s1]);
      expect(s2.previewIds, {_s1});
    });

    test('pins an existing tab when preview is false', () {
      final (s1, _) = r.add(empty, _s1, preview: true);
      final (s2, _) = r.add(s1, _s1, preview: false);
      expect(s2.previewIds, isEmpty);
      expect(s2.activeId, _s1);
    });
  });

  group('remove', () {
    test('never resurrects the removed id', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final s3 = r.remove(s2, _s1);
      expect(s3, isNotNull);
      expect(s3!.order, [_s2]);
      expect(s3.order.contains(_s1), isFalse);
    });

    test('activates previous neighbor, else first, else null', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final (s3, _) = r.add(s2, _s3, preview: false);
      // remove active middle -> previous neighbor
      expect(r.remove(s3, _s2)!.activeId, _s1);
      // remove active first -> new first
      expect(r.remove(s3, _s1)!.activeId, _s2);
      // remove last remaining -> null (landing)
      final (only, _) = r.add(empty, _s1, preview: false);
      expect(r.remove(only, _s1)!.activeId, isNull);
      // absent id -> null (no-op)
      expect(r.remove(s3, _f), isNull);
    });

    test('drops the removed id from previewIds', () {
      final (s1, _) = r.add(empty, _f, preview: true);
      final s2 = r.remove(s1, _f)!;
      expect(s2.previewIds, isEmpty);
    });
  });

  group('reorder / activate / pin / landing', () {
    test('reorder preserves active and preview', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final s3 = r.reorder(s2, 0, 1);
      expect(s3.order, [_s2, _s1]);
      expect(s3.activeId, _s2);
    });

    test('activate selects an existing tab', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      expect(r.activate(s2, _s1).activeId, _s1);
      expect(r.activate(s2, _f).activeId, _s2); // absent -> unchanged
    });

    test('pin removes from preview set', () {
      final (s1, _) = r.add(empty, _s1, preview: true);
      final s2 = r.pin(s1, _s1);
      expect(s2.previewIds, isEmpty);
    });

    test('enterLanding clears active but keeps tabs', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final s2 = r.enterLanding(s1);
      expect(s2.activeId, isNull);
      expect(s2.order, [_s1]);
      expect(s2.landingActive, isTrue);
    });
  });

  group('invariants', () {
    test('order has no duplicates after repeated adds', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s1, preview: false);
      expect(s2.order.where((t) => t == _s1).length, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/workbench/tab_strip_test.dart`
Expected: compile error — `tab_strip.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/cubits/workbench/tab_strip.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'workbench_tab.dart';

/// One strip's entire state: ordered tabs, active tab, preview set.
///
/// The single owner of presence / order / active for one tab surface. Domain
/// runtimes (sessions, files, shells) are referenced by [WorkbenchTabId]; the
/// strip never holds payloads.
@immutable
class TabStrip extends Equatable {
  const TabStrip({
    this.order = const [],
    this.activeId,
    this.previewIds = const {},
  });

  final List<WorkbenchTabId> order;
  final WorkbenchTabId? activeId;

  /// Tabs that are still preview (replaceable) until pinned.
  final Set<WorkbenchTabId> previewIds;

  /// Landing / welcome shows when nothing is selected. Tabs may remain in the
  /// bar (open sessions) while the landing is displayed.
  bool get landingActive => activeId == null;

  bool contains(WorkbenchTabId id) => order.contains(id);

  int indexOf(WorkbenchTabId id) => order.indexOf(id);

  @override
  List<Object?> get props => [order, activeId, previewIds];
}

/// Pure reducer: returns the next [TabStrip] for each mutation. Never mutates
/// in place. Removing an id never resurrects it — re-add requires an explicit
/// [add].
class TabStripReducer {
  const TabStripReducer();

  /// Adds [tab]. When already present and [preview] is false, it is pinned and
  /// activated. When [preview] is true and another preview exists, that preview
  /// is replaced in place and returned. Otherwise the tab is appended at the
  /// end (new tabs surface last).
  (TabStrip, WorkbenchTabId?) add(
    TabStrip strip,
    WorkbenchTabId tab, {
    required bool preview,
    bool activate = true,
  }) {
    final order = List<WorkbenchTabId>.of(strip.order);
    final previews = Set<WorkbenchTabId>.of(strip.previewIds);

    final existing = order.indexOf(tab);
    if (existing >= 0) {
      if (!preview) {
        previews.remove(tab);
        return (
          TabStrip(
            order: order,
            activeId: activate ? tab : strip.activeId,
            previewIds: previews,
          ),
          null,
        );
      }
      if (previews.contains(tab)) {
        return (
          TabStrip(
            order: order,
            activeId: activate ? tab : strip.activeId,
            previewIds: previews,
          ),
          null,
        );
      }
      order.removeAt(existing);
    }

    WorkbenchTabId? replaced;
    if (preview) {
      for (final candidate in order) {
        if (previews.contains(candidate)) {
          replaced = candidate;
          break;
        }
      }
    }

    if (replaced != null) {
      final i = order.indexOf(replaced);
      order[i] = tab;
      previews.remove(replaced);
      previews.add(tab);
    } else {
      order.add(tab);
      if (preview) previews.add(tab);
    }

    return (
      TabStrip(
        order: order,
        activeId: activate ? tab : strip.activeId,
        previewIds: previews,
      ),
      replaced,
    );
  }

  /// Removes [id]; recomputes active (previous neighbor → first → null).
  /// Returns null when [id] is absent.
  TabStrip? remove(TabStrip strip, WorkbenchTabId id) {
    final order = List<WorkbenchTabId>.of(strip.order);
    final index = order.indexOf(id);
    if (index < 0) return null;

    order.removeAt(index);
    final previews = Set<WorkbenchTabId>.of(strip.previewIds)..remove(id);

    WorkbenchTabId? active = strip.activeId;
    if (active == id) {
      if (order.isEmpty) {
        active = null;
      } else if (index > 0) {
        active = order[index - 1];
      } else {
        active = order.first;
      }
    }
    return TabStrip(order: order, activeId: active, previewIds: previews);
  }

  TabStrip reorder(TabStrip strip, int oldIndex, int newIndex) {
    if (strip.order.isEmpty) return strip;
    if (oldIndex < 0 ||
        oldIndex >= strip.order.length ||
        newIndex < 0 ||
        newIndex >= strip.order.length ||
        oldIndex == newIndex) {
      return strip;
    }
    final order = List<WorkbenchTabId>.of(strip.order);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    return TabStrip(
      order: order,
      activeId: strip.activeId,
      previewIds: strip.previewIds,
    );
  }

  TabStrip activate(TabStrip strip, WorkbenchTabId id) {
    if (!strip.order.contains(id)) return strip;
    return TabStrip(
      order: strip.order,
      activeId: id,
      previewIds: strip.previewIds,
    );
  }

  TabStrip pin(TabStrip strip, WorkbenchTabId id) {
    if (!strip.previewIds.contains(id)) return strip;
    final previews = Set<WorkbenchTabId>.of(strip.previewIds)..remove(id);
    return TabStrip(
      order: strip.order,
      activeId: strip.activeId,
      previewIds: previews,
    );
  }

  TabStrip enterLanding(TabStrip strip) => TabStrip(
    order: strip.order,
    activeId: null,
    previewIds: strip.previewIds,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/workbench/tab_strip_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/cubits/workbench/tab_strip.dart test/cubits/workbench/tab_strip_test.dart
git commit -m "feat(workbench): TabStrip single-owner strip model with pure reducer"
```

---

## Task 2: `WorkspaceTabBar` + `WorkbenchCubit` internals over `TabStrip` (facade keeps old surface)

**Files:**
- Create: `lib/cubits/workbench/workbench_tab_bar.dart`
- Modify: `lib/cubits/workbench/workbench_cubit.dart`
- Test: `test/cubits/workbench_cubit_test.dart`

**Interfaces:**
- Consumes: `TabStrip`, `TabStripReducer` (Task 1), `WorkbenchTabId`, `isCenterStripWorkbenchTab` (existing in `workbench_tab.dart`).
- Produces: `WorkspaceTabBar` (`center`, `floating`, `copyWith`, Equatable). `WorkbenchState.byWorkspace: Map<String, WorkspaceTabBar>`, `WorkbenchState.bar(id)` and **compatibility** `WorkbenchState.bucket(id) → WorkbenchWorkspaceState` exposing the OLD getters (`tabOrder`, `activeTabId`, `previewTabIds`, `welcomeActive`) derived from `bar.center` so existing readers compile unchanged. `WorkbenchCubit` keeps old method names as wrappers (`ensureTab`, `removeTab`, `select`, `reorderTabs`, `pinTab`, `closeOthers`, `closeRight`, `closeAll`, `clearActive`, `syncSessions`, `clearWorkspace`) plus NEW core methods (`openSession`, `openFile`, `openDiff`, `close`, `activate`, `pin`, `enterLanding`, `reorder`, `centerOrder`, `centerActiveId`).

- [ ] **Step 1: Write the failing test**

Rewrite `test/cubits/workbench_cubit_test.dart` to exercise the new core through the public surface:

```dart
// test/cubits/workbench_cubit_test.dart (full replacement)
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

const _ws = 'ws';
const _s1 = WorkbenchTabId.session('s1');
const _s2 = WorkbenchTabId.session('s2');
const _f = WorkbenchTabId.file('/a.dart');

void main() {
  late WorkbenchCubit cubit;
  setUp(() => cubit = WorkbenchCubit());

  group('openSession', () {
    test('adds and activates a new session tab', () {
      cubit.openSession(_ws, 's1');
      final bar = cubit.state.bar(_ws);
      expect(bar.center.order, [_s1]);
      expect(bar.center.activeId, _s1);
    });

    test('does not duplicate when opened twice', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's1');
      expect(cubit.state.bar(_ws).center.order.where((t) => t == _s1).length, 1);
    });
  });

  group('close', () {
    test('removes by id and never resurrects it', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      final removed = cubit.close(_ws, _s1);
      expect(removed, _s1);
      final order = cubit.state.bar(_ws).center.order;
      expect(order, [_s2]);
      expect(order.contains(_s1), isFalse);
    });

    test('re-activating a closed id re-adds at the end (explicit open only)', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.close(_ws, _s1);
      cubit.openSession(_ws, 's1'); // explicit re-open
      expect(cubit.state.bar(_ws).center.order, [_s2, _s1]);
    });
  });

  group('workspace isolation', () {
    test('buckets are independent per workspace', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession('other', 's2');
      expect(cubit.state.bar(_ws).center.order, [_s1]);
      expect(cubit.state.bar('other').center.order, [_s2]);
    });
  });

  group('legacy facade', () {
    test('bucket exposes old getters for existing readers', () {
      cubit.openSession(_ws, 's1');
      final bucket = cubit.state.bucket(_ws);
      expect(bucket.tabOrder, [_s1]);
      expect(bucket.activeTabId, _s1);
      expect(bucket.previewTabIds, isEmpty);
      expect(bucket.welcomeActive, isFalse);
    });

    test('legacy syncSessions still aligns sessions into the bar', () {
      cubit.openSession(_ws, 's1');
      cubit.syncSessions(_ws, ['s1', 's2']);
      expect(cubit.state.bar(_ws).center.order, contains(_s2));
    });
  });

  group('closeOthers / closeRight / closeAll', () {
    test('closeOthers returns removed list', () {
      cubit.openSession(_ws, 's1');
      cubit.openSession(_ws, 's2');
      cubit.openSession(_ws, 's3');
      final removed = cubit.closeOthers(_ws, _s2);
      expect(removed, [_s1, _s3]);
      expect(cubit.state.bar(_ws).center.order, [_s2]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/workbench_cubit_test.dart`
Expected: FAIL — `WorkbenchCubit()` constructor or new methods missing.

- [ ] **Step 3: Write `workbench_tab_bar.dart`**

```dart
// lib/cubits/workbench/workbench_tab_bar.dart
import 'package:equatable/equatable.dart';

import 'tab_strip.dart';

/// Per-workspace tab state: the center strip (session/file/diff) and the
/// floating strip (shell/run). Both are [TabStrip]s — one owner each.
class WorkspaceTabBar extends Equatable {
  const WorkspaceTabBar({
    this.center = const TabStrip(),
    this.floating = const TabStrip(),
  });

  final TabStrip center;
  final TabStrip floating;

  WorkspaceTabBar copyWith({TabStrip? center, TabStrip? floating}) =>
      WorkspaceTabBar(
        center: center ?? this.center,
        floating: floating ?? this.floating,
      );

  @override
  List<Object?> get props => [center, floating];
}
```

- [ ] **Step 4: Rewrite `workbench_cubit.dart`**

Replace the whole file body (keep `WorkbenchWorkspaceState` as a derived facade):

```dart
// lib/cubits/workbench/workbench_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'tab_strip.dart';
import 'workbench_tab.dart';
import 'workbench_tab_bar.dart';

/// Back-compat facade over [WorkspaceTabBar.center] so existing readers of the
/// old `bucket(ws).tabOrder` surface keep compiling during migration. Deleted
/// with the wrapper methods in Task 5.
class WorkbenchWorkspaceState extends Equatable {
  const WorkbenchWorkspaceState(this.bar);

  final WorkspaceTabBar bar;

  List<WorkbenchTabId> get tabOrder => bar.center.order;
  WorkbenchTabId? get activeTabId => bar.center.activeId;
  Set<WorkbenchTabId> get previewTabIds => bar.center.previewIds;
  bool get welcomeActive => bar.center.landingActive;
  bool isPreview(WorkbenchTabId tab) => bar.center.previewIds.contains(tab);

  @override
  List<Object?> get props => [bar];
}

class WorkbenchState extends Equatable {
  const WorkbenchState({this.byWorkspace = const {}});

  final Map<String, WorkspaceTabBar> byWorkspace;

  WorkspaceTabBar bar(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkspaceTabBar();

  /// Back-compat facade (Task 5 removes callers of this).
  WorkbenchWorkspaceState bucket(String workspaceId) =>
      WorkbenchWorkspaceState(bar(workspaceId));

  WorkbenchState withBar(String workspaceId, WorkspaceTabBar bar) {
    return WorkbenchState(byWorkspace: {...byWorkspace, workspaceId: bar});
  }

  @override
  List<Object?> get props => [byWorkspace];
}

/// Owns the workbench tab bar: per-workspace center + floating strips.
///
/// The single writer of tab presence / order / active. Domain runtimes are
/// referenced by id and reached via [WorkbenchDomainPort] on close.
class WorkbenchCubit extends Cubit<WorkbenchState> {
  WorkbenchCubit({WorkbenchDomainPort? port}) : _port = port ?? const _NoopPort(),
       super(const WorkbenchState());

  final WorkbenchDomainPort _port;
  static const TabStripReducer _r = TabStripReducer();

  // ---- NEW core API ----

  WorkbenchTabId? openSession(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(workspaceId, WorkbenchTabId.session(sessionId), preview: preview, activate: activate);

  WorkbenchTabId? openFile(
    String workspaceId,
    String path, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(workspaceId, WorkbenchTabId.file(path), preview: preview, activate: activate);

  WorkbenchTabId? openDiff(
    String workspaceId,
    WorkbenchTabId tab, {
    bool preview = false,
    bool activate = true,
  }) => _openCenter(workspaceId, tab, preview: preview, activate: activate);

  WorkbenchTabId? _openCenter(
    String workspaceId,
    WorkbenchTabId tab, {
    required bool preview,
    bool activate = true,
  }) {
    if (!isCenterStripWorkbenchTab(tab.kind)) return null;
    final bar = state.bar(workspaceId);
    final (next, replaced) = _r.add(
      bar.center,
      tab,
      preview: preview,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
    return replaced;
  }

  /// Removes [id] from the owning strip and returns it, or null if absent.
  /// The port's [WorkbenchDomainPort.onTabRemoved] is called for teardown.
  WorkbenchTabId? close(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final isCenter = isCenterStripWorkbenchTab(id.kind);
    final strip = isCenter ? bar.center : bar.floating;
    final next = _r.remove(strip, id);
    if (next == null) return null;
    emit(state.withBar(
      workspaceId,
      isCenter ? bar.copyWith(center: next) : bar.copyWith(floating: next),
    ));
    unawaited(_port.onTabRemoved(workspaceId, id));
    return id;
  }

  void openShell(String workspaceId, String entryId, {bool activate = true}) {
    final bar = state.bar(workspaceId);
    final (next, _) = _r.add(
      bar.floating,
      WorkbenchTabId.shell(entryId),
      preview: false,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  }

  void openRun(String workspaceId, String runSessionId, {bool activate = true}) {
    final bar = state.bar(workspaceId);
    final (next, _) = _r.add(
      bar.floating,
      WorkbenchTabId.run(runSessionId),
      preview: false,
      activate: activate,
    );
    emit(state.withBar(workspaceId, bar.copyWith(floating: next)));
  }

  void activate(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final strip = isCenterStripWorkbenchTab(id.kind) ? bar.center : bar.floating;
    final next = _r.activate(strip, id);
    emit(state.withBar(
      workspaceId,
      isCenterStripWorkbenchTab(id.kind)
          ? bar.copyWith(center: next)
          : bar.copyWith(floating: next),
    ));
  }

  void pin(String workspaceId, WorkbenchTabId id) {
    final bar = state.bar(workspaceId);
    final next = _r.pin(bar.center, id);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  /// Shows the center landing (new-chat / welcome) without closing tabs.
  void enterLanding(String workspaceId) {
    final bar = state.bar(workspaceId);
    final next = _r.enterLanding(bar.center);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  void reorder(String workspaceId, int oldIndex, int newIndex) {
    final bar = state.bar(workspaceId);
    final next = _r.reorder(bar.center, oldIndex, newIndex);
    emit(state.withBar(workspaceId, bar.copyWith(center: next)));
  }

  List<WorkbenchTabId> centerOrder(String workspaceId) =>
      state.bar(workspaceId).center.order;

  WorkbenchTabId? centerActiveId(String workspaceId) =>
      state.bar(workspaceId).center.activeId;

  // ---- Legacy wrappers (deleted in Task 5; keep callers compiling) ----

  WorkbenchTabId? ensureTab(String workspaceId, WorkbenchTabId tab, {bool preview = false}) =>
      _openCenter(workspaceId, tab, preview: preview, activate: true);

  void removeTab(String workspaceId, WorkbenchTabId tab) {
    close(workspaceId, tab);
  }

  void select(String workspaceId, WorkbenchTabId tab) =>
      activate(workspaceId, tab);

  void reorderTabs(String workspaceId, int oldIndex, int newIndex) =>
      reorder(workspaceId, oldIndex, newIndex);

  void pinTab(String workspaceId, WorkbenchTabId tab) =>
      pin(workspaceId, tab);

  void clearActive(String workspaceId) => enterLanding(workspaceId);

  void enterWelcome(String workspaceId) => enterLanding(workspaceId);

  List<WorkbenchTabId> closeOthers(String workspaceId, WorkbenchTabId keep) {
    final bar = state.bar(workspaceId);
    final center = bar.center;
    if (!center.order.contains(keep)) return const [];
    final removed = center.order.where((t) => t != keep).toList(growable: false);
    emit(state.withBar(
      workspaceId,
      bar.copyWith(
        center: TabStrip(order: [keep], activeId: keep, previewIds: center.previewIds.contains(keep) ? {keep} : const {}),
      ),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeRight(String workspaceId, WorkbenchTabId anchor) {
    final center = state.bar(workspaceId).center;
    final index = center.order.indexOf(anchor);
    if (index < 0 || index >= center.order.length - 1) return const [];
    final kept = center.order.sublist(0, index + 1);
    final removed = center.order.sublist(index + 1);
    final active = center.activeId;
    final nextActive = active != null && removed.contains(active) ? anchor : active;
    emit(state.withBar(
      workspaceId,
      state.bar(workspaceId).copyWith(
        center: TabStrip(
          order: kept,
          activeId: nextActive,
          previewIds: center.previewIds.where(kept.contains).toSet(),
        ),
      ),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  List<WorkbenchTabId> closeAll(String workspaceId) {
    final center = state.bar(workspaceId).center;
    final removed = List<WorkbenchTabId>.from(center.order);
    if (removed.isEmpty) return const [];
    emit(state.withBar(
      workspaceId,
      state.bar(workspaceId).copyWith(center: const TabStrip()),
    ));
    for (final tab in removed) {
      unawaited(_port.onTabRemoved(workspaceId, tab));
    }
    return removed;
  }

  /// Legacy reconcile-by-append. Kept ONLY until Task 3 deletes it together
  /// with [WorkbenchSessionSync]; the bridge then feeds the bar directly.
  void syncSessions(
    String workspaceId,
    List<String> sessionIds, {
    String? preferredActiveSessionId,
    bool newChatActive = false,
  }) {
    final bar = state.bar(workspaceId);
    final sessionSet = sessionIds.toSet();
    final order = <WorkbenchTabId>[];
    for (final tab in bar.center.order) {
      if (!isCenterStripWorkbenchTab(tab.kind)) continue;
      if (tab.kind == WorkbenchTabKind.session) {
        if (sessionSet.contains(tab.id)) order.add(tab);
      } else {
        order.add(tab);
      }
    }
    final existingSessions = {
      for (final t in order)
        if (t.kind == WorkbenchTabKind.session) t.id,
    };
    for (final id in sessionIds) {
      if (!existingSessions.contains(id)) {
        order.add(WorkbenchTabId.session(id));
      }
    }
    var active = bar.center.activeId;
    if (newChatActive) {
      active = null;
    } else if (active != null && !order.contains(active)) {
      active = null;
    }
    emit(state.withBar(
      workspaceId,
      bar.copyWith(
        center: TabStrip(order: order, activeId: active, previewIds: bar.center.previewIds.where(order.contains).toSet()),
      ),
    ));
  }

  void clearWorkspace(String workspaceId) {
    if (!state.byWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, WorkspaceTabBar>.from(state.byWorkspace)
      ..remove(workspaceId);
    emit(WorkbenchState(byWorkspace: next));
  }

  @override
  List<WorkbenchTabId> tabOrder(String workspaceId) => centerOrder(workspaceId);
}
```

The plan assumes these imports in the cubit file: `dart:async` for `unawaited`, `workbench_tab_bar.dart`, `tab_strip.dart`. Add `import 'dart:async';`.

- [ ] **Step 5: Create `WorkbenchDomainPort` in a new file**

```dart
// lib/cubits/workbench/workbench_domain_port.dart
import 'workbench_tab.dart';

/// Teardown port: called by [WorkbenchCubit] when a tab is removed from the
/// bar so the owning domain can dispose its runtime. Implemented by the
/// bridge / coordinator wired in `app_shell.dart`.
abstract class WorkbenchDomainPort {
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id);
}

class _NoopPort implements WorkbenchDomainPort {
  const _NoopPort();
  @override
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id) async {}
}
```

Move `_NoopPort` to the same file (top-level, private). Import it in the cubit.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/workbench_cubit_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify the rest of the tree still compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors introduced by the cubit rewrite (facade keeps old getters/methods).

- [ ] **Step 8: Commit**

```bash
git add lib/cubits/workbench/ lib/cubits/workbench_cubit.dart test/cubits/workbench_cubit_test.dart
git commit -m "feat(workbench): single-owner TabStrip bar behind legacy facade"
```

---

## Task 3: Bridge feeds the bar on session open; delete `syncSessions` + `WorkbenchSessionSync`

**Files:**
- Create: `lib/services/workbench/workbench_chat_bridge.dart`
- Modify: `lib/cubits/chat/session_launch_bundle.dart` (inject bridge or open callback into `SessionTabSurfaceCoordinator`)
- Modify: `lib/services/launch/session_tab_surface_coordinator.dart`
- Modify: `lib/widgets/workbench/workbench_session_sync.dart` (delete) + its usage in `lib/pages/chat/chat_page_shell.dart`
- Modify: `lib/cubits/workbench/workbench_cubit.dart` (delete `syncSessions`)
- Modify: `lib/app/app_shell.dart` (construct bridge)

**Interfaces:**
- Consumes: `WorkbenchCubit.openSession`, `ChatCubit` (session runtime). 
- Produces: `WorkbenchChatBridge.onSessionTabOpened(workspaceId, sessionId, {preview, activate})`. Later tasks use `WorkbenchChatBridge` for close/foreground mirror.

- [ ] **Step 1: Write the bridge**

```dart
// lib/services/workbench/workbench_chat_bridge.dart
import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';

/// Single domain ↔ bar handshake. Feeds the bar on session open; later tasks
/// add close teardown and the foreground-session mirror here.
class WorkbenchChatBridge {
  WorkbenchChatBridge({required WorkbenchCubit workbench, required ChatCubit chat})
      : _workbench = workbench,
        _chat = chat;

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;

  /// Session domain staged a new/reused session tab; surface it in the bar.
  void onSessionTabOpened(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) {
    _workbench.openSession(
      workspaceId,
      sessionId,
      preview: preview,
      activate: activate,
    );
  }
}
```

- [ ] **Step 2: Wire the bridge into `app_shell.dart`**

In `lib/app/app_shell.dart`, after `workbenchCubit` and `chatCubit` exist (near line 1572 / 1159), construct the bridge and pass it (or a `onSessionTabOpened` callback) into `SessionLaunchBundleDeps` / the surface coordinator. Follow the existing constructor-injection pattern used for `SessionLaunchBundle.create` (`session_launch_bundle.dart:73-99`). Add a `WorkbenchChatBridge? chatBridge` parameter to `SessionLaunchBundleDeps` and thread it into `SessionTabSurfaceCoordinator` as a `void Function(String workspaceId, String sessionId, {bool preview, bool activate})? onSessionTabOpened` callback.

- [ ] **Step 3: Route `surfaceNewTab` through the bridge**

In `lib/services/launch/session_tab_surface_coordinator.dart`, `surfaceNewTab` already calls `_tabStore.append(tab)` + `_host.applyState(...)` + `_host.refreshActiveWorkspaceTabs()`. Add a call to the injected `onSessionTabOpened` callback **immediately after** `_host.applyState(...)`:

```dart
onSessionTabOpened?.call(
  session.workspaceId,
  tab.info.id,
  preview: !request.connectImmediately,
  activate: true,
);
```

`surfaceExistingTab` needs no bar change — the tab is already in the bar (it must exist to be reused). Do NOT add a call there.

- [ ] **Step 4: Delete `WorkbenchSessionSync` and its usage**

- Delete `lib/widgets/workbench/workbench_session_sync.dart`.
- In `lib/pages/chat/chat_page_shell.dart`, remove the `WorkbenchSessionSync(...)` wrapper (lines ~203-209) — keep its `child` (the inner `BlocBuilder<WorkbenchCubit>`). Remove the import. The strip already reads `workbenchState.bucket(workspaceId).tabOrder` which is now the single-owner bar.

- [ ] **Step 5: Delete `syncSessions` from `WorkbenchCubit`**

Remove the `syncSessions` method (and any `WorkbenchSessionSync` reference). `flutter analyze` will flag any remaining caller; fix by removing the call (none should remain after Step 4).

- [ ] **Step 6: Update Task 2's legacy-facade test**

In `test/cubits/workbench_cubit_test.dart`, delete the `'legacy syncSessions still aligns sessions into the bar'` test (method no longer exists). Keep the rest.

- [ ] **Step 7: Verify green**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/cubits/workbench_cubit_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/workbench/workbench_chat_bridge.dart lib/app/app_shell.dart lib/services/launch/session_tab_surface_coordinator.dart lib/cubits/chat/session_launch_bundle.dart lib/widgets/workbench/workbench_session_sync.dart lib/pages/chat/chat_page_shell.dart lib/cubits/workbench/workbench_cubit.dart test/cubits/workbench_cubit_test.dart
git commit -m "feat(workbench): feed bar on session open via bridge; drop syncSessions reconcile"
```

---

## Task 4: Close path via bar + `ChatTabStore` → runtime registry + `ChatCubit` tab-ops rework

**Files:**
- Modify: `lib/services/workbench/workbench_shell_actions.dart`
- Modify: `lib/cubits/chat/chat_tab_store.dart`
- Modify: `lib/cubits/chat_cubit.dart`
- Modify: `lib/cubits/chat/chat_connect_state_mixin.dart`
- Modify: `lib/app/app_shell.dart` (implement port; wire teardown)
- Test: `test/cubits/chat_cubit_test.dart` (update close/select tests)

**Interfaces:**
- Consumes: `WorkbenchCubit.close`, `WorkbenchDomainPort.onTabRemoved`; produces `ChatCubit.teardownSession(sessionId)` (renamed from `_tearDownTab`'s body), `ChatCubit.registerSessionRuntime(ChatTab)`, `ChatTabStore.registerSession(ChatTab)`, `ChatTabStore.disposeSession(sessionId)`, `ChatTabStore.sessionsForWorkspace(workspaceId)`.

- [ ] **Step 1: Rewrite `WorkbenchShellActions` close path**

In `lib/services/workbench/workbench_shell_actions.dart`:
- `selectResolved`: replace `workbench.select(workspaceId, tab)` with `workbench.activate(workspaceId, tab)`; remove the `chat.selectTab(index)` block (the bar's active is the single source; the bridge mirrors it). Keep `chat.exitNewChat()` removal (replaced by `workbench` landing in later task — keep for now, it is harmless).
- `closeAt`: replace the whole `switch` body with a single id-based close:

```dart
static Future<void> closeAt({
  required BuildContext context,
  required String workspaceId,
  required String tabScopeId,
  required WorkbenchTabId tab,
}) async {
  final workbench = context.read<WorkbenchCubit>();
  switch (tab.kind) {
    case WorkbenchTabKind.file:
      final editor = context.read<EditorCubit>();
      final dirty = editor.state.bucket(workspaceId).isDirty(tab.id);
      if (dirty) {
        final discard = await _confirmDiscard(context);
        if (discard != true || !context.mounted) return;
      }
      editor.closeFile(workspaceId, tab.id, force: true);
    case WorkbenchTabKind.diff:
      context.read<EditorCubit>().closeDiff(workspaceId, tab.id);
    case WorkbenchTabKind.shell:
      disposeWorkbenchShellDomain(
        runService: context.read<WorkspaceTerminalRunService>(),
        group: context.read<WorkspaceTerminalRegistry>().groupFor(tabScopeId),
        entryId: tab.id,
      );
    case WorkbenchTabKind.run:
      final runCubit = context.read<RunCubit>();
      final session = _runSessionById(runCubit.state.sessions, tab.id);
      if (session != null) {
        final dismissed = await dismissRunSessionWithConfirm(
          context: context,
          cubit: runCubit,
          session: session,
        );
        if (!shouldRemoveRunWorkbenchTab(
              sessionFound: true,
              dismissSucceeded: dismissed,
            ) ||
            !context.mounted) {
          return;
        }
      }
    case WorkbenchTabKind.session:
      break; // teardown handled by the port (chat.teardownSession)
  }
  workbench.close(workspaceId, tab);
}
```

Note: file/diff/shell/run domains are torn down inline (as today); **session** teardown moves to the port (`onTabRemoved` → `chat.teardownSession`). The port teardown runs after the bar removes the entry.

- [ ] **Step 2: Reshape `ChatTabStore` into a runtime registry**

In `lib/cubits/chat/chat_tab_store.dart`, replace the per-workspace bucket model with a single map:

```dart
/// Session runtime registry. Owns the *runtime* behind each session tab, not
/// bar presence/order (that is `WorkbenchCubit`). Keyed by session id.
class ChatTabStore {
  final Map<String, ChatTab> _bySessionId = {};
  String _activeWorkspaceId = '';

  String get activeWorkspaceId => _activeWorkspaceId;
  void setActiveWorkspaceId(String id) => _activeWorkspaceId = id;

  ChatTab? openTabBySessionId(String sessionId) => _bySessionId[sessionId.trim()];

  Iterable<ChatTab> get openTabs => _bySessionId.values;

  List<ChatTab> tabsForWorkspace(String workspaceId) =>
      _bySessionId.values.where((t) => t.workspaceId == workspaceId).toList();

  /// Tabs for the foreground workspace (domain convenience).
  List<ChatTab> get activeTabs => _bySessionId.values.toList();

  bool get activeTabsIsEmpty => _bySessionId.isEmpty;

  /// Register a staged session runtime (bar presence is handled by the bridge).
  void registerSession(ChatTab tab) {
    tab.workspaceId = _activeWorkspaceId;
    _bySessionId[tab.info.id] = tab;
  }

  /// Remove and return the runtime for [sessionId], if any.
  ChatTab? removeSession(String sessionId) =>
      _bySessionId.remove(sessionId.trim());

  void clear() => _bySessionId.clear();

  ChatTab? activeTab(int _ignored) => _bySessionId.isEmpty ? null : _bySessionId.values.first;

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }
}
```

Keep the other stateless helpers (`defaultMemberId`, `localSessionInfo`, `workingDirectoryAndAddDirsForTab`, `sessionForTab`). Delete: `_byWorkspace`, `_savedActiveIndex`, `_newChatActiveByWorkspace`, `setActiveWorkspace`, `activeTabs` (bucket), `activeTabCount`, `activeTabsIsEmpty` (bucket), `activeTabBySessionId`, `openTabBySessionId` (kept), `activeIndexOfSession`, `append`, `appendLocalTab`, `removeAt`, `removeWorkspace`, `isNewChatActive`, `setNewChatActive`, `savedActiveIndexFor`, `sessionBackedCountForWorkspace`. If any are still referenced, keep them temporarily as thin helpers over the map; `flutter analyze` will find the remainder. `appendLocalTab` becomes:

```dart
ChatTab appendLocalTab(TeamProfile team, {required String cliTeamName}) {
  final tab = ChatTab(
    info: localSessionInfo(team),
    cliTeamName: cliTeamName,
    selectedMemberId: defaultMemberId(team),
    workspaceId: _activeWorkspaceId,
  );
  registerSession(tab);
  return tab;
}
```

- [ ] **Step 3: Rework `ChatCubit` tab operations**

In `lib/cubits/chat_cubit.dart`:

- Add `ChatTab? get activeTab` resolving the foreground session from the mirror (the bridge writes `state.activeSessionId`):

```dart
ChatTab? get activeTab {
  final id = state.activeSessionId;
  if (id == null || id.isEmpty) return null;
  return _tabStore.openTabBySessionId(id);
}
```
- Replace `closeTab(int index)` with a session-id teardown used by the port:

```dart
/// Tears down a session runtime after the bar removed its tab.
Future<void> teardownSession(String sessionId) async {
  final tab = _tabStore.removeSession(sessionId);
  if (tab == null) return;
  await _tearDownTab(tab);
  _pushPresenceTarget();
}
```

- Keep `_tearDownTab(ChatTab tab)` as-is (pod dispose, session dispose, bus dispose).
- `closeSessionTab(String sessionId)` → becomes a domain-driven close: it calls the bridge/port so the bar removes the entry (which then calls back `teardownSession`). If the port is not yet wired, fall back to `teardownSession` directly. Implement as:

```dart
@override
void closeSessionTab(String sessionId) {
  final tab = _tabStore.openTabBySessionId(sessionId);
  if (tab == null) return;
  // Domain-driven close: remove from the bar; the port calls teardownSession.
  final port = _workbenchPort;
  if (port != null) {
    port.onSessionTabClosed(tab.workspaceId, sessionId);
  } else {
    unawaited(teardownSession(sessionId));
  }
}
```

Where `_workbenchPort` is a new narrow interface (see Step 4). 
- Delete `selectTab`, `setActiveWorkspace`'s bucket switching, `activateWorkspaceTab`'s bucket switching, `_publishActiveWorkspaceTabs`, `_pushPresenceTarget` bucket logic — replace with `setActiveWorkspaceId` on the store + a bridge `syncForeground()` call. `enterNewChat`/`exitNewChat` become `workbench.enterLanding(workspaceId)` (route through `_workbenchPort.enterLanding(workspaceId)`).
- `closeTabsForWorkspace(workspaceId)`: replace bucket removal with: for each session runtime in `tabsForWorkspace(workspaceId)`, call `teardownSession(id)` and `_workbenchPort.closeAll(workspaceId)` (or `workbench.close` per id). Keep it idempotent.

- [ ] **Step 4: Add the `_workbenchPort` interface + wire the port in `app_shell.dart`**

New interface (in `lib/cubits/chat/session_launch_host.dart` or a small file):

```dart
/// Narrow surface the session domain uses to drive the bar (implemented by
/// WorkbenchChatBridge in production).
abstract class ChatWorkbenchPort {
  void onSessionTabClosed(String workspaceId, String sessionId);
  void enterLanding(String workspaceId);
  void closeAll(String workspaceId);
}
```

`WorkbenchChatBridge` implements `ChatWorkbenchPort` **and** `WorkbenchDomainPort`:
- `onSessionTabClosed(ws, id)` → `_workbench.close(ws, WorkbenchTabId.session(id))`.
- `onTabRemoved(ws, id)` → if `id.kind == session`, `_chat.teardownSession(id.id)`.
- `enterLanding(ws)` → `_workbench.enterLanding(ws)`.
- `closeAll(ws)` → `_workbench.closeAll(ws)` (each removal calls `onTabRemoved` → teardown).

In `app_shell.dart`, construct `WorkbenchCubit(port: bridge)` and pass `bridge` to `ChatCubit` as `_workbenchPort`. `ChatCubit` already has a `SessionLaunchHost` seam; add a constructor param `ChatWorkbenchPort? workbenchPort` defaulting to null.

- [ ] **Step 5: Update tests**

In `test/cubits/chat_cubit_test.dart`, update tests that call `chat.closeTab(index)`, `chat.selectTab(index)`, `chat.state.tabs`, `chat.state.activeTabIndex`, or `chat.state.newChatActive`:
- `closeTab` → drive via a fake `WorkbenchCubit` + bridge, or call `teardownSession(id)` directly for teardown assertions.
- `selectTab` / active index → assert bar state via `WorkbenchCubit` instead.
- `state.tabs` → read `workbench.state.bar(ws).center.order` + `chat.tabStore.tabsForWorkspace(ws)`.
Run and fix until green.

- [ ] **Step 6: Verify green**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/cubits/chat_cubit_test.dart test/cubits/workbench_cubit_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/services/workbench/workbench_shell_actions.dart lib/cubits/chat/chat_tab_store.dart lib/cubits/chat_cubit.dart lib/cubits/chat/chat_connect_state_mixin.dart lib/app/app_shell.dart lib/cubits/chat/session_launch_host.dart test/cubits/chat_cubit_test.dart
git commit -m "feat(workbench): close via bar->port teardown; ChatTabStore becomes runtime registry"
```

---

## Task 5: Slim `ChatState` + migrate `state.tabs` / `activeTabIndex` / `newChatActive` / `activeSessionId` consumers

**Files:**
- Modify: `lib/cubits/chat/model/chat_state.dart`
- Modify (remove `state.tabs`/`activeTabIndex`/`newChatActive` reads): `lib/cubits/chat/chat_connect_state_mixin.dart`, `lib/cubits/chat/chat_cubit.dart`, `lib/pages/chat/chat_workbench_slice.dart`, `lib/pages/chat/chat_scoped_tab_view.dart`, `lib/pages/chat/chat_page_structural_signal.dart`, `lib/services/commands/session_command_registrar.dart`, `lib/utils/session/workspace_tab_session_scope.dart`, `lib/utils/workspace/workspace_new_chat_active.dart`, `lib/app/app_shell.dart`, `lib/widgets/notification/session_idle_notification_listener.dart`, `lib/widgets/right_tools/right_tools_tool_views.dart`, `lib/pages/chat/chat_page_shell.dart`

**Interfaces:**
- Consumes: `WorkbenchCubit.centerOrder(ws)`, `centerActiveId(ws)`, `enterLanding(ws)`; `ChatCubit` keeps `activeSessionId` / `selectedMemberId` mirrors and `workingSessionIds`.
- Produces: `ChatState` without `tabs` / `activeTabIndex` / `newChatActive`. `ChatScopedTabView` deleted (its role moves to reading the per-workspace bar + registry).

- [ ] **Step 1: Remove the fields from `ChatState`**

In `lib/cubits/chat/model/chat_state.dart`, delete `tabs`, `activeTabIndex`, `newChatActive` fields and their `copyWith` params; delete the `activeCwd` getter (moved: cwd now comes from the active session runtime via `tabStore`). Keep `activeSessionId`, `selectedMemberId` (mirrors), and everything else. `props` updated.

- [ ] **Step 2: Delete `ChatScopedTabView` + `ChatWorkbenchSlice.from`'s tab fields**

- Delete `lib/pages/chat/chat_scoped_tab_view.dart`. Its consumers (`_ChatWorkspaceShell`) switch to reading `WorkbenchCubit` bar bucket + `ChatTabStore` directly (see Task 5 Step 4).
- In `lib/pages/chat/chat_workbench_slice.dart`, drop `tabCount`, `activeTabIndex`, `newChatActive`; keep `stateVersion`, `activeSessionId`, `selectedMemberId`, `sessionLaunchError`. `ChatWorkbench`'s layout uses the active session, not tab index.

- [ ] **Step 3: Migrate the `state.tabs`/`activeTabIndex`/`newChatActive` readers**

Exact mechanical changes (verified current shapes):

| File | Old | New |
|------|-----|-----|
| `chat_connect_state_mixin.dart` (`updateTabRunning`, `setLaunchError`, `clearLaunchError`) | `emit(state.copyWith(tabs: _tabStore.activeTabInfos(), ...))` | drop the `tabs:` arg; emit `state.copyWith(stateVersion: state.stateVersion + 1)` |
| `session_command_registrar.dart:19,23` | `chat.enterNewChat(chat.tabStore.activeWorkspaceId)` | `workbench.enterLanding(chat.tabStore.activeWorkspaceId)` (add `WorkbenchCubit` param to `registerSessionCommands`) |
| `session_command_registrar.dart:27` | `chat.closeTab(chat.state.activeTabIndex)` | `final active = workbench.centerActiveId(ws); if (active != null) workbench.close(ws, active);` |
| `workspace_new_chat_active.dart` | `cubit.state.newChatActive` / `store.isNewChatActive(...)` | `workbench.state.bar(tabScopeId).center.landingActive` |
| `workspace_tab_session_scope.dart` | `store.activeTab(...)`, `store.savedActiveIndexFor(...)` | `chat.tabStore.tabsForWorkspace(tabScopeId)` → `sessionsForWorkspace`; active = `workbench.centerActiveId(tabScopeId)` → its runtime |
| `chat_page_structural_signal.dart` | `state.tabs.map(...)`, `state.activeTabIndex` | compare `workbench.state.bar(tabScopeId).center.order` ids + `activeId` |
| `session_idle_notification_listener.dart`, `right_tools_tool_views.dart`, `app_shell.dart` | `state.tabs` | derive from `tabStore.tabsForWorkspace(activeWs)` (runtime presence) |
| `chat_page_shell.dart` (`_ChatWorkspaceShell`) | `view.tabs`, `ChatScopedTabView.resolve`, `WorkbenchSessionSync` | read `workbench.state.bar(workspaceId).center` for order/active; `sessionIds = order` session ids; delete `ChatScopedTabView` + `WorkbenchSessionSync` |

For `_ChatWorkspaceShell`, the new build reads:

```dart
final bar = workbenchState.bar(workspaceId);
final order = bar.center.order;
final activeId = bar.center.activeId;
final sessionIds = [for (final t in order) if (t.kind == WorkbenchTabKind.session) t.id];
```

`activeTabIndex` for the strip = `activeId == null ? -1 : order.indexOf(activeId)`.

- [ ] **Step 4: Verify green**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Fix every remaining reference until clean. Then `flutter test --exclude-tags integration`.

- [ ] **Step 5: Commit**

```bash
git add lib/cubits/chat/model/chat_state.dart lib/cubits/chat/chat_connect_state_mixin.dart lib/cubits/chat/chat_cubit.dart lib/pages/chat/ test/cubits/ lib/utils/session/workspace_tab_session_scope.dart lib/utils/workspace/workspace_new_chat_active.dart lib/services/commands/session_command_registrar.dart lib/widgets/notification/session_idle_notification_listener.dart lib/widgets/right_tools/right_tools_tool_views.dart
git commit -m "feat(chat): drop tab-list from ChatState; bar is the single strip source"
```

---

## Task 6: Migrate remaining `WorkbenchCubit` callers to the new API; delete wrapper methods

**Files:**
- Modify: `lib/services/workbench/workbench_editor_opener.dart`, `lib/services/workbench/workbench_shell_launcher.dart`, `lib/pages/chat/session_workbench_view_toggle.dart`, `lib/pages/chat_workbench.dart`, `lib/pages/home_workspace/global_resource_manager_host.dart`, `lib/pages/home_workspace/home_workspace_shell.dart`, `lib/pages/home_workspace/workspace/workspace_session_actions.dart`, `lib/pages/home_workspace/workspace/workspace_chat_landing.dart`, `lib/pages/workbench/file_editor_surface.dart`, `lib/services/floating_workspace/migrate_legacy_workbench_tabs.dart`, `lib/services/workbench/workbench_strip_navigator.dart`, `lib/widgets/workbench/workbench_shell_run_sync.dart`
- Modify: `lib/cubits/workbench/workbench_cubit.dart` (delete wrappers)

**Interfaces:**
- Consumes: new API (`openSession`/`openFile`/`openDiff`/`openShell`/`openRun`/`close`/`activate`/`pin`/`reorder`/`enterLanding`/`centerOrder`/`centerActiveId`).
- Produces: no new API; deletes `ensureTab`, `removeTab`, `select`, `reorderTabs`, `pinTab`, `clearActive`, `enterWelcome`, `WorkbenchWorkspaceState`, `WorkbenchState.bucket`.

- [ ] **Step 1: Migrate each caller per this exact table**

| File:Line | Old | New |
|-----------|-----|-----|
| `workbench_editor_opener.dart:77,118` | `_workbench.ensureTab(workspaceId, tab, preview: preview)` (tab is file/diff) | `tab.kind == file ? _workbench.openFile(workspaceId, tab.id, preview: preview) : _workbench.openDiff(workspaceId, tab, preview: preview)` |
| `workbench_shell_launcher.dart:241` (`floating.ensureTab`) | floating shell tab | stays on floating (Task 7), but via `workbench.openShell` once merged — leave for Task 7 if not yet merged |
| `session_workbench_view_toggle.dart:78-79` | `workbench.pinTab(ws, tabId)` / `workbench.ensureTab(ws, tabId, preview: false)` | `workbench.pin(ws, tabId)` / `workbench.openSession(ws, tabId.id, preview: false)` |
| `chat_workbench.dart:765-769` | `workbench.ensureTab(ws, WorkbenchTabId.session(id), preview: false)` | `workbench.openSession(ws, id, preview: false)` |
| `global_resource_manager_host.dart:253-255` | `workbench.ensureTab(ws, WorkbenchTabId.session(sessionId), preview: false)` | `workbench.openSession(ws, sessionId, preview: false)` |
| `workspace_session_actions.dart:124` | `workbench.ensureTab(ws, tabId, preview: false)` | `workbench.openSession(ws, tabId.id, preview: false)` |
| `workspace_session_actions.dart:128-132` | `workbench.ensureTab(ws, tabId, preview: asPreview)` | `workbench.openSession(ws, tabId.id, preview: asPreview)` |
| `workspace_session_actions.dart:241,398` | `workbench.ensureTab(ws, WorkbenchTabId.session(id))` | `workbench.openSession(ws, id)` |
| `workspace_chat_landing.dart`, `file_editor_surface.dart`, `workbench_shell_run_sync.dart:186` | `workbench.removeTab(ws, tab)` | `workbench.close(ws, tab)` |
| `workbench_shell_run_sync.dart:178` | `workbench.tabOrder(ws)` | `workbench.centerOrder(ws)` |
| `workbench_strip_navigator.dart:22,30,39` | `_workbench.tabOrder(ws)` / `_workbench.state.bucket(ws)` | `_workbench.centerOrder(ws)` / `_workbench.state.bar(ws).center` |
| `migrate_legacy_workbench_tabs.dart:92,145,151` | `workbench.removeTab` / `workbench.ensureTab` | `workbench.close` / `workbench.openSession|openFile` per kind |

- [ ] **Step 2: Delete the wrapper methods and facade**

In `workbench_cubit.dart`, delete `ensureTab`, `removeTab`, `select`, `reorderTabs`, `pinTab`, `clearActive`, `enterWelcome`, `tabOrder`, `WorkbenchWorkspaceState`, and `WorkbenchState.bucket`. Keep `centerOrder`, `centerActiveId`, `openSession`, `openFile`, `openDiff`, `openShell`, `openRun`, `close`, `closeOthers`, `closeRight`, `closeAll`, `activate`, `pin`, `reorder`, `enterLanding`, `clearWorkspace`.

- [ ] **Step 3: Verify green**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/cubits/workbench/workbench_cubit.dart lib/services/workbench/ lib/pages/chat/ lib/pages/chat_workbench.dart lib/pages/home_workspace/ lib/pages/workbench/ lib/widgets/workbench/ lib/services/floating_workspace/
git commit -m "refactor(workbench): migrate callers to open/close/activate API; drop legacy facade"
```

---

## Task 7: Floating strip aligned to `bar.floating`

**Files:**
- Modify: `lib/cubits/floating_workspace/floating_workspace_cubit.dart` (buckets → `WorkbenchCubit.floating`; chrome stays)
- Modify: `lib/cubits/floating_workspace/floating_workspace_state.dart` (drop `FloatingWorkspaceBucket` tab lists), `lib/services/workbench/workbench_shell_launcher.dart`, `lib/widgets/workbench/workbench_shell_run_sync.dart`, `lib/pages/floating_workspace/` projection

**Interfaces:**
- Consumes: `WorkbenchCubit.openShell/openRun/close/reorder/activate` on `bar.floating`; produces: `FloatingWorkspaceCubit` chrome-only (`visibility`, `panelPlacement`, `activeWorkspaceId`).

- [ ] **Step 1: Move floating tab buckets into `WorkbenchCubit.floating`**

`FloatingWorkspaceCubit` drops `_buckets` / `tabsChanged`; it keeps chrome (visibility/placement/attention/activeWorkspaceId). Shell/run opens go through `workbench.openShell(ws, entryId)` / `workbench.openRun(ws, id)`; closes through `workbench.close`; selection through `workbench.activate`; reorder through `workbench.reorder`. The floating panel projection reads `workbench.state.bar(ws).floating` + resolves `FloatingTab` payloads by id from `WorkspaceTerminalRegistry` / `RunCubit` (mirroring how the center strip resolves session facts).

- [ ] **Step 2: Migrate floating callers**

`workbench_shell_launcher.dart:241`, `workbench_shell_run_sync.dart:134-154`, `global_resource_manager_host.dart:222,274`, `home_workspace_shell.dart:217`, `migrate_legacy_workbench_tabs.dart`, `floating_workspace_panel.dart:454` — switch `floating.ensureTab/selectTab/setActiveWorkspace` to the bar API.

- [ ] **Step 3: Verify green + commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Commit: `feat(workbench): align floating strip on the shared TabStrip bar`.

---

## Task 8: Regression test for the reported bug + full verification

**Files:**
- Add: `test/cubits/workbench/close_no_resurrect_test.dart`
- Run: full suite

- [ ] **Step 1: Write the regression test**

```dart
// test/cubits/workbench/close_no_resurrect_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

/// Regression: closing a session tab must never make it reappear at the end
/// of the strip. (Root cause of the historical dual-ownership bug.)
void main() {
  test('closing a session tab removes it and no reconcile re-adds it', () {
    final cubit = WorkbenchCubit();
    cubit.openSession('ws', 's1');
    cubit.openSession('ws', 's2');
    cubit.openSession('ws', 's3');

    cubit.close('ws', const WorkbenchTabId.session('s2'));

    final order = cubit.state.bar('ws').center.order;
    expect(order.map((t) => t.id), ['s1', 's3']);

    // Any number of bar mutations must not resurrect the closed id.
    cubit.activate('ws', const WorkbenchTabId.session('s1'));
    cubit.reorder('ws', 0, 1);
    cubit.openSession('ws', 's4');
    expect(cubit.state.bar('ws').center.order.map((t) => t.id),
        ['s3', 's1', 's4']);
    expect(cubit.state.bar('ws').center.order.contains(const WorkbenchTabId.session('s2')),
        isFalse);
  });
}
```

- [ ] **Step 2: Run the regression test**

Run: `cd client && flutter test test/cubits/workbench/close_no_resurrect_test.dart`
Expected: PASS.

- [ ] **Step 3: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: all green. Manually verify the app: open two conversations, close the first via the strip X — it disappears and does not reappear after switching sessions or reordering.

- [ ] **Step 4: Commit**

```bash
git add test/cubits/workbench/close_no_resurrect_test.dart
git commit -m "test(workbench): regression — closed session tab never resurfaces"
```

---

## Self-Review Notes

- **Spec coverage:** TabStrip single owner (T1–T2), bridge feed on open (T3), close-by-id + port teardown (T4), ChatState slim + consumer migration (T5), caller migration + wrapper deletion (T6), floating alignment (T7), regression + verification (T8). Legacy `''` bucket and `syncSessions`/`WorkbenchSessionSync` removed (T3/T4). Performance: bar emits only on structure (T2 core).
- **Type consistency:** `TabStrip`, `TabStripReducer.add/remove/reorder/activate/pin/enterLanding`; `WorkbenchCubit.openSession/openFile/openDiff/openShell/openRun/close/activate/pin/reorder/enterLanding/centerOrder/centerActiveId`; `WorkbenchDomainPort.onTabRemoved`; `WorkbenchChatBridge.onSessionTabOpened`; `ChatWorkbenchPort.onSessionTabClosed/enterLanding/closeAll`; `ChatCubit.teardownSession`. All names consistent across tasks.
