/// A user-triggered git operation that can be in flight.
///
/// Lives in the state so both the source-control panel and the git graph
/// toolbar can animate the exact control that owns the work, and so every
/// other action can be disabled instead of silently dropped.
enum GitOperation {
  refresh,
  fetch,
  pull,
  push,
  commit,
  discard,
  init,
  checkout,
  branchCreate,
}
