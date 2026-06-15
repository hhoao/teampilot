# 丰富文件树文件图标 — 设计文档

- **日期**: 2026-06-15
- **状态**: 设计已批准，待编写实现计划
- **作者**: brainstorming session
- **相关文件**: `client/lib/utils/file_icon.dart`, `client/lib/widgets/file_tree_node.dart`, `client/lib/widgets/file_editor/file_editor_tab.dart`

## 背景与动机

当前文件树（文件树、编辑器标签页）的文件图标由 `lib/utils/file_icon.dart` 的 `fileIconForFileName()` 提供，它只有 31 行，把扩展名映射到 6 类 Material Icons：

- `dart` → `Icons.code`
- `yaml`/`yml`/`json` → `Icons.settings`
- `md` → `Icons.description_outlined`
- `png`/`jpg`/`jpeg`/`gif`/`svg` → `Icons.image_outlined`
- `zip`/`tar`/`gz` → `Icons.archive_outlined`
- 默认 → `Icons.insert_drive_file_outlined`

图标形状单一、单色、覆盖面窄（绝大多数文件落到默认通用图标），辨识度低，与 TeamPilot 作为 AI Agent IDE 客户端的定位不符。

## 目标

复用生产级文件图标集合，让文件树中每种文件类型有独立形状 + 彩色的图标，达到 IDE 级（VSCode 风格）的文件树观感。

## 方案选择

调研了三个方向，选定方案 A + 彩色：

| 方案 | 描述 | 取舍 |
|------|------|------|
| **A（选定）** | 复用 VSCode Material Icon Theme 的 SVG + 映射表 | 覆盖最全（数百类型彩色图标），零新增依赖（复用已有 `flutter_svg`），代价是 assets 增加约 1MB |
| B | pub 包 `file_icon` / `material_file_icon` | 开箱即用但覆盖有限（几十种）、多为单色，提升幅度不大 |
| C | 现有 Material Icons + 按类型上色 | 改动最小零依赖，但图标形状仍只有 6 类，辨识度提升有限 |

**彩色 vs 单色**：选定彩色。每种文件类型有专属配色是"丰富文件图标"的核心价值，辨识度最高；用户熟悉 VSCode 文件树观感，认知成本最低。

## 选定方案详情

### 数据源

- **npm 包**: `material-icon-theme@5.35.0`（MIT 协议）
  - `icons/*.svg` — 1245 个 SVG，总计约 1MB，平均 836B/个，标准 32×32 viewBox，内嵌 `fill` 色实现彩色
  - `dist/material-icons.json` — 编译好的扁平映射表，无需解析上游 TypeScript 源码
- **协议合规**: MIT，需在仓库 NOTICE/README 致谢

### 映射表结构（来自 `material-icons.json`）

```
top keys:
  iconDefinitions   — 所有图标定义
  fileExtensions    — { "dart": "dart", "json": "json", ... }  ~300+ 条
  fileNames         — { "pubspec.yaml": "dart", ".gitignore": "git", ... }  ~600+ 条精确文件名
  languageIds       — 语言 ID 映射
  light:
    fileExtensions  — 31 条需要浅色变体的扩展名
    fileNames       — 需要浅色变体的精确文件名
```

匹配优先级：精确文件名 > 扩展名 > 默认 `file` 图标。例：`pubspec.yaml` 命中文件名表得到 `dart` 图标，而非扩展名表的 `yaml`；`README.md` 得到 `readme` 而非通用 `markdown`。

## 架构

### 构建期（代码生成）

```
tools/sync_material_icons.dart
  ← 输入: material-icon-theme npm 包（icons/*.svg + dist/material-icons.json）
  → 输出:
     client/assets/file_icons/*.svg          (被映射表引用的 SVG, ~600-800 个)
     client/lib/utils/file_icon_mapping.g.dart (扩展名/文件名 → 图标名, 含 light 集)
```

**资产范围决策**：全量引入（映射表实际引用的图标，而非全部 1245 个）。理由：
- 总体积 ~1MB，对桌面端可忽略
- 避免维护"白名单"——映射表指向的图标必然存在，脚本只拷贝被引用的，自动正确
- 符合"复用生产级集合、低维护"的初衷

### 运行期（渲染）

```
file_tree_node.dart / file_editor_tab.dart
  → FileIconWidget(fileName: name, size: md)
      ├─ fileIconForFileName(name) → FileIconInfo(iconName, isLightVariant)
      │    1. kFileNameIcons[lower] (精确文件名优先)
      │    2. kFileExtensionIcons[ext]
      │    3. kDefaultFileIcon
      └─ SvgPicture.asset('assets/file_icons/$iconName${useLight?'_light':''}.svg')
           彩色 SVG 默认保留 fill 色，无需额外配色
```

## 组件与职责

| 单元 | 路径 | 职责 | 依赖 |
|------|------|------|------|
| 同步脚本 | `tools/sync_material_icons.dart` | 从 npm 包生成资产 + 映射代码；幂等 | npm（外部）|
| 映射数据 | `client/lib/utils/file_icon_mapping.g.dart` | 扩展名/文件名 → 图标名（纯 const 数据）| 无 |
| 解析逻辑 | `client/lib/utils/file_icon.dart` | `fileIconForFileName()` 返回 `FileIconInfo` | mapping.g.dart |
| 渲染组件 | `client/lib/widgets/file_icon_widget.dart` | `FileIconWidget` 渲染彩色 SVG | flutter_svg, file_icon.dart |

## 关键接口

### `FileIconInfo`（`file_icon.dart`）

```dart
class FileIconInfo {
  const FileIconInfo(this.iconName, {this.isLightVariant = false});
  final String iconName;
  final bool isLightVariant;
}

FileIconInfo fileIconForFileName(String name) {
  final baseName = name.split('/').last;
  final lower = baseName.toLowerCase();
  // 1. 精确文件名优先
  final byName = kFileNameIcons[lower];
  if (byName != null) {
    return FileIconInfo(byName, isLightVariant: kLightFileNames.contains(lower));
  }
  // 2. 扩展名
  final ext = lower.contains('.') ? lower.split('.').last : '';
  final byExt = kFileExtensionIcons[ext];
  if (byExt != null) {
    return FileIconInfo(byExt, isLightVariant: kLightFileExtensions.contains(ext));
  }
  // 3. 默认
  return const FileIconInfo(kDefaultFileIcon);
}
```

**破坏性改动**：返回值从 `IconData` 改为 `FileIconInfo`。不保留旧重载（YAGNI，仅 2 处调用，编译器护航逐一改）。

### `FileIconWidget`（`file_icon_widget.dart`）

```dart
class FileIconWidget extends StatelessWidget {
  const FileIconWidget({required this.fileName, this.size = 16, super.key});
  final String fileName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final info = fileIconForFileName(fileName);
    final useLight = Theme.of(context).brightness == Brightness.light &&
        info.isLightVariant;
    final asset = 'assets/file_icons/${info.iconName}${useLight ? '_light' : ''}.svg';
    return SvgPicture.asset(asset, width: size, height: size);
  }
}
```

彩色图标不染色——`flutter_svg` 默认保留 SVG 内 `fill` 色。

## 同步脚本职责（`tools/sync_material_icons.dart`）

与现有 `tool/gen_warmup_glyphs.dart`、`tool/sync_bundled_google_fonts.dart` 风格一致。

```
输入参数:
  --npm-package <path>   material-icon-theme npm 包解压目录（默认临时下载）
  --force                跳过版本缓存

执行步骤:
  1. 校验 npm 包存在，读取 dist/material-icons.json
  2. 扫描 iconDefinitions 得到所有被引用的图标名集合
  3. 收集 fileExtensions + fileNames → 图标名的完整映射
  4. 收集 light.fileExtensions + light.fileNames → 标记 _light 变体
  5. 从 icons/ 拷贝被引用的 SVG 到 client/assets/file_icons/
       普通图标: {name}.svg
       需要 light 变体且源存在: {name}_light.svg
  6. 生成 lib/utils/file_icon_mapping.g.dart:
       const materialFileIconsVersion = '5.35.0';
       const Map<String,String> kFileExtensionIcons = {...};
       const Map<String,String> kFileNameIcons = {...};
       const Set<String> kLightFileExtensions = {...};
       const Set<String> kLightFileNames = {...};
       const String kDefaultFileIcon = 'file';
  7. 资产完整性断言: 生成代码里每个图标名都有对应 SVG，缺失则失败
  8. 打印同步摘要: 版本、图标数、新增/删除/变更数

幂等保证: 映射表键排序输出，SVG 文件名归一，重复运行结果一致。
```

### 版本治理

生成的 `.g.dart` 头部写入源版本号。脚本启动时比对缓存版本，不符时警告（不阻断），方便知道当前资产对应的上游版本。

## 调用点改造

| 文件 | 现状 | 改造 |
|------|------|------|
| `widgets/file_tree_node.dart:143-148` | `Icon(isDir ? folder : fileIconForFileName(name), size: md)` | 文件分支改 `FileIconWidget(fileName: name, size: md.iconSize)`；目录分支保持 `Icon(folder)` |
| `widgets/file_editor/file_editor_tab.dart:131` | `fileIconForFileName(fileName)` 传给 `Icon` | 改为 `FileIconWidget(fileName: fileName, size: ...)` |

## 范围外（YAGNI）

- **文件夹图标**: 不纳入。当前 `Icons.folder_outlined` / `folder_open` 已够清晰；VSCode Material Icon Theme 的 folderNames 映射含 folder color theming，复杂度高，超出"丰富文件图标"范围。
- **图标可配置性/主题切换**: 不做。彩色固定，light 变体随系统主题自动。
- **懒加载/按需加载 SVG**: 不做。flutter_svg 的 asset 缓存已足够，~600 个 SVG 全量随 bundle 加载，无性能问题。

## 测试策略

- **单元测试** `client/test/utils/file_icon_test.dart`:
  - 扩展名命中（`a.dart` → `dart`）
  - 文件名优先于扩展名（`pubspec.yaml` → `dart` 而非 `yaml`；`README.md` → `readme` 而非 `markdown`）
  - 未知类型回退默认（`a.xyzunknown` → `file`）
  - light 标记正确（`Theme.brightness` 为 light 时切 `_light` 文件名）
- **脚本幂等性**: 输出固定，不依赖环境顺序。
- **资产完整性**: 脚本内置断言，生成代码与 SVG 资产一一对应。
- **手动验证（记入 README）**: 启动应用，打开含多种文件类型的项目，目视确认图标形状/颜色正确。

## 文件清单

新增：
- `tools/sync_material_icons.dart`
- `client/assets/file_icons/*.svg`（~600-800 个，脚本生成）
- `client/lib/utils/file_icon_mapping.g.dart`（脚本生成）
- `client/lib/widgets/file_icon_widget.dart`
- `client/test/utils/file_icon_test.dart`

修改：
- `client/lib/utils/file_icon.dart` — 返回 `FileIconInfo`
- `client/lib/widgets/file_tree_node.dart` — 用 `FileIconWidget`
- `client/lib/widgets/file_editor/file_editor_tab.dart` — 用 `FileIconWidget`
- `client/pubspec.yaml` — 声明 `assets/file_icons/` 目录
- `docs/DEVELOPMENT.md` — 记录 `dart run tools/sync_material_icons.dart` 命令
- `README.md` / `README.zh.md` — credits 致谢 VSCode Material Icon Theme (MIT)

## 许可证

material-icon-theme 为 MIT 协议。项目仓库已有 LICENSE（需确认协议一致性），在 README 添加 credits 行致谢。
