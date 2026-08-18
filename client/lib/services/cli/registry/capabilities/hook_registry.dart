/// 生成的脚本文件（统一 writer / 装配点落盘）。
class GeneratedScript {
  const GeneratedScript({
    required this.fileName,
    required this.content,
    this.targetDirectory,
  });

  final String fileName;
  final String content;

  /// Optional target directory for target-native scripts that live outside
  /// the shared hooks directory. The provisioner performs the actual write.
  final String? targetDirectory;
}
