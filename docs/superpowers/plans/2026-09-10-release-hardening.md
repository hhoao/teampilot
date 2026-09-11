# 3.23.0 Release Candidate Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Make the local release candidate green, push it to \`main\`, and publish TeamPilot \`3.23.0\`.

**Architecture:** Treat the existing local commits as the candidate and preserve dirty vendored submodules outside the candidate. Use focused tests and static analysis to identify regressions, apply test-first root-cause fixes only in candidate-owned files, then run the full local gates before pushing. Versioning and release remain separate from functional fixes.

**Tech Stack:** Flutter stable, Dart, Flutter analyzer, \`client/tool/run_tests.dart\`, Git, GitHub Actions, and \`gh\`.

## Global Constraints

- Never invoke \`flutter test\` directly; route client tests through \`cd client && dart run tool/run_tests.dart\`.
- Preserve dirty changes in \`client/packages/dartssh2\`, \`client/packages/flutter_alacritty\`, and \`client/third_party/fastforge\`.
- Before completion, run \`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart\`.
- Do not weaken workflows or checks to make CI pass.
- Use \`3.23.0\` because the candidate contains user-visible minor features beyond \`3.22.0\`.
- Stage only named files; never use \`git add -A\`.

---

### Task 1: Establish the candidate baseline

**Files:**
- Read: \`AGENTS.md\`, \`docs/DEVELOPMENT.md\`, \`docs/CODE_QUALITY.md\`
- Read: \`.github/workflows/client-verify.yml\`, \`.github/workflows/auto-tag.yml\`, \`.github/workflows/release.yml\`
- Test: changed workbench and search tests

**Interfaces:**
- Consumes: local \`main\` at \`origin/main..HEAD\`.
- Produces: recorded analysis, focused-test, candidate-file, and workflow state.

- [ ] **Step 1: Confirm boundaries**

~~~bash
git status --short --branch
git diff --submodule=short -- client/packages/dartssh2 client/packages/flutter_alacritty client/third_party/fastforge
git diff --name-only origin/main..HEAD
~~~

Expected: only the three named submodules are dirty outside committed files.

- [ ] **Step 2: Run static analysis**

~~~bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Expected: exit 0. A failure records its first application diagnostic for Task 3.

- [ ] **Step 3: Run focused tests through the wrapper**

~~~bash
cd client
dart run tool/run_tests.dart \
  test/pages/workbench/file_editor_image_preview_test.dart \
  test/pages/workbench/file_editor_surface_svg_test.dart \
  test/pages/workbench/svg_preview_pane_test.dart \
  test/services/editor/file_editor_theme_image_test.dart \
  test/services/editor/svg_view_mode_store_test.dart \
  test/widgets/workbench/editor_view_mode_toggle_test.dart
~~~

Expected: exit 0. If a listed path is absent, confirm with \`test -e\` and omit only that path.

- [ ] **Step 4: Capture remote state**

~~~bash
git log --oneline --decorate origin/main..HEAD
gh run list --repo hhoao/teampilot --limit 10
~~~

Expected: candidate commits and existing remote failures are recorded before push.

### Task 2: Audit changed behavior

**Files:**
- Read: \`git diff --name-only origin/main..HEAD\`
- Read: relevant implementation and test files under \`client/lib/\` and \`client/test/\`

**Interfaces:**
- Consumes: Task 1 failures and candidate diff.
- Produces: deterministic failure signatures tied to earliest application stack frames, or a clean audit.

- [ ] **Step 1: Check diff integrity**

~~~bash
git diff --check origin/main..HEAD
git diff --stat origin/main..HEAD
git diff --color=never origin/main..HEAD -- client/lib client/test
~~~

Expected: no whitespace errors and no unexplained behavior changes.

- [ ] **Step 2: Reproduce each failure narrowly**

~~~bash
cd client
dart run tool/run_tests.dart test/pages/workbench/svg_preview_pane_test.dart
~~~

Expected: the same failure reproduces deterministically through the wrapper.

- [ ] **Step 3: Classify the root cause**

Inspect the earliest application frame and classify it as stale async retargeting, zoom baseline state, view-mode state, multi-root aggregation, rendering, or environment/tooling. Only application-owned failures proceed to Task 3.

### Task 3: Fix verified regressions test-first

**Files:**
- Test: smallest existing test file that reproduces the failure
- Modify: only the application file containing the earliest faulty behavior

**Interfaces:**
- Consumes: one deterministic failure signature from Task 2.
- Produces: a failing regression test, minimal root-cause fix, and green focused tests.

- [ ] **Step 1: Add one observable regression test**

~~~dart
testWidgets('ignores a stale preview load after the file path changes',
    (tester) async {
  // Reuse the existing fake loader and harness in the selected test file.
  // Retarget from path A to path B, complete A after the retarget, and assert
  // that rendered bytes and zoom state still belong to path B.
});
~~~

Use the actual behavior identified in Task 2; do not test only mock call counts.

- [ ] **Step 2: Verify RED**

~~~bash
cd client
dart run tool/run_tests.dart test/pages/workbench/svg_preview_pane_test.dart
~~~

Expected: FAIL for the identified product behavior, not a syntax or harness error.

- [ ] **Step 3: Implement the smallest root-cause fix**

Preserve existing ownership boundaries. For async work, check the current retarget generation before publishing bytes or resetting zoom; for aggregation, preserve slice identity through fan-out and merge; for view state, key state by canonical path and dispose listeners with their owner. Do not add retries, broad null checks, or CI exceptions without a test requiring them.

- [ ] **Step 4: Verify GREEN and analyzer**

~~~bash
cd client
dart run tool/run_tests.dart test/pages/workbench/svg_preview_pane_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Expected: the regression test and analyzer both exit 0.

- [ ] **Step 5: Check scope**

~~~bash
git diff --check
git diff -- client/lib client/test
~~~

Expected: only intentional fix and regression-test files are changed.

### Task 4: Complete local quality gates

**Files:**
- Test: all default client tests
- Read: \`client/pubspec.yaml\`

**Interfaces:**
- Consumes: candidate plus verified fixes.
- Produces: fresh local evidence for integration.

- [ ] **Step 1: Run analyzer**

~~~bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Expected: exit 0.

- [ ] **Step 2: Run the full suite once**

~~~bash
cd client
dart run tool/run_tests.dart
~~~

Expected: exit 0 with zero failed tests.

- [ ] **Step 3: Confirm staging boundaries**

~~~bash
git status --short
git diff --check
~~~

Expected: intentional root changes only; the three pre-existing submodules remain dirty and unstaged.

### Task 5: Review, commit, push, and babysit CI

**Files:**
- Modify: only verified fix files, if any

**Interfaces:**
- Consumes: passing local gates.
- Produces: pushed green candidate and triaged CI state.

- [ ] **Step 1: Review the candidate diff**

Review \`origin/main..HEAD\` plus fixes for correctness, regressions, coverage, and scope. Resolve all Critical and Important findings before integration.

- [ ] **Step 2: Commit fixes**

~~~bash
git add client/lib/pages/workbench client/lib/services client/test/pages/workbench client/test/services
git commit -m "fix: harden release candidate behavior"
~~~

- [ ] **Step 3: Push main**

~~~bash
git push origin main
~~~

If branch policy rejects direct push, create a PR from the current branch and use \`babysit\` for comments, conflicts, and CI.

- [ ] **Step 4: Watch CI**

~~~bash
run_id=$(gh run list --repo hhoao/teampilot --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo hhoao/teampilot --exit-status
~~~

For candidate-owned failures, apply Task 3, commit, push, and watch the new run. Never edit checks merely to hide a failure.

### Task 6: Release \`3.23.0\`

**Files:**
- Modify: \`client/pubspec.yaml:5\`

**Interfaces:**
- Consumes: green pushed candidate at \`3.22.0\`.
- Produces: version \`3.23.0\` and an auto-tag trigger.

- [ ] **Step 1: Bump the version**

~~~diff
-version: 3.22.0
+version: 3.23.0
~~~

- [ ] **Step 2: Re-run required gates**

~~~bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
~~~

Expected: both commands exit 0.

- [ ] **Step 3: Commit and push**

~~~bash
git add client/pubspec.yaml
git commit -m "chore: release 3.23.0"
git push origin main
~~~

Expected: auto-tag workflow starts according to \`.github/workflows/auto-tag.yml\`.

### Task 7: Verify publication

**Files:**
- Read: \`.github/workflows/auto-tag.yml\`, \`.github/workflows/release.yml\`

**Interfaces:**
- Consumes: pushed \`3.23.0\` commit.
- Produces: \`v3.23.0\`, successful package jobs, and a published GitHub Release.

- [ ] **Step 1: Watch auto-tag**

~~~bash
run_id=$(gh run list --repo hhoao/teampilot --workflow auto-tag.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo hhoao/teampilot --exit-status
~~~

Expected: success and remote tag \`v3.23.0\`.

- [ ] **Step 2: Watch release packages**

~~~bash
run_id=$(gh run list --repo hhoao/teampilot --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo hhoao/teampilot --exit-status
~~~

Expected: all required platform package and publication jobs pass.

- [ ] **Step 3: Verify the final release**

~~~bash
gh release view v3.23.0 --repo hhoao/teampilot
git ls-remote --tags origin v3.23.0
~~~

Expected: GitHub reports a published \`v3.23.0\` release and the remote tag resolves to the version-bump commit.
