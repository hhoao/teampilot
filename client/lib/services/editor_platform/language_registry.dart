import 'package:teampilot/services/editor_platform/language_pack.dart';

/// Resolves file paths to [LanguagePack]s. Unknown extensions (including
/// extensions intentionally left as plain text, e.g. `.scss` this phase)
/// resolve to `null` — callers must not substitute a different language's
/// grammar as a stand-in.
class LanguageRegistry {
  LanguageRegistry(List<LanguagePack> packs) : _packs = List.unmodifiable(packs);

  /// Built-in packs shipped with the app. Task 3 registers `json` only;
  /// later tasks extend this list without changing the registry API.
  factory LanguageRegistry.builtins() {
    return LanguageRegistry(const [
      LanguagePack(
        id: 'json',
        extensions: {'json'},
        grammarId: 'json',
        highlightsAsset: 'assets/editor_languages/json/highlights.scm',
      ),
    ]);
  }

  final List<LanguagePack> _packs;

  /// All registered packs, in registration order.
  List<LanguagePack> get packs => _packs;

  /// Looks up the pack for [path] by basename, then by lowercase
  /// extension (without the leading dot). Returns `null` when no pack
  /// claims this path.
  LanguagePack? resolve(String path) {
    final basename = _basename(path);
    for (final pack in _packs) {
      if (pack.filenames.contains(basename)) {
        return pack;
      }
    }

    final extension = _extension(basename);
    if (extension == null) {
      return null;
    }
    for (final pack in _packs) {
      if (pack.extensions.contains(extension)) {
        return pack;
      }
    }
    return null;
  }

  /// Looks up a registered pack by its [LanguagePack.id].
  LanguagePack? byId(String id) {
    for (final pack in _packs) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    return slashIndex == -1 ? normalized : normalized.substring(slashIndex + 1);
  }

  static String? _extension(String basename) {
    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == basename.length - 1) {
      return null;
    }
    return basename.substring(dotIndex + 1).toLowerCase();
  }
}
