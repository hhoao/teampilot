# Bus Multiline Paste Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parked mixed-seat terminal paste enqueues one TeamBus mail for a multi-line paste; Enter remains the submit edge.

**Architecture:** Extend `BusUserLineCapture` with bracketed-paste state and a non-bracketed same-chunk coalesce fallback. No changes to TeamBus or UI overlays (they already render one bubble per mail).

**Tech Stack:** Dart / Flutter unit tests (`bus_user_line_capture_test.dart`)

---

### Task 1: Failing tests for multiline paste

**Files:**
- Modify: `client/test/services/team_bus/bus_user_line_capture_test.dart`

- [x] **Step 1: Write failing tests** (bracketed paste + Enter → one mail; non-bracketed chunk → one mail; two Enters → two mails)
- [x] **Step 2: Run tests — confirm RED**

### Task 2: Implement capture behavior

**Files:**
- Modify: `client/lib/services/team_bus/bus_user_line_capture.dart`

- [x] **Step 1: Bracketed paste mode + newline-as-content**
- [x] **Step 2: Non-bracketed same-chunk coalesce**
- [x] **Step 3: Run unit tests — GREEN**
- [x] **Step 4: Update class doc comment to match behavior**

### Task 3: Verify no regressions

- [x] **Step 1:** `flutter test test/services/team_bus/bus_user_line_capture_test.dart`
- [x] **Step 2:** Spot-check `team_bus_user_command_test.dart`
