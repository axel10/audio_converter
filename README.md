- 最小音频转码插件

`audio_converter` 现在只负责转码逻辑。
FFmpeg 的构建和携带已经拆到同级项目 `audio_ffmpeg_lib`，所以使用时请确保这个项目也被引入，并且它生成的 ffmpeg 资产可用。

## 使用方式

其他 Flutter 项目可以直接把这个包作为依赖引入，然后正常使用 `AudioConverter`。

如果是通过 GitHub Release 分发预编译产物，构建时会自动下载并解压：

- iOS / macOS：自动拉取 `audio_ffmpeg_lib-ffmpeg-*.zip`
- Android：默认只拉取 `arm64-v8a` 和 `armeabi-v7a` 对应的 `audio_ffmpeg_lib-ffmpeg-android-*.zip`

如果你确实需要 x86 / x86_64，可以在构建时显式指定：

`AUDIO_FFMPEG_LIB_ANDROID_ABIS=arm64-v8a,armeabi-v7a,x86,x86_64`

默认下载地址是：

`https://github.com/axel10/audio_ffmpeg_lib/releases/latest/download`

如果你要换成自己的仓库，可以通过环境变量覆盖：

`AUDIO_FFMPEG_LIB_RELEASE_BASE_URL`

## 发布产物

先在 `audio_ffmpeg_lib` 里生成 ffmpeg 库，再执行：

```bash
../audio_ffmpeg_lib/tooling/package_ffmpeg_assets.sh
```

会得到适合上传到 GitHub Releases 的压缩包。

建议上传这些文件：

- `audio_ffmpeg_lib-ffmpeg-ios-arm64.zip`
- `audio_ffmpeg_lib-ffmpeg-ios-arm64-sim.zip`
- `audio_ffmpeg_lib-ffmpeg-macos-arm64.zip`
- `audio_ffmpeg_lib-ffmpeg-macos-x86_64.zip`
- `audio_ffmpeg_lib-ffmpeg-android-arm64-v8a.zip`
- `audio_ffmpeg_lib-ffmpeg-android-armeabi-v7a.zip`

如果你启用了 Android 的 x86 支持，再额外上传：

- `audio_ffmpeg_lib-ffmpeg-android-x86.zip`
- `audio_ffmpeg_lib-ffmpeg-android-x86_64.zip`

## 桌面端打包约定

Windows 和 Linux 的桌面安装包现在改为随 Rust 插件一起携带 FFmpeg 动态库，不再依赖单独的 `ffmpeg` 可执行文件。

桌面端现在支持在 AAC 输出时选择编码器：

- `Built-in AAC`
- `FDK-AAC`

其中 `FDK-AAC` 依赖你打包的 FFmpeg 动态库确实启用了 `libfdk_aac`。如果你用的是自定义 FFmpeg，请确保它编进了这个编码器。

桌面端现在不再走外部进程，所以 `ConvertRequest.customArgs` 和 `ConvertRequest.ffmpegPath` 只保留为向后兼容字段，不再影响桌面转码路径。

如果你需要自定义输出行为，建议直接在 Rust 侧扩展转码参数，而不是继续拼接 ffmpeg 命令行。

本地构建产物目录现在也按平台分开了：

- `build/ffmpeg-linux/install/lib`
- `build/ffmpeg-windows/install/bin`

如果你确实还想参考旧的命令行式调用，这里只是示例说明，不再是桌面端的默认路径：

```dart
ConvertRequest(
  inputPath: inputPath,
  outputPath: outputPath,
  outputFormat: AudioFormat.mp3,
  customArgs: const ['-vn'],
);
```

## 仍然保留的本地构建方式

如果你想继续本地编译，建议把 ffmpeg 资产构建放到 `audio_ffmpeg_lib` 侧执行，再让 `audio_converter` 只消费这些资产。

Rust 侧的 `rust-ffmpeg` 仍然需要你当前使用的 fork 版本。
