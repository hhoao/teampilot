/// Outcome of shell connect after launch prep and lifecycle gating.
enum ConnectShellResult {
  attached,
  deferred,
  failed,
  aborted,
}
