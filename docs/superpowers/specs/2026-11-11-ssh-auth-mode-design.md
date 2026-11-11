# SSH 目标编辑：显式认证方式切换

## 背景

`client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart` 目前一次性渲染全部凭据字段：
「私钥内容」「密钥口令」「密码」。认证方式没有显式控件，而是由 `_usesPasswordAuth`
按“哪个框有内容”推断：

- 私钥非空 → 私钥认证；
- 否则密码非空 → 密码认证；
- 否则回落到 `profile.authType`（仅编辑时）。

`SshAuthType` 只有 `password` / `privateKey` 两个值，且保存写入器
（`services/ssh/ssh_profile_vault_writer.dart` 的 `sshEditorSecretInputs`）已经强制互斥：
非当前模式的两个字段一律写 `''`（删除）。也就是说“互斥”是既定语义，只是 UI 没表达出来。

实际使用中绝大多数目标用密码；私钥内容和密钥口令是少数，却常驻表单，增加视觉噪音。

## 目标

- 新增「认证方式」分段切换：密码 | 私钥；新建默认「密码」。
- 密码模式只显示「密码」输入框；私钥模式只显示「私钥内容」+「密钥口令」。
- 用显式状态（`SshAuthType`）替换“按内容推断”的逻辑；编辑时以 `profile.authType` 初始化。
- 编辑已有目标时切换认证方式并保存，会删除另一种已保存凭据；保存前弹出一次确认。

## 非目标

- 不改 `SshProfile` / `SshAuthType` 模型、JSON 格式或保险库写入契约。
- 新建目标必须提供密码或私钥：密码模式空密码、私钥模式空私钥都提示
  `formCredentialRequired`（沿用改造前的实际约束；原表述“密码可留空”有误，按此更正）。
- 不新增「高级」折叠；B 方案的按模式条件渲染已经达到“默认不显示私钥/口令”的效果。
- 不做跳板服务器（另立 spec）。
- 不改 SSH 列表页的认证方式展示（`ssh_profiles_page.dart`）。

## 行为

### 布局

表单字段顺序：

1. 标签 | 主机（两列）
2. 用户名 | 端口（两列）
3. **认证方式**（整行：标签 + 分段控件）
4. 按模式渲染：
   - 密码：密码输入框（`TpPasswordInput`，保留 reveal）
   - 私钥：「私钥内容」多行输入（4 行，沿用 `tpMultilineInputDecoration`）+「密钥口令」（`TpPasswordInput`）

私钥/密码/口令控制器保持不变；切换模式只改变可见性，不清空已输入文本，切回时内容仍在。

密码字段的 hint/helper 目前假设“密码与私钥同屏”，在显式模式下会误导，必须一并调整：

- `formPasswordHint`（现「未填写私钥时使用」）改为「登录密码」/「Login password」。
- 移除密码字段的 `helper`（现 `formPasswordHelper`「若已提供私钥则可不填。」）；
  该 key 仅此处使用，连同两个 i18n json 一并删除。
- `formPasswordHintEdit`（「留空则保留已保存密码」）保持不变，但仅在“编辑且未切换认证方式”时显示；
  切换到密码模式时显示 `formPasswordHint`（避免暗示存在一个并不存在的已存密码）。

### 分段控件

- 使用 shared_ui `TpSegmentedControl`（filled pill），两个段：`密码`、`私钥`，不加图标。
- 参数：`totalSwitches: 2`、`initialLabelIndex: _authType.index`；`onToggle` 更新
  `_authType` 并 `setState`。`_TpSegmentedControlTrack` 在 `didUpdateWidget` 同步
  `selectedIndex`，因此可受控。
- 控件左对齐（`Align(alignment: AlignmentDirectional.centerStart)`），宽度为内容宽度。
- 标签「认证方式」用 `TpFormFieldLayout(label: Text(...), child: ...)` 包一层，
  与其它表单字段标签样式一致。
- 不使用 `TpSegmentedPicker`：窄屏它会退化成 `TpCompactSelect` 下拉，不符合“切换按钮”的预期。

### 状态与保存

- 新增 `late SshAuthType _authType;`，`initState` 中：
  `_authType = widget.initialProfile?.authType ?? SshAuthType.password;`
- 删除 `_usesPasswordAuth` getter，所有调用点改为 `_authType == SshAuthType.password`：
  - `_buildProfile()` 的 `authType`
  - `_save()` 的 `usesPassword`
  - `_testConnection()` 的 `usesPassword`
- 密码字段不再需要 `onChanged: () => setState(() {})`，移除。
- 新建 + 任一模式凭据为空：提示 `formCredentialRequired` 并中止保存：
  密码模式看 `_passwordController.text.isEmpty`，私钥模式看
  `_privateKeyController.text.trim().isEmpty`。
- 编辑且**切换了**认证方式：新模式凭据也不能为空（同样提示
  `formCredentialRequired`），否则目标会失去唯一可用凭据。
- 编辑且**未切换**认证方式：沿用现有语义（当前模式的空字段 = 保留已存凭据，`null`）。
- 切换模式不主动清空控制器；写入器在保存时按模式丢弃另一侧值。

### 编辑态切换确认

- 触发条件：`_isEditing && _authType != widget.initialProfile!.authType`，
  在 `_save()` 真正写入前判断。
- 弹窗：`showDialog<bool>` + `TpDialog`（参照
  `pages/ssh_profiles/credential_push_opt_in_tile.dart` 的
  `showCredentialPushConfirm`），标题「切换认证方式？」，
  正文「保存后会清除该目标另一种认证方式已保存的凭据。」，
  按钮：取消（`l10n.cancel`）/「切换并保存」。
- 取消 → `_save()` 返回 `null`，不写入、不关闭编辑对话框。
- 确认 → 正常保存；写入器按新模式删除另一侧凭据（现有行为）。
- 新模式凭据为空时先提示 `formCredentialRequired`，不进入确认弹窗。
- `await` 确认结果后必须检查 `mounted` 再继续写入。
- 只在保存时确认；「测试连接」不触发。

### 导入按钮

- 「从文件导入」`suffixIcon` 行为不变；只在私钥模式可见（随字段一起渲染）。

## 涉及文件

- `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- `client/lib/i18n/sshProfile_en.i18n.json`、`sshProfile_zh.i18n.json`
  （改完跑 `dart run slang`，生成的 `client/lib/l10n/translations_*.g.dart` 一并提交）
- `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

## 文案变更

新增：

| key | en | zh |
|---|---|---|
| `formAuthType` | Authentication | 认证方式 |
| `formAuthPrivateKey` | Private key | 私钥 |
| `formAuthChangeTitle` | Switch authentication? | 切换认证方式？ |
| `formAuthChangeBody` | Saving will remove the credential stored for the other authentication method. | 保存后会清除该目标另一种认证方式已保存的凭据。 |
| `formAuthChangeConfirm` | Switch and save | 切换并保存 |

修改：

| key | en | zh |
|---|---|---|
| `formPasswordHint` | Login password | 登录密码 |

删除（仅此表单使用）：`formPasswordHelper`。

「密码」段复用 `formPassword`；取消复用全局 `cancel`。

## 测试

现有 widget 测试大量使用 `find.byType(TextField).at(n)`，条件渲染后数量与下标会变：

- 密码模式（默认）：`label, host, username, port, password` → 5 个 `TextField`，密码在 index 4。
- 私钥模式（点「私钥」后）：`label, host, username, port, privateKey, passphrase` → 6 个，
  私钥在 index 4。

更新：

1. `saves through the repository and cubit of the calling page`：密码改为 index 4。
2. `pastes a private key and saves it to the vault`：先点「私钥」再填私钥。
3. `reveals the saved password for a plane row with no vault link`：
   密码模式下只有 1 个 reveal 按钮。
4. `private key field stays multiline under the app single-line input theme`：
   先切到私钥模式再断言高度。

新增：

1. 默认显示密码框、不显示「私钥内容」/「密钥口令」；点「私钥」后反转。
2. 编辑密码认证目标时「密码」段选中；编辑私钥认证目标时「私钥」段选中。
3. 编辑态切换认证方式后点保存 → 出现确认弹窗；取消不写库；
   确认写入新 `authType` 且旧凭据被清除（读 vault 断言）。
4. 新建目标：密码模式空密码、私钥模式空私钥都保存失败（不写库）。

## 风险

- 现有测试依赖 `TextField` 顺序，必须逐一核对，不能只改数量。
- 编辑切换会真实删除另一种凭据；确认弹窗只覆盖编辑器的保存路径，
  通过保险库其他入口改写不在本次范围。
