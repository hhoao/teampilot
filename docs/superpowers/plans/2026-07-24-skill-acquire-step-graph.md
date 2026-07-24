# Skill Acquire Step Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace kind-based skill acquire with a step-graph engine; make gstack the reference pack (skills + bin + optional setup + PATH export).

**Architecture:** `SkillInstallRecipe` + handler registry; `SkillAcquisitionEngine` only runs recipes; packs own recipes; deps reference `packId` or inline recipe; no `SkillAcquireSpec.kind` compat.

**Tech Stack:** Dart/Flutter, existing `SkillRepoDiskCacheService` / `SkillInstallService`, AppStorage FS.

---

## File map

| File | Role |
|------|------|
| `client/lib/models/skill_install_recipe.dart` | Step / Exports / Recipe |
| `client/lib/models/skill_pack.dart` | `recipe` replaces `acquire` |
| `client/lib/models/skill_acquire_spec.dart` | **Delete** (or shrink to script URL helper only if needed) |
| `client/lib/models/discoverable_team.dart` / `skill.dart` | Dep uses `recipe` / `packId`; drop kind resolution |
| `client/lib/services/skill/acquire/*` | Context, handler interface, handlers, runner |
| `client/lib/services/skill/skill_acquisition_engine.dart` | Recipe resolve + run |
| `client/lib/services/skill/skill_pack_install_store.dart` | Persist pack exports |
| `client/lib/services/skill/skill_pack_registry.dart` | gstack recipe |
| `skill-packs/gstack/pack.json` | Mirror recipe |
| `member-hub/members/gstack-*/member.json` | Drop `acquire.kind` |
| Session launch env merge | Prepend pack PATH |
| Tests | Recipe parse, handlers, gstack pack install, PATH |

---

### Task 1: Recipe models + failing tests

**Files:**
- Create: `client/lib/models/skill_install_recipe.dart`
- Create: `client/test/models/skill_install_recipe_test.dart`
- Delete usages of `SkillAcquireSpec.kind` progressively

- [ ] Write test: parse steps/needs/exports; reject unknown required fields lightly
- [ ] Implement `SkillInstallStep`, `SkillInstallExports`, `SkillInstallRecipe`
- [ ] Run `flutter test test/models/skill_install_recipe_test.dart`

### Task 2: Handler registry + engine runner

**Files:**
- Create: `client/lib/services/skill/acquire/skill_acquire_context.dart`
- Create: `client/lib/services/skill/acquire/skill_step_handler.dart`
- Create: handlers `git_sync`, `skill_install_dir`, `skill_register_pack`, `fs_materialize`, `script_run`
- Rewrite: `skill_acquisition_engine.dart`

- [ ] Failing test: recipe with fake handlers runs in needs order
- [ ] Implement runner (validate needs, skip optional failures)
- [ ] Implement real handlers wired to install/cache/FS
- [ ] Tests green for register-pack + materialize (fake FS)

### Task 3: Pack + dep migration (no kind)

**Files:**
- Update: `skill_pack.dart`, `skill_pack_registry.dart`, `pack.json`
- Update: `SkillDependencyRef` / `DiscoverableSkill`
- Update: all `member-hub` gstack JSON
- Update/remove: `skill_acquire_spec.dart` + old tests

- [ ] Pack carries `recipe`; gstack includes bin + optional setup
- [ ] Deps: `packId` only (no acquire kind)
- [ ] Synthesize single-dir recipe when repo+directory set and no packId
- [ ] Fix all compile breaks / tests

### Task 4: Persist exports + session PATH

**Files:**
- Create: `skill_pack_install_store.dart`
- Wire engine to write store after pack recipe success
- Hook launch environment builder to merge PATH for packs owning session skills

- [ ] Test store round-trip
- [ ] Test PATH prepend when pack bin present
- [ ] Manual note in design: force-refresh hub after push

### Task 5: Docs + verify

- [ ] Update skillpack / acquisition design docs to point at step-graph spec
- [ ] `flutter test` focused suites
- [ ] Commit when user asks
