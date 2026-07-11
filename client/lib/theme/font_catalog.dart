enum FontRole { ui, mono }

enum FontSourceKind { system, bundled }

class FontCatalogEntry {
  const FontCatalogEntry({
    required this.id,
    required this.role,
    required this.source,
    this.bundledFamily,
    this.assetPaths = const [],
  });

  final String id;
  final FontRole role;
  final FontSourceKind source;
  final String? bundledFamily;
  final List<String> assetPaths;
}

abstract final class FontCatalog {
  static const systemId = 'system';

  static const List<FontCatalogEntry> all = [
    FontCatalogEntry(id: systemId, role: FontRole.ui, source: FontSourceKind.system),
    FontCatalogEntry(
      id: 'notoSansSc',
      role: FontRole.ui,
      source: FontSourceKind.bundled,
      bundledFamily: 'Noto Sans SC',
    ),
    FontCatalogEntry(id: systemId, role: FontRole.mono, source: FontSourceKind.system),
    FontCatalogEntry(
      id: 'jetbrainsMono',
      role: FontRole.mono,
      source: FontSourceKind.bundled,
      bundledFamily: 'JetBrainsMono NFM',
      assetPaths: [
        'assets/fonts/terminal/JetBrainsMonoNerdFontMono-Regular.ttf',
      ],
    ),
    FontCatalogEntry(
      id: 'ubuntuSansMono',
      role: FontRole.mono,
      source: FontSourceKind.bundled,
      bundledFamily: 'Ubuntu Sans Mono',
      assetPaths: [
        'assets/fonts/terminal/UbuntuSansMono-Regular.ttf',
        'assets/fonts/terminal/UbuntuSansMono-Bold.ttf',
      ],
    ),
  ];

  static Iterable<FontCatalogEntry> get uiOptions =>
      all.where((e) => e.role == FontRole.ui);

  static Iterable<FontCatalogEntry> get monoOptions =>
      all.where((e) => e.role == FontRole.mono);

  static FontCatalogEntry entry(FontRole role, String id) {
    for (final e in all) {
      if (e.role == role && e.id == id) return e;
    }
    return all.firstWhere(
      (e) => e.role == role && e.id == systemId,
    );
  }

  static bool isKnown(FontRole role, String id) =>
      all.any((e) => e.role == role && e.id == id);
}
