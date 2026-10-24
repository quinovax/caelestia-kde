# Airlock：Caelestia KDE 的默认登录屏幕（greetd）

本仓库把登录管理器从 SDDM 换成 [greetd](https://github.com/kennylevinsen/greetd)，
并用 [AstraSuite/Airlock](https://github.com/AstraSuite/Airlock) 作为 greeter。
Airlock 的自我描述是「a modern, fluid Material 3 frontend for greetd, crafted with
Quickshell and Qt6 to seamlessly match Caelestia's shell」，它直接复用 Caelestia 的
M3Shapes、锁屏时钟、FetchCard 与 Google Sans Flex，所以登录屏幕看起来就是会话本身。

**锁屏（KDE 的 kscreenlocker，主题为 Caelestia）不在此次改动范围内**，仍然保持 Caelestia。

## 一、默认选择

| 配置项 | 键名 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 登录管理器 | `LOGIN_MANAGER` | `airlock` | `airlock` / `sddm` / `none` |
| SDDM 主题 | `SDDM_THEME` | `material-you-dark` | 仅在 `LOGIN_MANAGER=sddm` 时使用 |

`LOGIN_MANAGER=airlock` 时，`scripts/05-sddm-theme.sh` 会 source
`scripts/lib/greetd-airlock.sh` 并调用 `greetd_airlock_install`，原有 SDDM 逻辑完整保留，
只是不再执行。

## 二、落盘位置

| 路径 | 内容 |
| --- | --- |
| `/usr/bin/astra-airlock` | greeter 启动器 |
| `/usr/lib64/qt6/qml/Astra/Airlock/` | 编译出的 QML 模块 |
| `/etc/xdg/quickshell/astra-airlock/` | greeter 的 QML 源码与 assets（含 Google Sans Flex、Titan One 字体） |
| `/usr/lib64/qt6/qml/M3Shapes/` | Caelestia 的 M3 形状模块（greeter 读不到 `~/.local`，必须系统级） |
| `/usr/lib64/qt6/qml/Caelestia/` | Airlock `import Caelestia.Blobs` 所需 |
| `/usr/share/fonts/google-material-symbols/MaterialSymbolsRounded.ttf` | 见第五节，缺了登录界面全是豆腐块 |
| `/var/cache/astra-airlock/` | greeter 用户的家目录：`schemes/dynamic/<user>/`、`avatars/<user>`、`wallpapers/<user>` |
| `/usr/local/bin/caelestia-airlock-sync` | 配色/头像/壁纸同步助手 |
| `/etc/sudoers.d/caelestia-airlock-sync` | 允许当前用户免密调用上面这个助手 |
| `/etc/greetd/config.toml` | `cage -s -- astra-airlock` |

## 三、greeter 用户

greetd 需要一个无特权账号来跑 greeter：

```bash
useradd -r -M -s /usr/sbin/nologin -d /var/cache/astra-airlock greeter
usermod -aG video,input,render greeter
```

`video`/`render` 让 cage 拿到 DRM 设备，`input` 让它读到输入设备。
greeter 的家目录就是 `/var/cache/astra-airlock`，因为 greetd 用 PAM 建立会话后
`HOME` 会指向 passwd 里的 home。

## 四、greetd 配置

```toml
[terminal]
vt = 1

[default_session]
command = "cage -s -- astra-airlock >/dev/null 2>&1"
user = "greeter"
```

原文件会被备份为 `/etc/greetd/config.toml.caelestia-orig`（安装器与 `uninstall.sh` 都会用）。
`cage` 是最小的 wlroots compositor：它只要一个 VT 和 DRM master，不做多余的事；
`-s` 允许 VT 切换，重定向则是为了避免 compositor 日志在 tty 上闪一下。

Fedora 的 `greetd` 包自带 `/etc/pam.d/greetd`，其中已经有 `pam_kwallet5`，
所以登录后 KWallet 会自动解锁，不需要额外配置。

## 五、字体：登录界面唯一的“隐形坑”

Airlock 的界面里所有图标（电源、会话箭头、电池、Caps Lock 提示、密码可见性开关）
都用 **Material Symbols Rounded** 绘制。它和 Google Sans Flex / Titan One 不同：
后两者由 Airlock 自己用 `FontLoader` 从 `assets/fonts/` 加载，前者**完全依赖 fontconfig**。

而本仓库的安装器把 Material Symbols 下载到 **用户** 的
`~/.local/share/fonts/MaterialSymbolsRounded.ttf`。greeter 用户读不到别人的家目录，
所以登录界面会把这些图标全部画成豆腐块（`口`），桌面里却正常——这就是「桌面没问题、
一登录就字体不对」的原因。

修复方式是把它装成系统字体，并在安装时**以 greeter 身份**验证一次：

```bash
install -d -m 0755 /usr/share/fonts/google-material-symbols
install -m 0644 ~/.local/share/fonts/MaterialSymbolsRounded.ttf \
  /usr/share/fonts/google-material-symbols/MaterialSymbolsRounded.ttf
fc-cache -f
HOME=/var/cache/astra-airlock runuser -u greeter -- fc-match 'Material Symbols Rounded'
# 期望输出：MaterialSymbolsRounded.ttf: "Material Symbols Rounded" "Regular"
```

`install_greeter_fonts()` 在 `scripts/lib/greetd-airlock.sh` 中实现：优先复用本地已有的
字体文件，没有就下载，最后一定用 `runuser -u greeter` 复核——因为 fontconfig 的缓存是
按用户分的，root 侧刷新成功不代表 greeter 能看见。

## 六、配色 / 头像 / 壁纸同步

Airlock 自己提供了 `--sync`，但它调用的是上游 Python 版 `caelestia-cli`
（`from caelestia.utils.scheme import get_scheme`）。本仓库是 bash 版 CLI，那条路走不通，
实测会报 `failed to retrieve current scheme from caelestia`。

因此仓库自带 `scripts/lib/caelestia-airlock-sync`（安装到 `/usr/local/bin/`）：

- 用 `SUDO_USER` 判断是哪个用户触发的
- 读 `$HOME/.local/state/caelestia/scheme.json`，生成
  `/var/cache/astra-airlock/schemes/dynamic/<user>/{dark,light}.json`（0644, owner greeter）
- 顺带调用 `astra-airlock --set-pfp` 与 `--set-wallpaper`
- 全程不需要交互，可直接被 hook 调用

`~/.config/caelestia/cli.json` 被写成：

```json
{"theme":{"postHook":"sudo -n /usr/local/bin/caelestia-airlock-sync"},
 "wallpaper":{"postHook":"sudo -n /usr/local/bin/caelestia-airlock-sync"}}
```

于是每次改主题或换壁纸，登录屏幕的配色都会自动跟上。

## 七、切换显示管理器

```bash
systemctl disable sddm.service
systemctl enable greetd.service
```

`display-manager.service` 会被重新指向 `greetd.service`。手动切换回来的方法：

```bash
systemctl disable greetd.service
systemctl enable sddm.service
```

`uninstall.sh` 会先恢复 `/etc/greetd/config.toml.caelestia-orig`、切回 SDDM，再删除 greeter，
避免机器重启后停在一个不存在的登录管理器上。

## 八、验证与回退

```bash
bash tests/test_login_screen.sh          # 12 项，覆盖默认值与步骤选择
journalctl -u greetd --no-pager -n 40    # 成功时会看到 pam_unix(greetd:session) for <user>
```

成功的登录在日志里长这样（先 greeter 会话，再用户会话）：

```
greetd[3069]: pam_unix(greetd-greeter:session): session opened for user greeter(uid=963) by (uid=0)
greetd[3706]: pam_unix(greetd:session): session opened for user quinovax(uid=1000) by quinovax(uid=0)
```

如果只有第一行、随后出现 `greeter exited without creating a session`，说明 greeter 自己
起不来（常见原因：`/usr/lib64/qt6/qml/Caelestia` 缺失、`/var/cache/astra-airlock` 权限不对）。

## 九、故障排查

| 现象 | 检查 |
| --- | --- |
| 登录界面图标全是豆腐块 | `/usr/share/fonts/google-material-symbols` 是否存在；`runuser -u greeter -- fc-match 'Material Symbols Rounded'` |
| 时钟字体不对 | Airlock 自带 Google Sans Flex / Titan One，检查 `/etc/xdg/quickshell/astra-airlock/assets/fonts/` 可读 |
| `module Caelestia.Blobs is not installed` | `/usr/lib64/qt6/qml/Caelestia/` 缺失或不可读（需 `chmod -R a+rX`） |
| `module M3Shapes is not installed` | `/usr/lib64/qt6/qml/M3Shapes/` 缺失，先构建 shell 再重跑安装 |
| 黑屏 / 起不来 | `journalctl -u greetd`；确认 `greeter` 在 `video,input,render` 组里 |
| 配色不跟随桌面 | 手动跑 `sudo -n /usr/local/bin/caelestia-airlock-sync` 看输出 |

## 十、参考命令

| 操作 | 命令 |
| --- | --- |
| 同步配色 | `sudo -n /usr/local/bin/caelestia-airlock-sync` |
| 只同步调色板 | `sudo -n astra-airlock --sync` |
| 设置头像 | `sudo -n astra-airlock --set-pfp <图片>` |
| 设置壁纸 | `sudo -n astra-airlock --set-wallpaper <图片>` |
| 切换输出 | `astra-airlock --output DP-2 --on --output HDMI-A-1 --off` |
