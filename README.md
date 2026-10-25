# machidpi

Crisp HiDPI ("Retina") scaling for sub-4K external displays.
**macOS 26+, Apple Silicon (arm64) only.**

There are two ways to get it; try the first one first:

1. **[Native mode](#native-mode-recommended) — no app.** A one-time display
   override makes macOS itself offer HiDPI "looks like" resolutions for the
   monitor. The monitor stays an ordinary extended display: three-finger
   swipes switch Spaces on it, the built-in display can stay main, and
   windows come back after the monitor is unplugged and replugged.
2. **[The machidpi app](#the-machidpi-app) — virtual display.** A minimal
   menu bar app for setups where native mode does not offer the
   resolutions you want.

## Native mode (recommended)

macOS reads per-model display overrides from
`/Library/Displays/Contents/Resources/Overrides` at boot. A
`scale-resolutions` list in that file adds 2× ("HiDPI") modes for
natively connected external displays on Apple Silicon too — the mechanism
behind BetterDisplay's flexible scaling and
[acuity](https://github.com/paulhkang94/acuity). Each mode renders at 2× and
the display hardware scales the result to the panel.

Verified with a 13.6" MacBook Air and a 2560×1440 Philips monitor on macOS 26:
"looks like 1470×956" renders at 2940×1912, looks as sharp as the app's
virtual display, three-finger swipes switch Spaces on the monitor, and its
windows return after replugging.

### 1. Find the monitor's IDs and native resolution

Turn off any other HiDPI tool for that monitor (in the machidpi app: uncheck
**Enable HiDPI**) and set the monitor to *Extended display*, not mirrored.

- **Vendor and product ID** (hex):

  ```sh
  system_profiler SPDisplaysDataType -json | grep -E '"_name"|display-vendor-id|display-product-id'
  ```

  Each display prints its `_name` followed by its IDs (the very first
  `_name` is the GPU). Skip the built-in panel (vendor `610`) and use the
  monitor's `display-vendor-id` and `display-product-id` values as they are,
  e.g. `410c` and `c21c`. Alternatives: the app's
  `/Applications/machidpi.app/Contents/MacOS/machidpi probe`
  (`vendor=0x410c product=0xc21c`), or
  `ioreg -lw0 | grep -o '"ProductAttributes"={[^}]*}'`, whose
  `LegacyManufacturerID` and `ProductID` are *decimal* — convert them with
  `printf '%x\n' 16652`.
- **Native resolution**: with HiDPI off and the monitor at its default
  resolution, `system_profiler SPDisplaysDataType` — the monitor's
  `Resolution:` line, e.g. `2560 x 1440`.

### 2. Install the override

```sh
curl -fsSLO https://raw.githubusercontent.com/ac50/machidpi/main/scripts/native-hidpi.sh
bash native-hidpi.sh install <vendor> <product> <width> <height> [extra WxH ...]
# example: Philips 2560×1440 monitor, plus the 13.6" MacBook Air size
bash native-hidpi.sh install 410c c21c 2560 1440 1470x956
```

It asks for your administrator password (nothing shows while you type it).
**Reboot** afterwards — macOS only reads overrides at boot.

Installed by default, as far as they fit inside the native resolution:
2560×1440, 2048×1152, 1920×1080, 1680×945, 1600×900, 1440×810 and 1280×720
(a "looks like" size can't be larger than the panel). Extra `WxH` arguments
add sizes — for example your MacBook's own "looks like" size (System
Settings → Displays → built-in display; 1470×956 on a 13.6" Air) gives the
monitor the same UI size as the MacBook, like mirror mode but as its own
extended desktop; on a 16:9 panel it may show black bars at the sides.
Panels that are not 16:9 should pass their own sizes.

### 3. Pick a resolution

System Settings → Displays → select the monitor → choose a size. If the new
sizes are missing, Control-click the resolution thumbnails and choose *Show
List* (or click *Advanced…* and turn on *Show resolutions as list*), then
turn on *Show all resolutions*. `system_profiler SPDisplaysDataType` then
shows e.g. `Resolution: 2940 x 1912` and `UI Looks like: 1470 x 956`.

### Undo

```sh
bash native-hidpi.sh uninstall <vendor> <product>
```

and reboot.

### Notes

- The override applies to every monitor of the same model.
- Changing the list means running `install` again (password) and rebooting.
- macOS can still decline an individual size; it then doesn't appear.
- The script also sets WindowServer's `DisplayResolutionEnabled` preference,
  as acuity does; `uninstall` leaves that setting alone.
- The override carries a display name (`HiDPI Display` unless you run the
  script as `NAME="My Monitor" bash native-hidpi.sh install …`), which
  macOS may show for the monitor.
- The first override the script replaces is saved to `~` and never
  overwritten; `uninstall` prints how to restore it, which matters only if
  another tool wrote it.

## The machidpi app

Apple gates HiDPI on external displays to 4K-class panels. Besides the
override above, the other workaround is a virtual display that renders at 2×
and is mirrored onto the panel. That is what this app does — one checkbox per
display, a short list of "looks like" resolutions, launch at login, nothing
else. [BetterDisplay](https://github.com/waydabber/BetterDisplay) offers the
same technique (and the override one) in a much larger app.

Earlier versions of this README claimed that Apple Silicon ignores
`/Library/Displays/…/Overrides`. For the `scale-resolutions` list that is
wrong — see [Native mode](#native-mode-recommended).

### How it works

1. Creates a virtual display via the CoreGraphics private `CGVirtualDisplay`
   API with `hiDPI = 1`, so WindowServer synthesizes Retina (2×) variants of
   every declared resolution.
2. Hardware-mirrors your physical display onto the virtual one using the
   *public* `CGConfigureDisplayMirrorOfDisplay` API.
3. macOS renders at 2× into the virtual display's backing store; the display
   coprocessor's hardware scaler downsamples that to the panel's native
   pixels. Result: crisp HiDPI text on 1440p/1080p monitors.

The private API surface is exactly four class declarations
(`Sources/CGVirtualDisplayShim`); mirroring, mode enumeration, and mode
switching all use public CoreGraphics APIs.

### Install

Download `machidpi.zip` from
[Releases](https://github.com/ac50/machidpi/releases), unzip, drag
`machidpi.app` into `/Applications`.

The app is ad-hoc signed (not notarized): on first launch, right-click →
Open, or allow it under System Settings → Privacy & Security.

Or build it yourself on a Mac:

```sh
swift build -c release --arch arm64
```

### Usage

Click the menu bar icon → check **Enable HiDPI** under your display → pick a
"looks like" resolution. Preferences — including the display's position in
your arrangement — persist per display (by display UUID) and re-apply
automatically when the display is replugged or at next login. Enable
**Launch at Login** to make it permanent.

#### Sharpness (the ✦ marker)

Rungs marked **✦** are pixel-exact: their 2× backing store maps onto the
panel at an integer ratio, so nothing is resampled. On a 2560×1440 panel
that's *looks like 2560×1440* (renders 5120×2880, exact 2:1 — same UI size
as native, much sharper text) and *looks like 1280×720* (exact 1:1).
Fractional rungs like *looks like 1920×1080* on a 1440p panel (1.5:1) are
inherently a little softer — that is a property of macOS's scaler shared by
every tool of this kind, not something machidpi can remove. Windows stays
sharper at "1080p-sized UI on 2K" because it scales vector UI at native
resolution instead of downsampling a rendered bitmap.

#### Same as MacBook

The rung marked **(same as MacBook)** uses the built-in display's current
"looks like" size (e.g. 1470×956 on a 13.6" MacBook Air), so the external
shows exactly what a mirrored MacBook would — but as its own extended
desktop. It keeps the MacBook's aspect ratio, so a 16:9 panel shows black
bars at the sides, just as in mirror mode.

Diagnostics for bug reports:

```sh
/Applications/machidpi.app/Contents/MacOS/machidpi probe
# live log of every enable, mirror, rung switch and layout restore:
log stream --predicate 'subsystem == "io.github.ac50.machidpi"' --info
```

## Limitations of the app

Native mode has none of the first two; they come with mirroring.

- **Spaces swipe gestures follow a macOS bug on mirror sets**: with the
  cursor on a *secondary* mirror set, a three-finger swipe switches the main
  display's Space instead ([acknowledged by the BetterDisplay maintainer and
  reported to Apple](https://github.com/waydabber/BetterDisplay/issues/144);
  affects Sidecar/AirPlay/DisplayLink mirroring identically). Workaround
  built in: pick **Use as Main Display (fixes Spaces swipes)** in the menu —
  gestures then work on the HiDPI display, and plain (non-mirrored) displays
  like the built-in one are unaffected either way. machidpi remembers the
  arrangement.
- **Unplugging the monitor removes the virtual display**: its ordinary
  windows move to Desktop 1 of the built-in display and don't return on
  replug (full-screen apps do).
- Relies on the private `CGVirtualDisplay` API (stable for years — display
  vendors depend on it — but Apple could change it). Not App Store eligible.
- While HiDPI is active the physical display is a mirror of the virtual one;
  the virtual display *is* that desktop (window arrangement is preserved by
  macOS when toggling).
- No DDC/brightness control, no HDR pipeline, no Intel support — by design.

## Credits

- [one-key-hidpi](https://github.com/xzhih/one-key-hidpi) — the Intel-era
  approach and the reason this tool exists.
- [BetterDisplay / BetterDummy](https://github.com/waydabber/BetterDisplay)
  — pioneered virtual-display HiDPI on Apple Silicon.
- [acuity](https://github.com/paulhkang94/acuity) — the override format
  and evidence that it works on Apple Silicon (native mode).
- [force-hidpi](https://github.com/sammcj/force-hidpi) and
  [DeskPad](https://github.com/Stengo/DeskPad) — prior art for the
  `CGVirtualDisplay` + mirroring technique.

## 中文简介

为 4K 以下的外接显示器启用 HiDPI(Retina)缩放,仅支持 macOS 26+ 与 Apple
Silicon。有两种方式,建议先试第一种:

**原生模式(推荐,不需要任何 App)**:给该型号显示器安装一个系统显示覆盖文件,
由 macOS 自己提供 HiDPI"看起来像"分辨率。外接屏仍是普通扩展屏,三指滑动可切换
桌面、内建屏可继续作为主屏、拔插后窗口会恢复。

1. 关掉其他 HiDPI 工具(machidpi 菜单里取消 **Enable HiDPI**),外接屏设为
   "扩展显示器"(不要镜像)。
2. 查厂商/产品 ID(十六进制):运行
   `system_profiler SPDisplaysDataType -json | grep -E '"_name"|display-vendor-id|display-product-id'`,
   跳过内建屏(vendor 为 `610`),外接屏的 `display-vendor-id`、
   `display-product-id` 直接照抄(例如 `410c`、`c21c`);也可以用
   `machidpi probe`。查原生分辨率:在关闭 HiDPI、默认分辨率下运行
   `system_profiler SPDisplaysDataType`,看外接屏的 `Resolution:`。
3. 安装并**重启**(会要管理员密码):

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/ac50/machidpi/main/scripts/native-hidpi.sh
   bash native-hidpi.sh install 410c c21c 2560 1440 1470x956   # 换成你的 ID 与分辨率
   ```

   输入管理员密码时屏幕上不显示字符,属正常。

   末尾的 `1470x956` 是 13.6 英寸 MacBook Air 的"看起来像"尺寸,加上后外接屏的
   界面大小与 MacBook 相同(类似镜像,但是独立的扩展桌面;16:9 屏可能左右有黑边)。
4. 系统设置 → 显示器 → 外接屏,选择新出现的分辨率。没看到的话,按住 Control
   点按分辨率缩略图改为列表显示(Show List;或点"高级…"打开 Show resolutions
   as list),再打开"显示所有分辨率"(Show all resolutions)。
5. 还原:`bash native-hidpi.sh uninstall 410c c21c`(换成你的 ID)后重启。

注意:覆盖文件对同型号的所有显示器生效;改分辨率列表需重新 `install` 并重启;
macOS 可能拒绝个别分辨率;`uninstall` 不会撤销脚本设置的
`DisplayResolutionEnabled`;覆盖文件会给显示器起名 `HiDPI Display`(可用
`NAME="名称"` 自定义)。

**machidpi App(虚拟屏方式)**:原生模式没有出现想要的分辨率时使用。原理是用
`CGVirtualDisplay` 私有 API 创建支持 HiDPI 的虚拟屏,再把物理屏硬件镜像到虚拟屏。
局限:作为副屏时三指滑动无法切换桌面(macOS 的镜像 bug,菜单里的"Use as Main
Display"可绕过,但外接屏会变成主屏),拔掉外接屏后窗口会移到内建屏桌面 1。
安装:从 Releases 下载 zip,拖入"应用程序"文件夹,首次运行右键打开。

## License

MIT
