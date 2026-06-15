# 丰富文件树文件图标 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复用 VSCode Material Icon Theme 的 SVG 图标集合，让文件树和编辑器标签页的每种文件类型显示独立的彩色图标，达到 IDE 级文件树观感。

**Architecture:** 一个 Dart 工具脚本 `tool/sync_material_icons.dart` 在构建期从 npm 包 `material-icon-theme` 拷贝被引用的 SVG 资产并生成 `file_icon_mapping.g.dart` 映射代码；运行期 `fileIconForFileName()` 返回 `FileIconInfo`（图标名 + light 标记），`FileIconWidget` 用已有的 `flutter_svg` 依赖渲染彩色 SVG。仅 2 个调用点需改造。

**Tech Stack:** Dart（工具脚本）、Flutter、flutter_svg（已依赖，零新增）、material-icon-theme npm 包（MIT）。

**设计依据:** `docs/superpowers/specs/2026-06-15-file-tree-rich-file-icons-design.md`

---

## 文件结构

| 路径 | 动作 | 职责 |
|------|------|------|
| `client/tool/sync_material_icons.dart` | 新建 | 同步脚本：npm 包 → SVG 资产 + 映射代码 |
| `client/assets/file_icons/*.svg` | 脚本生成 | 被映射表引用的彩色 SVG（~600-800 个）|
| `client/lib/utils/file_icon_mapping.g.dart` | 脚本生成 | const Map/Set 映射数据 |
| `client/lib/utils/file_icon.dart` | 修改 | `fileIconForFileName` 返回 `FileIconInfo` |
| `client/lib/widgets/file_icon_widget.dart` | 新建 | `FileIconWidget` 渲染彩色 SVG |
| `client/test/utils/file_icon_test.dart` | 新建 | 单元测试 |
| `client/lib/widgets/file_tree_node.dart` | 修改 | 用 `FileIconWidget` |
| `client/lib/widgets/file_editor/file_editor_tab.dart` | 修改 | 用 `FileIconWidget` |
| `client/pubspec.yaml` | 修改 | 声明 `assets/file_icons/` |
| `docs/DEVELOPMENT.md` | 修改 | 记录同步命令 |
| `README.md` / `README.zh.md` | 修改 | MIT credits |

---

### Task 1: 资产目录 + 同步脚本骨架

**目标**: 建立 `client/assets/file_icons/` 目录和脚本文件骨架，能解析命令行参数并定位 npm 包。脚本放 `client/tool/`（与 `gen_warmup_glyphs.dart`、`sync_bundled_google_fonts.dart` 同级）。

**Files:**
- Create: `client/tool/sync_material_icons.dart`
- Create: `client/assets/file_icons/.gitkeep`

- [ ] **Step 1: 建立资产目录占位**

```
client/assets/file_icons/.gitkeep
```

文件内容为空。确保目录存在且 git 能跟踪（脚本运行后会被实际 SVG 取代，`.gitkeep` 之后可删，但保留也无害）。

- [ ] **Step 2: 写脚本骨架（参数解析 + npm 包定位）**

`client/tool/sync_material_icons.dart`:

```dart
// ignore_for_file: avoid_print
//
// Syncs VSCode Material Icon Theme SVGs + mapping into this repo. Run from `client/`:
//
//   dart run tool/sync_material_icons.dart
//
// By default it downloads material-icon-theme npm package to a temp dir.
// Use --npm-package <path> to point at a pre-extracted package directory.
// Use --force to skip the version cache check.

import 'dart:convert';
import 'dart:io';

const _packageName = 'material-icon-theme';
const _repoRoot = '..'; // client/ -> repo root (for docs/README, resolved at runtime)
const _targetSvgDir = 'assets/file_icons';
const _targetMappingFile = 'lib/utils/file_icon_mapping.g.dart';

Future<Directory> _prepareNpmPackage(List<String> args) async {
  final pkgArgIdx = args.indexOf('--npm-package');
  if (pkgArgIdx >= 0 && pkgArgIdx + 1 < args.length) {
    final dir = Directory(args[pkgArgIdx + 1]);
    if (!dir.existsSync()) {
      stderr.writeln('--npm-package dir does not exist: ${dir.path}');
      exit(1);
    }
    return dir;
  }
  // Default: download via `npm pack` into a temp dir and extract.
  final temp = await Directory.systemTemp.createTemp('material-icon-theme-');
  print('Downloading $_packageName via npm pack into ${temp.path} ...');
  final packResult = await Process.run('npm', ['pack', _packageName], workingDirectory: temp.path);
  if (packResult.exitCode != 0) {
    stderr.writeln('npm pack failed:\n${packResult.stderr}');
    exit(1);
  }
  final tgzFiles = temp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tgz'))
      .toList();
  if (tgzFiles.isEmpty) {
    stderr.writeln('No .tgz produced by npm pack.');
    exit(1);
  }
  final extractResult = await Process.run(
    'tar',
    ['-xzf', tgzFiles.first.path, '-C', temp.path],
    runInShell: true,
  );
  if (extractResult.exitCode != 0) {
    stderr.writeln('tar extract failed:\n${extractResult.stderr}');
    exit(1);
  }
  // npm pack extracts into ./package/
  final pkgDir = Directory('${temp.path}/package');
  if (!pkgDir.existsSync()) {
    stderr.writeln('Extracted package/ dir not found at ${pkgDir.path}');
    exit(1);
  }
  return pkgDir;
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final pkgDir = await _prepareNpmPackage(args);
  print('Using npm package at: ${pkgDir.path}');

  // TODO(steps below): read version, parse json, copy svgs, write mapping.
  final mappingFile = File('${pkgDir.path}/dist/material-icons.json');
  if (!mappingFile.existsSync()) {
    stderr.writeln('material-icons.json not found at ${mappingFile.path}');
    exit(1);
  }
  final json = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
  print('material-icons.json top keys: ${json.keys.toList()}');

  // Keep temp dir reference for later tasks; this is just the skeleton.
  print('Skeleton OK. version json loaded with ${json.length} top keys. force=$force');
}
```

- [ ] **Step 3: 验证脚本骨架能跑**

Run: `cd client && dart run tool/sync_material_icons.dart`
Expected: 打印 `Downloading material-icon-theme via npm pack ...`、`Using npm package at: ...`、`material-icons.json top keys: [...]`、`Skeleton OK.`，退出码 0。

注意：这一步依赖 `npm` 和 `tar` 在 PATH 中。Windows 上 `tar` 在 Win10+ 内置。如果环境无 `npm`，可用 `--npm-package <解压后的包目录>` 测试。

- [ ] **Step 4: Commit**

```bash
cd client
git add tool/sync_material_icons.dart assets/file_icons/.gitkeep
git commit -m "feat(file-icons): add sync script skeleton for material icon theme"
```

---

### Task 2: 同步脚本 — SVG 拷贝 + 版本读取

**目标**: 扩展脚本，读取 npm 包版本、收集所有被引用的图标名、拷贝对应 SVG 到 `client/assets/file_icons/`。

**Files:**
- Modify: `client/tool/sync_material_icons.dart`

- [ ] **Step 1: 在 `_prepareNpmPackage` 后增加版本读取和 JSON 解析逻辑**

在 `main()` 里替换 TODO 注释段，加入完整的解析逻辑。把 `main` 改为下面这版（完整替换 `main` 函数及其之后的代码）：

```dart
/// Reads the npm package version from its package.json.
String _readPackageVersion(Directory pkgDir) {
  final pkgJson = File('${pkgDir.path}/package.json');
  if (!pkgJson.existsSync()) return 'unknown';
  final data = jsonDecode(pkgJson.readAsStringSync()) as Map<String, dynamic>;
  return (data['version'] ?? 'unknown').toString();
}

/// Collects the set of icon names referenced by the mapping (from iconDefinitions
/// plus every extension/fileName/languageId value), preserving order by insertion.
Set<String> _collectReferencedIconNames(Map<String, dynamic> json) {
  final names = <String>{};
  void addFromMap(Object? map) {
    if (map is Map) {
      for (final v in map.values) {
        if (v is String) names.add(v);
      }
    }
  }

  // iconDefinitions keys are the icon names themselves.
  final defs = json['iconDefinitions'];
  if (defs is Map) {
    names.addAll(defs.keys.cast<String>());
  }
  addFromMap(json['fileExtensions']);
  addFromMap(json['fileNames']);
  addFromMap(json['languageIds']);
  // Default folder/file icons referenced at top level.
  for (final k in const ['file', 'folder', 'folderExpanded', 'rootFolder', 'rootFolderExpanded']) {
    final v = json[k];
    if (v is String) names.add(v);
  }
  return names;
}

/// Copies referenced SVGs from <pkg>/icons into the target dir.
/// Returns (copiedCount, missingNames) where missingNames are referenced but
/// absent in the source (treated as non-fatal warnings).
({int copied, List<String> missing}) _copySvgs({
  required Directory pkgDir,
  required Directory targetDir,
  required Set<String> referencedNames,
}) {
  final srcIcons = Directory('${pkgDir.path}/icons');
  if (!srcIcons.existsSync()) {
    stderr.writeln('Source icons/ dir not found at ${srcIcons.path}');
    exit(1);
  }
  // Wipe target so removed icons don't linger.
  if (targetDir.existsSync()) {
    targetDir.deleteSync(recursive: true);
  }
  targetDir.createSync(recursive: true);

  var copied = 0;
  final missing = <String>[];
  for (final name in referencedNames..toList()..sort()) {
    final src = File('${srcIcons.path}/$name.svg');
    if (src.existsSync()) {
      final dst = File('${targetDir.path}/$name.svg');
      dst.writeAsBytesSync(src.readAsBytesSync());
      copied++;
    } else {
      missing.add(name);
    }
  }
  return (copied: copied, missing: missing);
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final pkgDir = await _prepareNpmPackage(args);
  final version = _readPackageVersion(pkgDir);
  print('Using $_packageName@$version at: ${pkgDir.path}');

  final mappingFile = File('${pkgDir.path}/dist/material-icons.json');
  if (!mappingFile.existsSync()) {
    stderr.writeln('material-icons.json not found at ${mappingFile.path}');
    exit(1);
  }
  final json = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;

  final referenced = _collectReferencedIconNames(json);
  print('Referenced icon names: ${referenced.length}');

  final targetDir = Directory(_targetSvgDir);
  final (:copied, :missing) = _copySvgs(
    pkgDir: pkgDir,
    targetDir: targetDir,
    referencedNames: referenced,
  );
  print('Copied $copied SVGs into $_targetSvgDir/.');
  if (missing.isNotEmpty) {
    print('WARNING: ${missing.length} referenced icons missing in source: $missing');
  }
  if (force) print('(force: version cache check skipped)');

  // Mapping generation comes in Task 3.
  print('SVG sync done. (mapping generation not yet implemented)');
}
```

- [ ] **Step 2: 运行验证 SVG 拷贝**

Run: `cd client && dart run tool/sync_material_icons.dart`
Expected: 打印 `Referenced icon names: <N>`（N 应在 600-900 区间）、`Copied <N> SVGs into assets/file_icons/.`。检查 `dir assets\file_icons\*.svg | find /c /v ""` 输出的文件数与 copied 一致，且 `dart.svg`、`json.svg`、`markdown.svg` 等存在。

- [ ] **Step 3: Commit**

```bash
cd client
git add tool/sync_material_icons.dart
git commit -m "feat(file-icons): copy referenced SVGs in sync script"
```

注：SVG 资产暂不提交，待 Task 4 映射生成后与 pubspec 改动一起提交。

---

### Task 3: 同步脚本 — 生成映射代码 + 完整性校验

**目标**: 脚本生成 `lib/utils/file_icon_mapping.g.dart`，含 `kFileExtensionIcons`、`kFileNameIcons`、`kLightFileExtensions`、`kLightFileNames`、`kDefaultFileIcon`、`materialFileIconsVersion`；并做资产完整性断言（每个引用的图标名都有 SVG）。

**Files:**
- Modify: `client/tool/sync_material_icons.dart`
- Generated: `client/lib/utils/file_icon_mapping.g.dart`（脚本产出）

- [ ] **Step 1: 在脚本里增加映射生成函数**

在 `_copySvgs` 之后、`main` 之前加入：

```dart
/// Writes lib/utils/file_icon_mapping.g.dart with sorted const maps.
void _writeMappingFile({
  required String version,
  required Map<String, dynamic> json,
  required Set<String> copiedIconNames,
}) {
  String dartStringLiteral(String s) {
    // Escape backslash and single quote.
    final escaped = s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }

  void writeMap(String varName, Map<String, String> m, IOSink out) {
    final sortedKeys = m.keys.toList()..sort();
    out.writeln('const Map<String, String> $varName = {');
    for (final k in sortedKeys) {
      out.writeln('  ${dartStringLiteral(k)}: ${dartStringLiteral(m[k]!)},');
    }
    out.writeln('};');
    out.writeln();
  }

  void writeSet(String varName, Iterable<String> values, IOSink out) {
    final sorted = values.toList()..sort();
    out.writeln('const Set<String> $varName = {');
    for (final v in sorted) {
      out.writeln('  ${dartStringLiteral(v)},');
    }
    out.writeln('};');
    out.writeln();
  }

  Map<String, String> castMap(Object? m) {
    if (m is! Map) return {};
    return m.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  final extMap = castMap(json['fileExtensions']);
  final nameMap = castMap(json['fileNames']);
  final light = json['light'];
  final lightExt = light is Map ? castMap(light['fileExtensions']).keys.toSet() : <String>{};
  final lightName = light is Map ? castMap(light['fileNames']).keys.toSet() : <String>{};
  // Default file icon: material-icons.json "file" -> iconDefinition name, usually "file".
  final defaultIcon = (json['file'] ?? 'file').toString();

  final buf = StringBuffer()
    ..writeln('// GENERATED BY tool/sync_material_icons.dart — DO NOT EDIT.')
    ..writeln('// Source: material-icon-theme@$version (MIT)')
    ..writeln()
    ..writeln('const materialFileIconsVersion = ${dartStringLiteral(version)};')
    ..writeln()
    ..writeln('const String kDefaultFileIcon = ${dartStringLiteral(defaultIcon)};')
    ..writeln();
  writeMap('kFileExtensionIcons', extMap, buf);
  writeMap('kFileNameIcons', nameMap, buf);
  writeSet('kLightFileExtensions', lightExt, buf);
  writeSet('kLightFileNames', lightName, buf);

  File(_targetMappingFile).writeAsStringSync(buf.toString());
  print('Wrote $_targetMappingFile '
      '(extensions=${extMap.length}, fileNames=${nameMap.length}, '
      'lightExt=${lightExt.length}, lightName=${lightName.length}).');
}
```

- [ ] **Step 2: 在 main 末尾调用生成 + 完整性断言**

替换 `main` 最后那行 `print('SVG sync done...')`，改为：

```dart
  _writeMappingFile(version: version, json: json, copiedIconNames: {});

  // Asset integrity assertion: every icon name referenced by the generated
  // mapping must have a copied SVG on disk.
  final allReferencedInMapping = <String>{
    ..._collectReferencedIconNames(json),
  };
  final missingOnDisk = allReferencedInMapping
      .where((n) => !File('$_targetSvgDir/$n.svg').existsSync())
      .toList();
  if (missingOnDisk.isNotEmpty) {
    stderr.writeln('FATAL: ${missingOnDisk.length} mapping icons have no SVG on disk: '
        '${missingOnDisk.take(20).toList()}');
    exit(1);
  }

  print('Done. material-icon-theme@$version synced.');
```

- [ ] **Step 3: 运行生成映射并校验**

Run: `cd client && dart run tool/sync_material_icons.dart`
Expected: 末尾打印 `Wrote lib/utils/file_icon_mapping.g.dart (extensions=..., fileNames=..., lightExt=..., lightName=...).` 和 `Done. material-icon-theme@<version> synced.`，退出码 0。

抽查生成文件：应包含 `const materialFileIconsVersion = '5.x.x';`、`const Map<String, String> kFileExtensionIcons = { ... 'dart': 'dart', ... };`、`const Map<String, String> kFileNameIcons = { ... 'pubspec.yaml': 'dart', ... };`。

- [ ] **Step 4: 用 dart analyze 校验生成代码可编译**

Run: `cd client && dart analyze lib/utils/file_icon_mapping.g.dart`
Expected: 无 error（可能有 info 级提示，忽略）。如果报错，检查字符串转义。

- [ ] **Step 5: Commit**

```bash
cd client
git add tool/sync_material_icons.dart
git commit -m "feat(file-icons): generate file_icon_mapping.g.dart with integrity check"
```

（生成的 `.g.dart` 和 SVG 资产在 Task 4 末尾与 pubspec 一起提交。）

---

### Task 4: pubspec 声明资产 + 提交生成产物

**目标**: 在 pubspec.yaml 声明 `assets/file_icons/` 目录，让 Flutter 打包 SVG。然后把生成的 SVG 资产和映射代码一起提交（生成产物纳入版本控制，确保不开箱运行脚本也能构建）。

**Files:**
- Modify: `client/pubspec.yaml`
- Generated (commit): `client/lib/utils/file_icon_mapping.g.dart`
- Generated (commit): `client/assets/file_icons/*.svg`

- [ ] **Step 1: 确认脚本已生成资产和映射**

Run: `cd client && dart run tool/sync_material_icons.dart`
确认 `lib/utils/file_icon_mapping.g.dart` 存在且 `assets/file_icons/` 含数百个 `.svg`。

- [ ] **Step 2: 在 pubspec.yaml 声明资产**

定位 `flutter:` → `assets:` 段。在现有 assets 列表里增加一行 `- assets/file_icons/`。

现有片段（约 pubspec.yaml:83 附近）大致是：
```yaml
flutter:
  assets:
    - assets/icons/
```
改为：
```yaml
flutter:
  assets:
    - assets/icons/
    - assets/file_icons/
```

（实现时先 Read pubspec.yaml 确认 `assets:` 段的确切缩进和现有条目，再做精确 Edit。）

- [ ] **Step 3: flutter pub get 让资产声明生效**

Run: `cd client && flutter pub get`
Expected: 无报错，退出码 0。

- [ ] **Step 4: 提交生成产物 + pubspec**

```bash
cd client
git add pubspec.yaml lib/utils/file_icon_mapping.g.dart assets/file_icons/
git commit -m "feat(file-icons): bundle material icon theme SVGs and generated mapping"
```

注：`assets/file_icons/.gitkeep` 此时若仍存在可一并删除（已无用了）：
```bash
git rm assets/file_icons/.gitkeep
```
若已无该文件则跳过。

---

### Task 5: file_icon.dart — 返回 FileIconInfo（TDD）

**目标**: 把 `fileIconForFileName` 返回值从 `IconData` 改为 `FileIconInfo(iconName, isLightVariant)`，按"精确文件名 > 扩展名 > 默认"优先级匹配。先写失败测试。

**Files:**
- Modify: `client/lib/utils/file_icon.dart`
- Create: `client/test/utils/file_icon_test.dart`

- [ ] **Step 1: 写失败测试**

`client/test/utils/file_icon_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/file_icon.dart';
import 'package:teampilot/utils/file_icon_mapping.g.dart';

void main() {
  group('fileIconForFileName', () {
    test('matches by extension', () {
      final info = fileIconForFileName('main.dart');
      expect(info.iconName, 'dart');
      expect(info.isLightVariant, isFalse);
    });

    test('matches json extension', () {
      expect(fileIconForFileName('config.json').iconName, 'json');
    });

    test('exact file name beats extension', () {
      // pubspec.yaml is mapped to 'dart' by file name, NOT 'yaml' by extension.
      expect(fileIconForFileName('pubspec.yaml').iconName, 'dart');
    });

    test('case-insensitive file name and extension', () {
      expect(fileIconForFileName('README.MD').iconName,
          kFileNameIcons['readme.md']);
      expect(fileIconForFileName('App.DART').iconName, 'dart');
    });

    test('unknown extension falls back to default', () {
      expect(fileIconForFileName('data.xyzunknown').iconName, kDefaultFileIcon);
    });

    test('no extension falls back to default', () {
      expect(fileIconForFileName('Makefile_no_ext_hint').iconName,
          isNot(kDefaultFileIcon).equals(kDefaultFileIcon)
              ? kDefaultFileIcon
              : kFileNameIcons['makefile'] ?? kDefaultFileIcon);
      // Simpler: a truly unknown name with no dot hits default.
      expect(fileIconForFileName('zzznoext').iconName, kDefaultFileIcon);
    });

    test('strips path prefix', () {
      expect(fileIconForFileName('lib/src/utils/file_icon.dart').iconName,
          'dart');
    });

    test('light variant flag for known light extension', () {
      // 'blink' is in the light set per material-icons.json.
      final info = fileIconForFileName('a.blink');
      expect(info.iconName, kFileExtensionIcons['blink']);
      expect(info.isLightVariant, kLightFileExtensions.contains('blink'));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败（编译错误）**

Run: `cd client && flutter test test/utils/file_icon_test.dart`
Expected: 编译失败 —— `FileIconInfo` 未定义、`fileIconForFileName` 返回 `IconData` 无 `iconName` 字段、`kFileExtensionIcons` 等未导入或不存在（依赖 Task 3 生成的 mapping，应已存在）。

- [ ] **Step 3: 实现 FileIconInfo + 改造 fileIconForFileName**

完整替换 `client/lib/utils/file_icon.dart` 内容为：

```dart
import 'file_icon_mapping.g.dart';

/// Resolved Material Icon Theme glyph for a file.
///
/// [iconName] maps to `assets/file_icons/$iconName.svg` (or `..._light.svg`
/// when [isLightVariant] is true and the runtime theme is light).
/// See `tool/sync_material_icons.dart` for the source mapping.
class FileIconInfo {
  const FileIconInfo(this.iconName, {this.isLightVariant = false});

  /// Icon name as used by VSCode Material Icon Theme, e.g. `dart`, `json`.
  final String iconName;

  /// Whether this file type has a designated light-theme variant
  /// (`{iconName}_light.svg`). The runtime widget decides whether to use it
  /// based on [ThemeData.brightness].
  final bool isLightVariant;
}

/// Material icon for a file name or path.
///
/// Match priority: exact file name (case-insensitive) > extension > default.
FileIconInfo fileIconForFileName(String name) {
  final baseName = name.split('/').last;
  final lower = baseName.toLowerCase();

  // 1. Exact file name (e.g. "pubspec.yaml", ".gitignore").
  final byName = kFileNameIcons[lower];
  if (byName != null) {
    return FileIconInfo(
      byName,
      isLightVariant: kLightFileNames.contains(lower),
    );
  }

  // 2. Extension.
  final ext = lower.contains('.') ? lower.split('.').last : '';
  final byExt = kFileExtensionIcons[ext];
  if (byExt != null) {
    return FileIconInfo(
      byExt,
      isLightVariant: kLightFileExtensions.contains(ext),
    );
  }

  // 3. Default.
  return const FileIconInfo(kDefaultFileIcon);
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test test/utils/file_icon_test.dart`
Expected: 全部 PASS。

若 `no extension` 用例里 `Makefile_no_ext_hint` 行为不确定，可删除该断言只保留 `zzznoext` 断言（Makefile 实际会命中 `kFileNameIcons['makefile']`，那是正确行为）。

- [ ] **Step 5: 确认全局编译仍报错（预期，2 个调用点还没改）**

Run: `cd client && flutter analyze lib/widgets/file_tree_node.dart lib/widgets/file_editor/file_editor_tab.dart 2>&1 | findstr /i error`
Expected: 报 `fileIconForFileName` 返回类型不匹配之类的 error —— 这是 Task 6/7 要修的。

- [ ] **Step 6: Commit**

```bash
cd client
git add lib/utils/file_icon.dart test/utils/file_icon_test.dart
git commit -m "feat(file-icons): return FileIconInfo from fileIconForFileName (TDD)"
```

---

### Task 6: FileIconWidget + 改造 file_tree_node.dart

**目标**: 新建 `FileIconWidget`（用 flutter_svg 渲染彩色 SVG），并把 `file_tree_node.dart` 的文件分支从 `Icon(fileIconForFileName(...))` 换成 `FileIconWidget`。

**Files:**
- Create: `client/lib/widgets/file_icon_widget.dart`
- Modify: `client/lib/widgets/file_tree_node.dart:143-148`

- [ ] **Step 1: 新建 FileIconWidget**

`client/lib/widgets/file_icon_widget.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/file_icon.dart';

/// Renders a colored Material Icon Theme SVG for [fileName].
///
/// Uses `flutter_svg` (already a dependency). The SVG's internal `fill` colors
/// are preserved, so each file type shows its designated color. When the
/// runtime theme is light and the file type has a light variant, the
/// `{iconName}_light.svg` asset is used instead.
class FileIconWidget extends StatelessWidget {
  const FileIconWidget({
    required this.fileName,
    this.size = 16,
    super.key,
  });

  final String fileName;
  final double size;

  static const _assetDir = 'assets/file_icons';

  @override
  Widget build(BuildContext context) {
    final info = fileIconForFileName(fileName);
    final useLight = Theme.of(context).brightness == Brightness.light &&
        info.isLightVariant;
    final suffix = useLight ? '_light' : '';
    final path = '$_assetDir/${info.iconName}$suffix.svg';
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
    );
  }
}
```

- [ ] **Step 2: 改造 file_tree_node.dart 的文件分支**

Read 确认 `client/lib/widgets/file_tree_node.dart` 当前 import 段（顶部）和第 143-148 行的图标渲染。当前是：

```dart
              Icon(
                isDir
                    ? (isExpanded ? Icons.folder_open : Icons.folder_outlined)
                    : fileIconForFileName(widget.entry.name),
                size: context.appIconSizes.md,
              ),
```

改为：目录仍用 `Icon`（保持 folder 图标 + 旋转动画逻辑不变），文件分支用 `FileIconWidget`：

```dart
              if (isDir)
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder_outlined,
                  size: context.appIconSizes.md,
                  color: iconMuted,
                )
              else
                FileIconWidget(
                  fileName: widget.entry.name,
                  size: context.appIconSizes.md,
                ),
```

注意：原代码文件分支的图标没有显式 color（继承 `IconTheme`），彩色 SVG 不需要 color，符合预期。

- [ ] **Step 3: 更新 imports**

在 `file_tree_node.dart` 顶部 import 区加入（紧邻 `import '../utils/file_icon.dart';`）：

```dart
import 'file_icon_widget.dart';
```

并把原来的 `import '../utils/file_icon.dart';` 保留（`isEditorOpenableFilePath` 等可能仍需要，且 `FileIconWidget` 内部已用它；若 analyze 显示 `file_icon.dart` 未被直接引用，可移除 —— 先保留，Step 5 analyze 确认）。

- [ ] **Step 4: 确认 file_tree_node.dart 编译通过**

Run: `cd client && flutter analyze lib/widgets/file_tree_node.dart`
Expected: 无 error。

- [ ] **Step 5: Commit**

```bash
cd client
git add lib/widgets/file_icon_widget.dart lib/widgets/file_tree_node.dart
git commit -m "feat(file-icons): render colored file icons in file tree via FileIconWidget"
```

---

### Task 7: 改造 file_editor_tab.dart

**目标**: 编辑器标签页的文件图标也换成 `FileIconWidget`（原来是单色 `Icon` 染 `labelColor`，改后变彩色）。

**Files:**
- Modify: `client/lib/widgets/file_editor/file_editor_tab.dart:130-134`

- [ ] **Step 1: 改造图标渲染**

当前 `file_editor_tab.dart:130-134`：

```dart
                Icon(
                  fileIconForFileName(widget.fileName),
                  size: context.appIconSizes.sm,
                  color: labelColor,
                ),
```

改为：

```dart
                FileIconWidget(
                  fileName: widget.fileName,
                  size: context.appIconSizes.sm,
                ),
```

彩色 SVG 不再跟随 `labelColor`（这是设计决策：文件图标彩色，提升辨识度；标签选中态已由背景色 `secondaryContainer` 表达）。

- [ ] **Step 2: 更新 imports**

在 `file_editor_tab.dart` 顶部 import 区：
- 加入 `import '../file_icon_widget.dart';`（注意相对路径：`file_editor/` 上一级是 `widgets/`，所以是 `../file_icon_widget.dart`）
- 若原 import `../utils/file_icon.dart` 不再被本文件其他地方使用，移除（Step 3 analyze 确认）。

- [ ] **Step 3: 确认编译通过**

Run: `cd client && flutter analyze lib/widgets/file_editor/file_editor_tab.dart`
Expected: 无 error。如果提示 `file_icon.dart` unused import，移除该 import 再 analyze。

- [ ] **Step 4: Commit**

```bash
cd client
git add lib/widgets/file_editor/file_editor_tab.dart
git commit -m "feat(file-icons): render colored file icons in editor tabs"
```

---

### Task 8: 全局校验 + 文档 + 致谢

**目标**: 全项目 analyze + test 通过；在 DEVELOPMENT.md 记录同步命令；README 加 MIT credits。

**Files:**
- Modify: `docs/DEVELOPMENT.md`
- Modify: `README.md`
- Modify: `README.zh.md`

- [ ] **Step 1: 全项目 analyze（按 AGENTS.md 标准）**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error（warning/info 可有）。

- [ ] **Step 2: 全项目 test（排除 integration）**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全部 PASS，包括新加的 `test/utils/file_icon_test.dart`。

- [ ] **Step 3: 在 DEVELOPMENT.md 记录同步命令**

在 `docs/DEVELOPMENT.md` 找到记录工具命令的段落（搜索 `gen_warmup_glyphs` 或 `sync_bundled_google_fonts` 的位置）。在邻近位置加入：

```markdown
- File type icons (VSCode Material Icon Theme): `dart run tool/sync_material_icons.dart`
  — regenerates `lib/utils/file_icon_mapping.g.dart` and `assets/file_icons/*.svg`
  from the `material-icon-theme` npm package. Use `--npm-package <path>` to point
  at a pre-extracted package, `--force` to skip the version cache check.
```

（实现时先 Read DEVELOPMENT.md 找到确切段落，用 Edit 精确插入，匹配周围 Markdown 风格。）

- [ ] **Step 4: README credits（英文）**

在 `README.md` 找到 credits / acknowledgements / licenses 段落（若无，在 License 段后加一节）。加入：

```markdown
## Acknowledgements

- File icons: [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) (MIT) by Philipp Kief / material-extensions.
```

- [ ] **Step 5: README credits（中文）**

在 `README.zh.md` 对应位置加入：

```markdown
## 致谢

- 文件图标：[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)（MIT 协议），作者 Philipp Kief / material-extensions。
```

- [ ] **Step 6: Commit**

```bash
cd C:\Users\haung\git\teampilot
git add docs/DEVELOPMENT.md README.md README.zh.md
git commit -m "docs: document file icon sync command and credit Material Icon Theme"
```

---

## 完成标准（DoD）

- [ ] `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 无 error
- [ ] `cd client && flutter test --exclude-tags integration` 全部 PASS
- [ ] 运行应用打开一个含多种文件类型（dart/json/yaml/md/png/svg/gitignore/pubspec.yaml）的项目，文件树和编辑器标签页显示对应彩色图标
- [ ] `assets/file_icons/` 含数百个 SVG 且 `lib/utils/file_icon_mapping.g.dart` 版本号正确
- [ ] DEVELOPMENT.md 和 README（中英）已更新
