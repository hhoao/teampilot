enum AppSection { chat, runs, config }

class TabInfo {
  const TabInfo({required this.id, required this.title, this.working = false});

  final String id;
  final String title;

  /// Session has a member in a turn → show the working spinner left of title.
  final bool working;
}
