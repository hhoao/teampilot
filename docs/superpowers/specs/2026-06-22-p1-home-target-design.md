# 远程执行架构 · P1 设计稿（home target 归一 + 权威源反转 + "选 target" UI）

> 状态：**已澄清待实现** · **最优终态、零向后兼容**（用户 2026-06-22 全局准则）· 建立在分支 `feat/p0-runtime-target` 之上
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §4 home target、§5 控制面、§11 控制面在远端、§12 P1 行
> 决策来源：2026-06-22 用户全局准则（经 team-lead 转达）+ P1 Q1–Q6

## 0. 全局准则（本期及后续一律遵守）

**不做向下/向后兼容、不考虑工作量、直接最优架构。** 具体：
- targets/`homeTargetId` 即唯一权威源；**砍掉** P0 遗留的"live prefs 权威 + targets.json 镜像"过渡态，**无双写窗口、无 schemaVersion 兼容、无"读旧字段"迁移**。
- 数据模型直接是**干净终态形状**；旧磁盘 manifest/prefs 将无法被新版读取——**用户明确接受**。
- **P1 顺带清除前序阶段加的全部兼容脚手架**（见 §6），使"四旋钮/旧字段彻底消失、target 为唯一真相源"。

## 1. 目标

| 子目标 | 内容 |
|---|---|
| **home target 归一** | 明确"home target = App 自身所在机"为**唯一作用域层**：桌面 home 由平台定为 `local`；Android home = 某个 `ssh:*`。`app_shell` 的 install/reinstall/reloadRemoteBackedAppData 围绕 **home target** 装配，不再读四旋钮遗留字段。 |
| **权威源反转（直接到位）** | 用户对 home 的选择 = **设备本地持久化的 `homeTargetId`**（唯一权威）；删除"由 connectionMode/windowsStorageBackend/selectedProfile 推导 target"的 P0 遗留逻辑。 |
| **UI 升级** | 把"连接模式开关 + Windows 后端开关 + SSH profile 选择"升级为**平台域定的"选 home target"选择器**。 |
| **清除兼容脚手架** | 移除预备阶段双写/`foldersFromLegacyJson`、P0 的 `migrateIfNeeded`/`currentLegacyTargetId`/`synthTarget`、`SessionPreferences.connectionMode`/`windowsStorageBackend` 等（§6）。 |

**明确不在 P1**：去存储单例（P2）、控制面/工作面拆分（P2）、`Workspace.folders[].targetId` 多机解析（P2）、反向隧道/成员远程（P3）、`remoteOs` 探测（P3）、桌面"整体远程/home 搬到 ssh"（§12 明确暂不做——桌面 home 恒 local）。

## 2. 核心架构决策

### 2.1 ⚠️ home target 身份是**设备本地 bootstrap 事实**（请 team-lead 确认/否决）

团队转达的准则 #1 字面为"`targets.json/defaultTargetId` 即唯一权威源"。**但 home target 的身份在最优架构下也无法只存控制面**，原因是架构约束（非兼容）：

- `targets.json` 落在**控制面 = home 机器**。桌面 home=local → 本地可读；**Android home=ssh → targets.json 在远程**。
- 要连远程 home 必须**先知道是哪个 ssh**（即 home 选择）。若 home 选择只存远程 targets.json → **自指循环，无法 bootstrap**。

**最优解（推荐，已据此设计）**：把"home 选择"与"target 目录"分成两个**职责不同**的事实：

| 事实 | 存哪 | 何时可读 | 权威于 |
|---|---|---|---|
| `homeTargetId`（home 选择） | **设备本地**（SharedPrefs，`HomeTargetStore`） | bootstrap 最早期，**任何存储 install 之前** | 控制面在哪台机 |
| targets 目录（list + label） | 控制面 `targets.json`（home 上） | home 存储 install **之后** | 可用 target 清单（P2 工作面复用） |

这不是兼容妥协，而是"控制面永远在 home"（§5）的必然推论——**home 的身份不能存在 home 之上**。`homeTargetId` 是 bootstrap 输入；`targets.json` 是 home 上的目录。SSH 连接凭证已在设备本地 `SecureSshCredentialStore`（与此自洽）。

> 若团队坚持"只用 targets.json/defaultTargetId、无本地 homeTargetId"，则 **Android(home=ssh) 不可 bootstrap**——这是 §12 P1 验收点"Android 等价归一"直接要求的能力。故本设计采用本地 `homeTargetId`。**请确认或否决此点**（其余设计不依赖该否决之外的选择）。

### 2.2 targets.json 终态形状（无 defaultTargetId、无迁移）

```json
{ "schemaVersion": 1, "targets": [ {"id":"ssh:<pid>","label":"prod","kind":"ssh","sshProfileId":"<pid>"} ] }
```

- 删除 P0 的 `defaultTargetId` 与 `wslDistro` 字段（home 选择移交本地 `homeTargetId`；wsl distro 编码进 `homeTargetId='wsl:<distro>'`，见 §2.3）。
- 删除 `RuntimeTargetRegistry.migrateIfNeeded`（无"读旧 prefs 播种"）。`listTargets` 的 ssh 对账（从 `ssh_profiles/` live 派生 ssh 目标）**保留**——这是 live 派生，非兼容。
- targets.json **首次** access 时若不存在 → 写空 `{schemaVersion:1, targets:[]}`（ssh 目标随后由 `listTargets` 对账补齐），不读任何旧源。

### 2.3 `homeTargetId` 与 `HomeTargetStore`（新增，设备本地）

```dart
// lib/services/storage/home_target_store.dart
class HomeTargetStore {
  HomeTargetStore(SharedPreferences prefs);
  static const _key = 'flashskyai.home_target.v1';
  String load();                 // '' 表示未设置 → 由 §3 默认规则定
  Future<void> save(String id);  // 'local' | 'wsl:<distro>' | 'ssh:<profileId>'
}
```

- 权威的 home 选择。UI"选 target"写它；bootstrap 读它。
- distro 编码进 id（`wsl:<distro>`），不再有独立 `windowsStorageBackend`/`wslDistro` 字段，也不再"解析 claude 路径"。

## 3. home target 解析（bootstrap 次序，解鸡生蛋）

```
1. 读设备本地 homeTargetId（HomeTargetStore）          // install 之前
   缺省默认：Android → 首个可用 ssh profile 的 'ssh:<id>'（无则进首启门，§4）
            桌面非 Windows → 'local'
            桌面 Windows → 'local'（用户可在选择器改 'wsl:<distro>'）
2. homeTarget = RuntimeTarget(homeTargetId)
   ssh kind 的连接凭证来自本地 SecureSshCredentialStore + ssh_profiles 目录
3. RuntimeStorageContext.installForTarget(homeTarget, sshProfile: <由 homeTargetId 解出>)
4. home 存储就绪 → 读 targets.json 目录（控制面，现可读）
5. UI/工作面后续用 registry.listTargets()（P2 起按目录用工作面 target）
```

- **不再两段式**靠 prefs：bootstrap 直接以 `homeTargetId` 解出的 home target 装一次（Android 即远程、桌面即 local/wsl）。`installForTarget` + `resolve()` 既有逻辑复用（resolve/单例 P1 仍不动，属 P2）。
- `defaultTargetResolver()` 改为返回**由 `homeTargetId` 解析的 home target**（缓存，UI 改选时刷新），删除 `currentLegacyTargetId()`/`synthTarget()` 的 prefs 推导。

## 4. UI：平台域定的"选 home target"选择器（Q4/Q5/Q6）

替换今天散落的三个控件（`session_config_section.dart` 的连接模式开关[已 `kShowConnectionModeSetting=false` 死代码] + Windows native/wsl 后端开关；`ssh_profiles_page.dart` 的选中单选 + `android_ssh_profile_selector.dart`）为**单一 home target 选择器**：

| 平台 | 可选 home | 控件 |
|---|---|---|
| 桌面非 Windows | 仅 `local` | 只读展示（无选项） |
| 桌面 Windows | `local` / `wsl:<distro>` | 选择器（**替换**后端开关） |
| Android | `ssh:<profile>…` | 选择器（**替换** ssh 选择 + quick-switch） |

- **位置**：就地放 `/config/session`（替换 Windows 后端开关那块）；Android quick-switch 改为 home target 切换。SSH profiles 页（`/config/ssh-profiles`）降为**纯管理**（增/删/改 profile），不再承载"选中"。
- 选择器项来自 `registry.listTargets()` 按平台过滤；选中 → `HomeTargetStore.save(id)` → `defaultTargetResolver` 刷新 → `reinstallStorageContext()` + `reloadRemoteBackedAppData`（沿用现有切换副作用链）。
- **移除死开关**：删除 `kShowConnectionModeSetting`/连接模式 SegmentedButton 整块（Q5）。
- **wsl distro（Q6）**：选择器 wsl 项用**已配置 distro**（编码于 `wsl:<distro>`）；**不**加 distro 发现/多 distro 选择 UI（YAGNI，留后续）。首版 Windows distro 取值来源见 §4.1。
- **Android 首启门（保留等价）**：home=ssh 但无 profile → 仍走"先建 profile"门（`requiresSshProfileSetup` 等价：无 home-ssh 可用即引导建 profile，建成自动设为 home）。

### 4.1 Windows distro 取值

P0 曾"解析 claude 路径"得 distro。P1 删除该隐式来源。Windows 上选择 `wsl` home 时的 distro：首版**沿用 `RuntimeStorageContext.parseWslDistro` 作为一次性建议默认**填入选择器（用户确认后写入 `homeTargetId='wsl:<distro>'`），此后纯由 `homeTargetId` 显式承载，运行时不再解析。（distro 发现 UI 属后续。）

## 5. 关键文件

| 文件 | 动作 | 职责 |
|------|------|------|
| `lib/services/storage/home_target_store.dart` | 新增 | 设备本地 `homeTargetId` 持久化 |
| `lib/services/storage/targets_repository.dart` | 改 | `TargetsRegistryFile` 去 `defaultTargetId`/`wslDistro`，仅 `{schemaVersion, targets}` |
| `lib/services/storage/runtime_target_registry.dart` | 改 | 删 `migrateIfNeeded`/`defaultTarget`/`setDefaultTargetId`/`wslDistro`；保留 `listTargets`（live 对账） |
| `lib/app/app_shell.dart` | 改 | bootstrap 读 `homeTargetId` → `installForTarget(homeTarget)`；删 `currentLegacyTargetId`/`synthTarget`/`migrateIfNeeded` 调用；install/reinstall/reload 围绕 home target |
| `lib/services/app/connection_mode_service.dart` | 改 | `isSshMode` 仍由 `defaultTargetResolver().kind` 推导（来源换 homeTargetId）；删 `effectiveMode`/`preferredMode`（`ConnectionMode` 不再外露） |
| `lib/models/session_preferences.dart` | 改 | **删除** `connectionMode`、`windowsStorageBackend` 字段及其 json | 
| `lib/cubits/session_preferences_cubit.dart` | 改 | 删 `setConnectionMode`/`setWindowsStorageBackend` |
| `lib/models/connection_mode.dart` / `windows_storage_backend.dart` | 改/删 | 若审计后无内部传输用途则整文件删除；否则降为内部传输描述符 |
| `lib/pages/config/session_config_section.dart` | 改 | 删后端开关 + 死连接模式开关；接入 home target 选择器 |
| `lib/pages/config/runtime_target_picker.dart` | 新增 | home target 选择器组件（平台域定） |
| `lib/pages/ssh_profiles_page.dart` | 改 | 降为纯管理（去"选中"单选） |
| `lib/widgets/android_ssh_profile_selector.dart` | 改 | 改为 home target 切换器 |
| `lib/services/storage/runtime_storage_context.dart` | 改 | 删 `installForTarget` 里对 `windowsStorageBackend` 旧入参的依赖（直接由 target.kind 决定）；`resolve()`/单例仍不动（P2） |

## 6. 兼容脚手架清除清单（纳入 P1）

**预备阶段**（`workspace_folder.dart`、`workspace.dart`、`app_session.dart`、`session_repository.dart` 等）：
- 删 `foldersFromLegacyJson` 的"读旧 primaryPath/additionalPaths"分支 → `folders` 唯一磁盘形状（`fromJson` 只读 `folders`）。
- 删 Workspace/AppSession `toJson` 的 `primaryPath`/`additionalPaths` 双写。
- 删 `@Deprecated primaryPath/additionalPaths` getter（若预备阶段 Task 8 已删则确认无残留）。
- 删 `WorkspacesIndex`/`AppSession` 的 schemaVersion 兼容读旧分支。

**P0 阶段**：
- 删 `RuntimeTargetRegistry.migrateIfNeeded` + `defaultTarget`/`setDefaultTargetId`/`wslDistro`（被 homeTargetId 取代）。
- 删 `app_shell` 的 `currentLegacyTargetId`/`synthTarget`/legacy install 块/`wslDistroFromPrefs`。
- 删 `SessionPreferences.connectionMode`/`windowsStorageBackend` 及 cubit setter；删 `ConnectionMode`/`WindowsStorageBackend` 用户旋钮（enum 视审计存废）。

**已知后果**（用户接受）：旧磁盘 manifest/prefs 不再可读；现有本地数据失效。

## 7. 测试策略（重点：Android 等价归一 + 桌面 home=local 回归）

1. **HomeTargetStore 单测**：save/load 往返；空默认。
2. **home target 解析单测**：`homeTargetId` → home `RuntimeTarget`（local/wsl:<d>/ssh:<pid>）；缺省默认按平台（注入 isAndroid/isWindows）。
3. **bootstrap 次序单测**：给定本地 `homeTargetId='ssh:p1'` + profile p1 → `installForTarget` 收到 ssh home target（Android 等价：等于今天选 p1 远程的结果——mode=ssh/appDataRoot 等价）。`homeTargetId='local'`（桌面）→ native。`'wsl:Ubuntu'`（Windows）→ wsl。
4. **targets.json 终态单测**：`{schemaVersion, targets}` 往返；无 `defaultTargetId`/`wslDistro`；缺文件 → 空 targets；`listTargets` ssh 对账（profile 增→补、删→剔）。
5. **ConnectionModeService 单测**：`isSshMode` 由 home target kind 推导。
6. **清除回归**：全仓 `grep` 断言无 `connectionMode`/`windowsStorageBackend`/`primaryPath`/`additionalPaths`/`migrateIfNeeded`/`currentLegacyTargetId`/`foldersFromLegacyJson`（除内部传输描述符若保留）。
7. **UI widget 测试**：选择器按平台渲染正确项；选中调 `HomeTargetStore.save` + 触发 reinstall。
8. **全量**：`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
9. **手验金路径**（CI 不覆盖）：桌面 local 启动；Windows 切 wsl home；Android 选 ssh home 等价于旧"选 profile 远程"；Android 首启无 profile 走建 profile 门。

## 8. 不在 P1 范围（YAGNI / 后续期）

- 去单例 / 控制面-工作面拆分 / `resolve()` 重构 / `StorageBackendMode`↔`RuntimeKind` 统一（P2）。
- 每目录 target、工作面 target 选择、`AppSession.folderAssignments`（P2/P3）。
- 反向隧道、relay、跨机产物、`remoteOs` 探测、Windows-remote 分支（P3）。
- distro 发现/多 distro 选择 UI、远程目录浏览器（后续）。
- `ssh_profiles/` 从控制面移到设备本地的整理（P2 控制面/工作面边界时再定；P1 沿用现状，Android 经现有本地可读路径取 profile 连 home）。

## 7.9 手验金路径（CI 不覆盖，P1 实现后人工确认）

P1 把 home target 反转为设备本地权威（`HomeTargetStore`），并以平台域定的选择器替换连接模式/Windows 后端/选 profile 三件套。下列路径需人工确认：

1. **桌面 local 启动**：首启无 stored home → 默认 `local` → `mode==native`，数据落 `~/.local/share/com.hhoa.teampilot`；选择器只显示「This device」。
2. **Windows 切 home 到 wsl**：选择器选 `wsl:<distro>` → 重装 + reload → `mode==wsl`，数据落 WSL `$HOME/...`；WSL 不可用时落引导回退到 local（`_switchToNativeStorageAndRetry` 写 `HomeTargetStore('local')`）。
3. **Android 选 ssh home == 旧「选 profile 远程」**：Android quick-switch 选 profile → `setHomeTarget('ssh:<id>')` → 重装到远端 + reload；与 P1 前选中该 profile 行为等价。
4. **Android 首启无 profile → create-profile 门 → 成为 home**：`StartupGate` 在 `Android && home kind != ssh` 时强制 `SshProfileSetupPage`；建好首个 profile 后 `onProfileSaved` 自动 `setHomeTarget('ssh:<firstId>')` 进入。

实现要点：`homeTargetId`（device-local SharedPrefs，key `flashskyai.home_target.v1`）是唯一 home 权威；`targets.json` 退为纯目录（`{schemaVersion, targets}`）；`SessionPreferences.connectionMode`/`windowsStorageBackend` 字段与 setter 已删，`ConnectionMode`/`WindowsStorageBackend` enum 仅作内部传输/`resolve()` 描述符保留（P2 `resolve()` 重构时再清）。
