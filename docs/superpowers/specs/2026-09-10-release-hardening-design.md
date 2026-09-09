# 3.23.0 Release Candidate Hardening Design

## Goal

Validate, harden, integrate, and release the 28 commits currently ahead of
`origin/main` as TeamPilot `3.23.0`, while preserving unrelated uncommitted
changes inside vendored submodules.

## Scope

- Review the local `main` commit range `origin/main..HEAD` and its existing
  tests, with emphasis on SVG workbench preview, multi-root search, and
  terminal incident detection.
- Keep the existing uncommitted changes in `client/packages/dartssh2`,
  `client/packages/flutter_alacritty`, and `client/third_party/fastforge`
  untouched and unstaged.
- Fix only failures or defects attributable to the release-candidate range;
  do not weaken CI checks or make unrelated refactors.
- Use the repository test wrapper, never direct `flutter test`.

## Validation and Debugging

The validation sequence is:

1. Run `flutter analyze --no-fatal-infos --no-fatal-warnings`.
2. Run focused tests for the changed workbench and search behavior.
3. For each failure, add or adjust a minimal regression test, observe the
   expected failure, implement the root-cause fix, and rerun the focused test.
4. Run the required full local gates once before integration:
   `flutter analyze --no-fatal-infos --no-fatal-warnings` and
   `dart run tool/run_tests.dart`.
5. Push the verified candidate and monitor all relevant GitHub Actions jobs.
   Fix only code or configuration failures caused by this candidate.

## Release

The user-visible feature additions warrant a minor release from `3.22.0` to
`3.23.0`. The version bump will be a separate commit after the candidate is
green. The repository's auto-tag workflow is expected to create `v3.23.0` and
dispatch the release workflow; the release is complete only after its package
jobs succeed and the GitHub Release is published.

## Constraints

- Do not overwrite or commit unrelated worktree changes.
- Preserve the repository's layering, l10n, member-placement, storage-root,
  and CLI-registry conventions from `AGENTS.md`.
- Do not alter CI merely to hide a failure.
