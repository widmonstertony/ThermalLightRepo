# Tony Repo — iOS/iPadOS 16 Rootless APT Source

Personal APT repository for original jailbreak hacks, fixes, tools, and
experiments by tony. The currently published packages target
iOS/iPadOS 16 rootless jailbreaks and can be installed through Sileo or Zebra.

Repository URL:

```text
https://widmonstertony.github.io/tonyrepo/
```

Add the URL to Sileo or Zebra and refresh sources.

[Add to Sileo](sileo://source/https://widmonstertony.github.io/tonyrepo/) ·
[Add to Zebra](zbra://sources/add/https://widmonstertony.github.io/tonyrepo/) ·
[Open repository page](https://widmonstertony.github.io/tonyrepo/)

## Packages

- **ThermalLightControl 3.5.2** — blocks the direct `CBDisplayModuleiOS` `DisplayBrightness` path that can reduce SDR output to 153.448 nit in games such as Honkai: Star Rail, while preserving CPU/GPU throttling, temperature monitoring, warnings, watchdog, and emergency shutdown.
- **VirtualMac Audio Stability Fix 1.0.1** — preserves VirtualMac microphone and speaker support while preventing the iPadOS 16.1 MediaExperience/Now Playing teardown race.
- **Virtual Mac 1.2.3+609.pause2** — a modified build of the upstream MIT-licensed project with native in-memory Pause/Resume controls and a startup menu-refresh fix. Supported only on the upstream-compatible M1/M2 iPads running iPadOS 14.5–16.3.1.

## Grass Mac Browser

The native Universal 2 macOS client is maintained in the separate
[`widmonstertony/newt66y-mac-universal`](https://github.com/widmonstertony/newt66y-mac-universal)
repository. One package runs natively on both Intel (`x86_64`) and Apple
silicon (`arm64`) Macs.

[Download v1.3.0](https://github.com/widmonstertony/newt66y-mac-universal/releases/tag/v1.3.0) ·
[Bilingual installation guide](https://github.com/widmonstertony/newt66y-mac-universal#readme)

## NewT66y 2.3.7 local universal builder

This repository does **not** redistribute NewT66y, its IPA, app bundle, icon, or a
package containing the app. The public builder only repackages a copy that the
user has lawfully obtained into either a universal iPad/PlayCover IPA or a
rootless jailbreak package on the user's Mac. The generated app includes the
original NewTWebFix navigation, input, Touch Bar, and VidCatch download bridge.

1. Download or clone this repository on a Mac.
2. Put your own `1024app_ios_2.3.7.ipa` beside
   `tools/newt66y-local-builder/Build-NewT66y.command`, or drag the IPA onto that
   command file in Terminal.
3. Run `Build-Universal-IPA.command` for one IPA that can be installed on iPad
   and imported by PlayCover 3.1.0, or run `Build-NewT66y.command` for a
   rootless `.deb`.
4. Install the locally generated result only on your own device. On iPad,
   downloaded videos appear under `Files > On My iPad > 小草补丁V8 > VidCatch`.

Full instructions and the legal/provenance notice are in
[`tools/newt66y-local-builder/README.md`](tools/newt66y-local-builder/README.md).
The generated package is intentionally ignored by Git and must not be committed
to this public repository.

Published compatibility is limited to iOS/iPadOS 16 rootless jailbreaks.

> Sustained high brightness at elevated temperatures increases power consumption,
> display wear, and overheating risk. Monitor device temperature and disable
> ThermalLightControl if the device becomes unusually hot.

---

# Tony Repo 中文说明 — iOS/iPadOS 16 Rootless 越狱源

这是 tony 发布个人原创 hack、修复、工具与实验项目的长期越狱源。
目前公开的软件包面向 iOS/iPadOS 16 rootless 越狱环境。将上面的地址添加到
Sileo 或 Zebra 后刷新软件源即可。

[一键添加到 Sileo](sileo://source/https://widmonstertony.github.io/tonyrepo/) ·
[一键添加到 Zebra](zbra://sources/add/https://widmonstertony.github.io/tonyrepo/) ·
[打开软件源页面](https://widmonstertony.github.io/tonyrepo/)

- **ThermalLightControl 3.5.2**：拦截《崩坏：星穹铁道》等游戏会触发的 `CBDisplayModuleiOS` `DisplayBrightness` 直达路径，防止 SDR 输出被压到 153.448 nit，同时保留 CPU/GPU 降频、温度监控、过热警告、watchdog 和紧急关机保护。
- **VirtualMac Audio Stability Fix 1.0.1**：保留 VirtualMac 的麦克风与扬声器功能，并修复 iPadOS 16.1 上 MediaExperience/正在播放模块销毁时的竞态崩溃。
- **Virtual Mac 1.2.3+609.pause2**：基于上游 MIT 开源项目的修改版，加入原生内存暂停/恢复以及虚拟机启动后自动刷新菜单的修复。仅支持上游兼容的 M1/M2 iPad 与 iPadOS 14.5–16.3.1。

## 小草 Mac 浏览器

原生 Universal 2 macOS 客户端已放在独立的
[`widmonstertony/newt66y-mac-universal`](https://github.com/widmonstertony/newt66y-mac-universal)
仓库。同一个安装包同时原生支持 Intel (`x86_64`) 与 Apple silicon
(`arm64`) Mac。

[下载 v1.3.0](https://github.com/widmonstertony/newt66y-mac-universal/releases/tag/v1.3.0) ·
[中英文安装说明](https://github.com/widmonstertony/newt66y-mac-universal#readme)

## NewT66y 2.3.7 本地通用构建工具

本仓库**不提供或再分发**小草/NewT66y 的 IPA、App、图标或包含 App 的安装包。
公开内容只有原创打包脚本；用户必须在自己的 Mac 上提供自己合法取得的
`1024app_ios_2.3.7.ipa`。脚本可以在本地生成一份同时供 iPad 与 PlayCover 3.1.0
使用的通用 IPA，或者生成 rootless `.deb`。生成的 App 包含 NewTWebFix 的导航、
输入、Touch Bar 与 VidCatch 下载桥接；iPad 下载文件保存在“文件 > 在我的 iPad 上
> 小草补丁V8 > VidCatch”。

请阅读
[`tools/newt66y-local-builder/README.md`](tools/newt66y-local-builder/README.md)
中的完整操作步骤。生成的 `.deb` 已被 Git 忽略，只能传到自己的设备本地安装，
不得提交到本公开仓库。

目前公开支持范围仅为 iOS/iPadOS 16 rootless 越狱环境。
