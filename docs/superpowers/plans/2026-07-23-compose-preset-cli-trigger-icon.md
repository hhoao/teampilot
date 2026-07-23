# Compose Preset CLI Trigger Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session chat preset chip trigger shows `CliBrandIcon` for the selected/locked CLI.

**Architecture:** Optional `leading` widget on compose toolbar chips; preset chip resolves CLI and passes `CliBrandIcon`.

**Tech Stack:** Flutter, existing `CliBrandIcon` / `ComposeModelPresetChip`.

**Spec:** `docs/superpowers/specs/2026-07-23-compose-preset-cli-trigger-icon-design.md`

---

### Task 1: Chip leading slot + preset CLI icon

**Files:**
- Modify: `client/lib/widgets/compose/compose_menu_chip.dart`
- Modify: `client/lib/widgets/compose/compose_model_preset_chip.dart`
- Test: `client/test/widgets/compose/compose_chips_test.dart` (extend if needed)

- [x] **Step 1:** Add optional `Widget? leading` to `ComposeToolbarChip` and `ComposeMenuChip`; prefer `leading` over `Icon(icon)` when set.
- [x] **Step 2:** In `ComposeModelPresetChip`, resolve CLI from selected preset (or sole same-CLI list), pass `CliBrandIcon` as `leading`.
- [x] **Step 3:** Run `flutter test test/widgets/compose/compose_chips_test.dart` and any session continue chrome test that covers the chip.
- [ ] **Step 4:** Commit only if user asks.
