/// Internal clipboard for file-tree copy/cut + paste (not the OS clipboard).
enum FileTreeClipboardMode { copy, cut }

class FileTreeClipboard {
  const FileTreeClipboard({required this.path, required this.mode});

  final String path;
  final FileTreeClipboardMode mode;
}
