# NewT66y 2.3.7 Local Universal Builder

这个工具只提供原创打包逻辑，不包含、下载或再分发小草/NewT66y 的 IPA、
App、图标、签名或生成后的安装包。

用户必须提供自己合法取得的 `1024app_ios_2.3.7.ipa`。处理过程完全在用户
自己的 Mac 上完成。工具可以生成：

- 一份同时用于 iPad 与 PlayCover 3.1.0 的通用 IPA；
- 用于 iOS/iPadOS 16 rootless 越狱设备的本地 `.deb`。

生成结果只供用户在自己的设备上安装。

## 系统要求

- Apple silicon 或 Intel Mac
- iOS/iPadOS 16 rootless 越狱设备
- 设备的软件源中可安装 `ldid` 和 `uikittools`
- 自己合法取得的 NewT66y 2.3.7 IPA

## 构建通用 IPA

最简单的方法：

1. 把 IPA 改名为 `1024app_ios_2.3.7.ipa`。
2. 将它放到本目录，但不要加入 Git。
3. 双击 `Build-Universal-IPA.command`。

也可以在 Terminal 中运行：

```bash
./Build-Universal-IPA.command /完整路径/1024app_ios_2.3.7.ipa
```

生成的 `NewT66y-2.3.7-Universal-Mac-iPad-VidCatch.ipa` 位于本目录的
`output/`。该目录已被仓库 `.gitignore` 排除。

- iPad：使用 TrollStore、越狱安装器，或用自己的证书重新签名后安装。
- Mac：把同一份 IPA 导入 PlayCover 3.1.0；PlayCover 会把 iOS Mach-O 转换为 Mac Catalyst。
- iPad 下载位置：“文件 > 在我的 iPad 上 > 小草补丁V8 > VidCatch”。
- Mac 下载位置：`~/Downloads`，并需安装 VidCatch v0.3.0 companion。

直链和点播 HLS 可在 iPad 下载；DASH、直播 HLS、DRM 和受访问控制的视频不在
iPad 原生下载支持范围内。

## 构建 rootless `.deb`

双击 `Build-NewT66y.command`，或者运行：

```bash
./Build-NewT66y.command /完整路径/1024app_ios_2.3.7.ipa
```

生成的 `.deb` 同样包含 NewTWebFix 下载补丁，并保存到本目录的 `output/`。

默认情况下，工具只接受本项目维护者本地验证过的参考副本：

```text
SHA-256: feb2e4559025a45943bbace799fc9c2c81b7bed6a6d32579478d1368e76dc785
Bundle ID: com.cl.NewT66y.2026
Version: 2.3.7
Architecture: arm64
```

这里的哈希只用于识别已经测试的输入，不代表本仓库对第三方 App 的来源、
所有权或安全性作出保证。对自己信任但签名不同的副本，可显式运行：

```bash
./build.sh --accept-other-build /完整路径/1024app_ios_2.3.7.ipa
```

即使使用该选项，工具仍会检查 IPA 路径、App 数量、Bundle ID、版本和 arm64
主程序。

## 安装 rootless `.deb`

把生成的 `.deb` 传到自己的 rootless 越狱设备，然后使用 Sileo、Zebra、Filza
或以下命令本地安装：

```sh
sudo dpkg -i com.tony.newt66y.localbuild_2.3.7-2_iphoneos-arm64.deb
sudo apt-get -f install
```

安装脚本会在设备上使用 `ldid` 对主程序做本地伪签名，并使用 `uicache` 注册
桌面图标。相同 Bundle ID 的既有安装可能发生冲突，安装前请先备份数据并卸载
旧副本。

## 发布边界

- 可以公开复制、修改和分发本目录中的原创打包脚本与文档，适用 MIT License。
- `patch-source/`、补丁 dylib 和 Mach-O 注入工具适用 AGPL-3.0。
- 不得把输入 IPA、解压后的 App、图标或生成的 `.deb` 提交到 Tony Repo。
- 本工具不授予任何第三方 App、名称、图标或内容的权利。
- 用户应遵守所在地区法律、原应用许可条款和设备安全要求。

本项目与 NewT66y、小草、草榴社区及原作者没有官方关联。如权利人认为本工具
中的原创兼容说明不当，请通过 Tony Repo 的 GitHub Issues 联系维护者。
