abstract final class TeamBusPrompt {
  TeamBusPrompt._();

  static String format({
    required String type,
    required String content,
    Map<String, String> attributes = const {},
  }) {
    final values = <String, String>{'type': type, ...attributes};
    final attrs = values.entries
        .map((entry) => ' ${entry.key}="${_escape(entry.value)}"')
        .join();
    return '<teambus$attrs>${_escape(content)}</teambus>';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
