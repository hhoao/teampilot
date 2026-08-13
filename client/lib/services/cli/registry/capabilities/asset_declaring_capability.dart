import '../cli_capability.dart';
import 'cli_config_asset.dart';

/// 能力侧纯声明资产（依赖反转：能力不持有 Registry）。
///
/// 惰性 getter：可依赖运行时数据（如 session 才知道的 ack endpoint）。
abstract interface class AssetDeclaringCapability implements CliCapability {
  List<CliConfigAsset> get declaredAssets;
}
