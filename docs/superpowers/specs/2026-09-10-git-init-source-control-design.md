# Source Control Git Repository Initialization

## Goal

When the Source Control panel detects that a workspace folder is not a Git
repository, let the user initialize that folder as a repository from the UI.

## Design

The existing Git command abstraction remains the only path for executing Git:

- Add an `init` operation to `GitService`, implemented through its injected
  `GitCommandRunner`.
- Add an initialization action to `GitCubit`. It runs against the current
  `repoRoot`, preserves the existing busy/error state conventions, and refreshes
  status after success.
- Extend the non-repository state in `GitSourceControlPanel` with a localized
  action button. The single-root view uses that root; the multi-root view uses
  the currently selected root. Empty roots and unavailable Git keep their
  existing hint-only states.

The button uses the existing panel styling and is enabled only while no Git
operation is running. Success changes the panel to the normal repository view
through the refresh result. Failures are surfaced through the existing
localized Git error toast; no raw process output is shown directly in the UI.

## Testing

- Git service tests verify that initialization invokes the runner with the
  expected directory and command arguments, and reports non-zero exits as
  `GitException`.
- Git cubit tests verify that initialization refreshes a non-repository state
  into a repository state and exposes failures through `errorMessage`.
- Source Control widget tests verify that the button appears only for a
  non-repository root and triggers initialization for the selected root in a
  multi-root workspace.

## Scope

This change does not add repository-name, initial-branch, or remote setup
options. It only performs the equivalent of `git init` in the selected
workspace folder.
