import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    await RustBuilder(
      // asset id 与 ffigen 产物文件名一致（tree_sitter 同款），
      // @Native externals 才能免显式 asset id 解析。
      assetName: 'teampilot_search_bindings_generated.dart',
      cratePath: 'rust',
    ).run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        // ignore: avoid_print
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
