/// Returns `ssh:…` when [message] matches provision/connect missing-profile text.
String? deadSshTargetIdFromError(String? message) {
  if (message == null) return null;
  final match = RegExp(
    r'No SSH profile for target "(ssh:[^"]+)"',
  ).firstMatch(message);
  return match?.group(1);
}
