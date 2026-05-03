- 最小音频转码插件

## 使用方式

其他 Flutter 项目可以直接把这个包作为依赖引入，然后正常使用 `AudioConverter`。

如果是通过 GitHub Release 分发预编译产物，构建时会自动下载并解压：

- iOS / macOS：自动拉取 `audio_converter-ffmpeg-*.zip`
- Android：自动拉取对应 ABI 的 `audio_converter-ffmpeg-android-*.zip`

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
- `audio_converter-ffmpeg-android-x86.zip`
- `audio_converter-ffmpeg-android-x86_64.zip`

## 仍然保留的本地构建方式

如果你想继续本地编译，`build-ffmpeg-ios.sh`、`build-ffmpeg-macos.sh`、`build-ffmpeg-android.sh` 仍然可用。

Rust 侧的 `rust-ffmpeg` 仍然需要你当前使用的 fork 版本。
