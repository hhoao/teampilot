/// Watch metadata for live transcript refresh after [locate].
class AiHistoryWatchMeta {
  const AiHistoryWatchMeta({
    required this.changeWatchRoot,
    required this.cacheTokenPaths,
  });

  final String changeWatchRoot;
  final List<String> cacheTokenPaths;

  static const hintRoot = 'changeWatchRoot';
  static const hintPaths = 'cacheTokenPaths';

  static AiHistoryWatchMeta? fromHints(Map<String, String> hints) {
    final root = hints[hintRoot]?.trim();
    if (root == null || root.isEmpty) return null;

    final pathsRaw = hints[hintPaths]?.trim() ?? '';
    final paths = pathsRaw.isEmpty
        ? const <String>[]
        : pathsRaw.split('\n').where((p) => p.isNotEmpty).toList(growable: false);

    return AiHistoryWatchMeta(
      changeWatchRoot: root,
      cacheTokenPaths: paths,
    );
  }

  Map<String, String> toHints() => {
    hintRoot: changeWatchRoot,
    hintPaths: cacheTokenPaths.join('\n'),
  };
}
