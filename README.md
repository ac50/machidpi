# machidpi

Minimal menu bar tool that enables HiDPI ("Retina") scaling on external
displays. **macOS 26+, Apple Silicon (arm64) only.**

One checkbox per display, a short list of "looks like" resolutions, launch at
login — nothing else.

## Why

EDID-override tools like
[one-key-hidpi](https://github.com/xzhih/one-key-hidpi) write
`scale-resolutions` plists under `/Library/Displays/…/Overrides`. Only the
Intel-era display stack ever read those files. On Apple Silicon the display
pipeline (the DCP coprocessor behind `AppleCLCD2`) builds its mode list
without consulting them, and Apple gates native HiDPI to 4K-and-up panels —
so those tools run "successfully" and change nothing.

[BetterDisplay](https://github.com/waydabber/BetterDisplay) solves this
properly, but it is a big app with dozens of features. machidpi does the one
thing.

## How it works

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

## Install

Download `machidpi.zip` from
[Releases](https://github.com/ac50/machidpi/releases), unzip, drag
`machidpi.app` into `/Applications`.

The app is ad-hoc signed (not notarized): on first launch, right-click →
Open, or allow it under System Settings → Privacy & Security.

Or build it yourself on a Mac:

```sh
swift build -c release --arch arm64
```

## Usage

Click the menu bar icon → check **Enable HiDPI** under your display → pick a
"looks like" resolution. Preferences persist per display (by display UUID)
and re-apply automatically when the display is replugged. Enable **Launch at
Login** to make it permanent.

Diagnostics for bug reports:

```sh
/Applications/machidpi.app/Contents/MacOS/machidpi probe
```

## Limitations

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
- [force-hidpi](https://github.com/sammcj/force-hidpi) and
  [DeskPad](https://github.com/Stengo/DeskPad) — prior art for the
  `CGVirtualDisplay` + mirroring technique.

## 中文简介

machidpi 是一个极简菜单栏工具,为外接显示器启用 HiDPI(Retina)缩放,仅支持
macOS 26+ 与 Apple Silicon。原理:用 `CGVirtualDisplay` 私有 API 创建支持
HiDPI 的虚拟屏,再把物理屏硬件镜像到虚拟屏,由系统以 2× 渲染后降采样输出,
文字清晰锐利。EDID override 类工具(如 one-key-hidpi)在 Apple Silicon 上
已失效,本工具是其现代替代。安装:从 Releases 下载 zip,拖入应用程序文件夹,
首次运行右键打开即可。

## License

MIT
