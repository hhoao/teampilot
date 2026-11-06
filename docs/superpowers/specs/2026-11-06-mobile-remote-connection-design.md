# 移动端远程连接与 SSH 服务器拆分设计

- 日期：2026-11-06
- 状态：待审阅
- 来源：用户提出「远程连接」与「SSH 服务器」应是两个功能：配置放远端、连接能力放本地

## 背景

当前 Android 上「远程连接」和「SSH 服务器管理」是同一套东西：

- `ConnectionModeService.isSshMode` 同时表示"home 绑定到 SSH"和"远程模式"。
- `SshProfilesPage` 既是主机配置页，又是启动门控页（`StartupGate` 在缺少 profile 时直接渲染它）。
- `ssh_profiles/`、`vault/` 被 pin 在设备本地（`client/lib/services/storage/device_local_control_plane.dart`），无法随 home 走，多设备看不到同一份配置。

结果：连接生命周期和配置管理纠缠在一起；主机配置无法在多设备间共享。

## 目标

1. 把「远程连接」（连接层，本地）与「SSH 服务器」（配置层，远端）拆成两个独立功能。
2. `ssh_profiles/`、`vault/` 跟随 home plane 存远端；多设备连同一台 home 即共享同一份配置。
3. 本地只保留"断线也必须可用"的最小 bootstrap。
4. 远端为最终权威；本地先行写入，连上后同步。

## 非目标

- 不改 Termux 分支的既有语义。
- 不做 `~/.ssh/config` 导入（另立需求）。
- 不做多副本双向合并（"每台各存一份 + 合并"的方案已排除）。
- 不改 SSH worker、传输层、PTY 交付状态机。

## 概念定义

### 远程连接（本地）

| 项 | 内容 |
|---|---|
| 数据来源 | 本地 bootstrap（`nativeAppDataPath`） |
| 列出 | 所有已知目标 |
| 新建/编辑 | 连接信息：host、port、用户名、认证方式、登录凭据 |
| 操作 | 连接、断开、重连、切换 home |
| 断线时 | 正常可用 |

### SSH 服务器（远端）

| 项 | 内容 |
|---|---|
| 数据来源 | 远端 home plane |
| 列出 | 连上后才加载远端 profile |
| 编辑 | 完整配置：credential push、端口转发、root sandbox 等 |
| 操作 | 不提供连接、断开、切换 home |
| 断线时 | 不可用，提示"去远程连接页连接" |

### 保险库

- 本地 vault：只存所有目标的 SSH 登录凭据，由远程连接页在新建/编辑目标时写入；删除"新建业务凭据条目"入口。
- 远端 vault：全量业务凭据（provider key、GitHub token 等），跟随 home plane。

### 字段归属原则

**断线重连要用到的字段，一律放本地；只有连上后才用得到的配置，放远端。**

据此：

- 本地：host、port、username、authType、凭据引用、endpoints、hostKeyFingerprints、lastGoodKind、lastHome、lastAppDataRoot、embeddedTarget、relayUrl、pairedDesktopId。
- 远端：连接字段的共享副本（不含凭据）、embeddedTarget、relayUrl、pairedDesktopId，以及后续新增的"连上后才用"配置。

## 模型

### RemoteTarget（本地）

```
id, name, host, port, username, authType,
vaultEntryId,                              // 本地 vault 的登录凭据
endpoints, hostKeyFingerprints, lastGoodKind,
lastHome, lastAppDataRoot,                 // 冷启动缓存路径
embeddedTarget, relayUrl, pairedDesktopId,
updatedAt,
pendingSync                                // 是否有待推送的本地修改
```

### SshServerProfile（远端）

```
id, name, host, port, username, authType,  // 连接字段的共享副本，供多设备同步
embeddedTarget, relayUrl, pairedDesktopId,
updatedAt
```

远端不含凭据，也不含 endpoints、指纹、lastHome（这些是本机的连接状态）。per-target 的 credential push opt-in 继续存放在远端 home 的 `targets.json`（`TargetsRepository.home`），不并入 profile。

## 仓库与路径

| 仓库 | 位置 | 说明 |
|---|---|---|
| `RemoteTargetRepository` | `<nativeAppData>/remote-targets.json` | 由 `deviceLocalSshProfileRepository` 改造 |
| `SshServerProfileRepository` | `<home>/ssh_profiles/profiles.json` | 走 home plane |
| 本地 vault | `<nativeAppData>/vault/` | 只存 SSH 登录凭据 |
| 远端 vault | `<home>/vault/` | 全量业务凭据 |

Cubit：

- `RemoteConnectionCubit`：由 `SshConnectionCubit` 改造，管本地 target 与连接状态。
- `SshServerConfigCubit`：新增，连上后加载远端 profile。

## 同步

### 新建/编辑目标

1. 写本地 `RemoteTarget` + 本地 vault 凭据，立即生效。
2. 置 `pendingSync = true`。
3. 连上目标后 upsert 远端 `SshServerProfile`（不含凭据），清除标记。

### 从其他设备同步

每次连上目标时拉远端 profile：

- 远端 `updatedAt` 更新：用远端连接字段覆盖本地，凭据不动。
- 本地 `updatedAt` 更新：推本地。
- 相同：跳过。

### 冲突

`updatedAt` 新者胜；凭据永远只在本机，不参与同步；冲突写 `AppLogger.w`。

`updatedAt` 只反映可同步字段（连接字段与远端配置）的变更；仅改凭据不更新 `updatedAt`，避免把纯本地变更误判为需要推送。

### 删除

两个页面的删除语义不同：

- **远程连接页**：只删本机连接（本地 target + 本地凭据），远端 profile 保留，其他设备不受影响。
- **SSH 服务器页**：删除远端 profile（影响所有设备），同时删除本机 target；删除前强警告。该页只在已连接时可用，因此能直接删远端。

### home 切换

切换 = 改本地 `currentTargetId` 并重绑 home plane。切走前若有 `pendingSync`，提示"有未同步的修改，仍要切换？"。

## 错误处理

| 场景 | 行为 |
|---|---|
| 同步失败 | 不回滚本地，保留 `pendingSync`，下次连上重试 |
| 远端不可达 | SSH 服务器页提示"未连接，去远程连接页连接"；远程连接页照常可用 |
| 远端没有 profile（首次连） | 用本地 target 创建 |
| 凭据缺失 | 远程连接页提示重新输入，不阻塞其他目标 |

## 迁移

1. 新增 `RemoteTarget` 与 `RemoteTargetRepository`（device-local）。
2. 新增 `SshServerProfile` 与 `SshServerProfileRepository`（home plane）。
3. `SshConnectionCubit` 改造为 `RemoteConnectionCubit`，读本地 target。
4. 新增 `RemoteConnectionsPage`，接管添加目标、连接、切换 home。
5. `SshProfilesPage` 改造为 `SshServersPage`：连上后读远端 profile，去掉连接按钮和添加目标。
6. vault 页删除"新建业务凭据条目"，本地 vault 只展示 SSH 登录凭据。
7. `StartupGate`：Android 未绑定 work home 时跳 `RemoteConnectionsPage`。
8. 旧 `profiles.json` 一次性迁移：读旧文件写本地 `remote-targets.json`，远端 profile 等首次连上再写；写迁移标记避免重复迁移。

## 测试

- 单元：两个仓库读写、旧数据迁移、`updatedAt` 合并、`pendingSync` 重试。
- 组件：SSH 服务器页无连接按钮；远程连接页断线可用。
- 回归：home 切到 ssh 后，`RemoteTargetRepository` 的 fs 仍是 `LocalFilesystem`。
- 集成：新建目标 → 连上 → 远端 profile 出现 → 另一设备连上可见。

验证命令：

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```

## 风险

- **首次使用空窗**：本地只有 target 与凭据，远端 profile 尚未创建；首次连接必须能自举（用本地 target 创建远端 profile）。
- **双写一致性**：本地先行意味着短暂不一致；以 `updatedAt` + `pendingSync` 收敛，不做多副本合并。
- **vault 双份**：本地只存连接凭据，远端存业务凭据；轮换 SSH 凭据只影响本地，不会自动同步到其他设备，需要用户在各自设备重新输入。
- **新设备凭据**：远端 profile 不含凭据，新设备首次连接同一目标需要输入一次登录凭据。
- **迁移失败**：旧 `profiles.json` 解析失败时保留原文件并提示，不覆盖。
