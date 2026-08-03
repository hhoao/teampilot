# Linux Packaging

Linux 端使用仓库内的 [fastforge](https://github.com/hhoao/fastforge) 子模块
（`third_party/fastforge`，分支含 AppImage `StartupWMClass` 支持；上游 PR
[#360](https://github.com/fastforgedev/fastforge/pull/360)）打包 `.deb` 和 `AppImage`。

## 一次性准备

```bash
git submodule update --init third_party/fastforge
bash tool/activate_fastforge.sh
# After upstream https://github.com/fastforgedev/fastforge/pull/360 is on pub.dev:
# dart pub global activate fastforge

# 系统依赖（Ubuntu/Debian）
sudo apt install -y dpkg-deb fakeroot file libfuse2
```

`libfuse2` 是 AppImage 运行时需要的。`dpkg-deb` / `fakeroot` 用于构建 `.deb`。

确保 `~/.pub-cache/bin` 在 `PATH` 中：

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## 构建命令（在 `client/` 目录下）

```bash
# 同时构建 deb + AppImage
fastforge release --name dev

# 只构建 deb
fastforge package --platform linux --targets deb

# 只构建 AppImage
fastforge package --platform linux --targets appimage
```

产物在 `client/dist/<version>/` 下。

## 文件结构

```
third_party/fastforge/                            # 打包工具子模块（fork）
client/
├── distribute_options.yaml                       # fastforge 顶层配置（release/jobs）
└── linux/packaging/
    ├── com.hhoa.teampilot.desktop                # 参考 desktop entry（含 StartupWMClass）
    ├── deb/make_config.yaml                      # .deb（startup_wm_class）
    └── appimage/make_config.yaml                 # AppImage（startup_wm_class）
```

## 验证安装效果

### `.deb`

```bash
sudo dpkg -i dist/1.0.0+1/teampilot-1.0.0+1-linux.deb
# 启动后查看 dock：应显示 "TeamPilot" 名称和应用图标
```

卸载：`sudo apt remove teampilot`

### AppImage

```bash
chmod +x dist/1.0.0+1/teampilot-1.0.0+1-linux.AppImage
./dist/1.0.0+1/teampilot-1.0.0+1-linux.AppImage
```

若希望 AppImage 也注册到桌面环境（dock 显示名称/图标），推荐安装
[AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher)，
首次运行时它会自动把 desktop entry 注册到 `~/.local/share/applications/`。
内嵌 `.desktop` 需含 `StartupWMClass=com.hhoa.teampilot`（由子模块 fastforge +
`startup_wm_class` 配置写入）。

## 修改版本号

编辑 [`pubspec.yaml`](../../pubspec.yaml) 中的 `version:` 字段（如 `1.0.1+2`），
fastforge 会自动读取并写进包名和 deb control 文件。

## 常见问题

- **Dock 固定图标无运行点 / 右侧出现 `com.hhoa.teampilot` 齿轮**：窗口 GTK id 是
  `com.hhoa.teampilot`，launcher `.desktop` 缺少 `StartupWMClass`。确认已用
  `tool/activate_fastforge.sh`（非子模块前的 pub.dev 版），且
  `appimage/make_config.yaml` / `deb/make_config.yaml` 含
  `startup_wm_class: com.hhoa.teampilot`。本机临时修复可在
  `~/.local/share/applications/teampilot.desktop` 加同一行。
- **dock 显示 `com.hhoa.teampilot` 而非 `TeamPilot`**：说明系统没在 `XDG_DATA_DIRS/applications/`
  下找到匹配的 desktop 文件。`.deb` 安装后会自动放置；AppImage 需要 AppImageLauncher
  或手动复制 `.desktop` 到 `~/.local/share/applications/` 并 `update-desktop-database`。
- **AppImage 报 `FUSE` 错误**：装 `libfuse2`（Ubuntu 22.04+ 默认不带）。
- **图标不显示**：在 `client/` 下运行 `dart run tool/sync_app_icons.dart`，确保
  [`assets/icons/icon_bg.png`](../../assets/icons/icon_bg.png) 存在，且已同步到
  [`linux/runner/resources/app_icon.png`](../runner/resources/app_icon.png)。
