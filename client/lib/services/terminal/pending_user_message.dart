/// A line the user submitted while a member was parked on `wait_for_message`,
/// tracked by the terminal overlay until the receiving member consumes it.
class PendingUserMessage {
  const PendingUserMessage({required this.id, required this.content});

  /// Delivered team-bus message id (used to poll consumption via the session).
  final String id;

  /// The submitted text, shown in the banner.
  final String content;
}
