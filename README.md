- 最小音频转码插件

## 使用方式

其他 Flutter 项目可以直接把这个包作为依赖引入，然后正常使用 `AudioConverter`。

如果是通过 GitHub Release 分发预编译产物，构建时会自动下载并解压：

- iOS / macOS：自动拉取 `audio_converter-ffmpeg-*.zip`
- Android：默认只拉取 `arm64-v8a` 和 `armeabi-v7a` 对应的 `audio_converter-ffmpeg-android-*.zip`

如果你确实需要 x86 / x86_64，可以在构建时显式指定：

`AUDIO_CONVERTER_ANDROID_ABIS=arm64-v8a,armeabi-v7a,x86,x86_64`

默认下载地址是：

`https://github.com/axel10/audio_converter/releases/latest/download`

如果你要换成自己的仓库，可以通过环境变量覆盖：

`AUDIO_CONVERTER_FFMPEG_RELEASE_BASE_URL`

## 发布产物

先用现有脚本生成 ffmpeg 库，再执行：

```bash
tooling/package_ffmpeg_assets.sh
```

会得到适合上传到 GitHub Releases 的压缩包。

建议上传这些文件：

- `audio_converter-ffmpeg-ios-arm64.zip`
- `audio_converter-ffmpeg-ios-arm64-sim.zip`
- `audio_converter-ffmpeg-macos-arm64.zip`
- `audio_converter-ffmpeg-macos-x86_64.zip`
- `audio_converter-ffmpeg-android-arm64-v8a.zip`
- `audio_converter-ffmpeg-android-armeabi-v7a.zip`

如果你启用了 Android 的 x86 支持，再额外上传：

- `audio_converter-ffmpeg-android-x86.zip`
- `audio_converter-ffmpeg-android-x86_64.zip`

## 桌面端打包约定

Windows 和 Linux 的桌面安装包，建议把 `ffmpeg` 可执行文件和应用程序放在同一个安装目录里，或者放在代码已经支持的子目录里。

桌面端现在支持在 AAC 输出时选择编码器：

- `Built-in AAC`
- `FDK-AAC`

其中 `FDK-AAC` 依赖你打包的 ffmpeg 二进制确实启用了 `libfdk_aac`。如果你用的是自定义 ffmpeg，请确保它编进了这个编码器。

桌面端还支持额外的 ffmpeg 自定义参数，通过 `ConvertRequest.customArgs` 传入即可，例如：

```dart
ConvertRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  outputFormat: AudioFormat.mp3,
  customArgs: const ['-vn'],
);
```

这些参数只会在 Windows 和 Linux 的外部 ffmpeg 路径上生效，适合像 `-vn`、`-map 0:a:0`、`-metadata title=...` 这样的输出参数。

推荐目录约定：

- Windows
  - `audio_converter_example.exe`
  - `ffmpeg.exe`
  - 可选 `ffprobe.exe`
- Linux
  - `audio_converter_example`
  - `ffmpeg`
  - 可选 `ffprobe`

如果你希望放在子目录里，当前运行时代码也会顺序检查这些位置：

- `./ffmpeg`
- `./bin/ffmpeg`
- `./tools/ffmpeg`
- `./libexec/ffmpeg`

也就是说，安装器只要把二进制解压到程序目录内，代码就能自动找到它；如果你想自己指定路径，`ConvertRequest.ffmpegPath` 仍然可以覆盖默认行为。

本地构建产物目录现在也按平台分开了：

- `build/ffmpeg-linux/install/bin/ffmpeg`
- `build/ffmpeg-windows/install/bin/ffmpeg.exe`

## 仍然保留的本地构建方式

如果你想继续本地编译，`build-ffmpeg-ios.sh`、`build-ffmpeg-macos.sh`、`build-ffmpeg-android.sh` 仍然可用。

Rust 侧的 `rust-ffmpeg` 仍然需要你当前使用的 fork 版本。
