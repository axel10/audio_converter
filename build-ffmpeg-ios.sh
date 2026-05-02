#!/usr/bin/env bash
set -euo pipefail
# 配置项
DEPLOYMENT_TARGET="11.0"
# 默认编译架构：真机 arm64，模拟器 arm64 (Apple Silicon Mac)
# 如果你还在用 Intel Mac，可以加上 x86_64
ARCHS=("arm64" "arm64-sim")
usage() {
  cat <<EOF
Usage: ./build-ffmpeg-ios.sh [--clean] [--jobs N] [--arch "arch1 arch2"]
Options:
  --clean      Remove the build directory before configuring.
  --jobs N     Number of parallel jobs for make. Defaults to CPU count.
  --arch       Target architectures. Options: arm64, arm64-sim, x86_64.
               Defaults to "arm64 arm64-sim".
  -h, --help   Show this help message.
EOF
}
clean=false
jobs=""
while (($#)); do
  case "$1" in
    --clean) clean=true; shift ;;
    --jobs) jobs="$2"; shift 2 ;;
    --arch) IFS=' ' read -r -a ARCHS <<< "$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
if [[ -z "$jobs" ]]; then
  jobs="$(sysctl -n hw.ncpu || echo 1)"
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$script_dir"

find_source_dir() {
  local name="$1"
  local candidate

  while IFS= read -r candidate; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(
    find "$repo_root" -maxdepth 1 -mindepth 1 -type d \
      \( -name "$name" -o -name "${name}-*" -o -name "${name}_*" -o -name "*${name}*" \) \
      -exec test -x '{}/configure' \; -print | sort
  )

  return 1
}

ffmpeg_root="$(find_source_dir FFmpeg || find_source_dir ffmpeg || true)"
lame_root="$(find_source_dir lame || true)"
opus_root="$(find_source_dir opus || true)"
log() {
  printf "[$(date +%H:%M:%S)] %s\n" "$*"
}
[[ -z "$ffmpeg_root" ]] && { echo "Error: FFmpeg source not found in $repo_root" >&2; exit 1; }
[[ -z "$lame_root" ]] && { echo "Error: LAME source not found in $repo_root" >&2; exit 1; }
[[ -z "$opus_root" ]] && { echo "Error: Opus source not found in $repo_root" >&2; exit 1; }
for arch in "${ARCHS[@]}"; do
  log "Targeting architecture: $arch"
  
  # 根据架构设置 SDK 和编译器标志
  if [[ "$arch" == "arm64" ]]; then
    sdk="iphoneos"
    platform_name="iphoneos"
    ff_arch="arm64"
    ff_cpu="armv8-a"
    extra_flags="-arch arm64 -miphoneos-version-min=$DEPLOYMENT_TARGET"
    # Opus treats arm* hosts as 32-bit ARM and enables celt/arm/*.S.
    # Use aarch64 here so Apple Silicon iPhone builds do not pick the wrong asm path.
    opus_host="aarch64-apple-darwin"
  elif [[ "$arch" == "arm64-sim" ]]; then
    sdk="iphonesimulator"
    platform_name="iphonesimulator"
    ff_arch="arm64"
    ff_cpu="armv8-a"
    extra_flags="-arch arm64 -miphonesimulator-version-min=$DEPLOYMENT_TARGET"
    opus_host="aarch64-apple-darwin"
  elif [[ "$arch" == "x86_64" ]]; then
    sdk="iphonesimulator"
    platform_name="iphonesimulator"
    ff_arch="x86_64"
    ff_cpu="x86-64"
    extra_flags="-arch x86_64 -miphonesimulator-version-min=$DEPLOYMENT_TARGET"
    opus_host="x86_64-apple-darwin"
  else
    echo "Unsupported architecture: $arch" >&2; exit 1
  fi
  sdk_path=$(xcrun -sdk "$sdk" --show-sdk-path)
  cc="xcrun -sdk $sdk clang -arch $arch"
  cxx="xcrun -sdk $sdk clang++ -arch $arch"
  ar="xcrun -sdk $sdk ar"
  nm="xcrun -sdk $sdk nm"
  ranlib="xcrun -sdk $sdk ranlib"
  strip="xcrun -sdk $sdk strip"
  build_root="$repo_root/build/ffmpeg-ios-$arch"
  install_root="$repo_root/ios/ffmpeg_lib/$arch"
  lame_build_root="$repo_root/build/lame-ios-$arch"
  lame_install_root="$lame_build_root/install"
  opus_build_root="$repo_root/build/opus-ios-$arch"
  opus_install_root="$opus_build_root/install"
  if $clean; then
    rm -rf "$build_root" "$lame_build_root" "$opus_build_root" "$install_root"
  fi
  # 1. 编译 LAME
  log "Building LAME for $arch..."
  mkdir -p "$lame_build_root"
  cd "$lame_build_root"
  
  # LAME configure 对于 iOS 需要设置 host
  lame_host="arm-apple-darwin"
  [[ "$arch" == "x86_64" ]] && lame_host="x86_64-apple-darwin"
  "$lame_root/configure" \
    --prefix="$lame_install_root" \
    --host="$lame_host" \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    CC="$cc" \
    CFLAGS="$extra_flags -isysroot $sdk_path -fembed-bitcode" \
    LDFLAGS="$extra_flags -isysroot $sdk_path" \
    AR="$ar" \
    RANLIB="$ranlib"
  make -j"$jobs"
  make install
  # FFmpeg's pkg-config metadata links against libmp3lame, so install the
  # matching static archive alongside the other iOS libraries.
  mkdir -p "$install_root/lib"
  cp -f "$lame_install_root/lib/libmp3lame.a" "$install_root/lib/libmp3lame.a"

  # 2. 编译 Opus
  log "Building Opus for $arch..."
  mkdir -p "$opus_build_root"
  cd "$opus_build_root"

  "$opus_root/configure" \
    --prefix="$opus_install_root" \
    --host="$opus_host" \
    --disable-shared \
    --enable-static \
    --disable-extra-programs \
    --disable-doc \
    CC="$cc" \
    CFLAGS="$extra_flags -isysroot $sdk_path -fembed-bitcode -fPIC" \
    LDFLAGS="$extra_flags -isysroot $sdk_path" \
    AR="$ar" \
    RANLIB="$ranlib"
  make -j"$jobs"
  make install

  cp -f "$opus_install_root/lib/libopus.a" "$install_root/lib/libopus.a"

  # 3. 编译 FFmpeg
  log "Configuring FFmpeg for $arch..."
  mkdir -p "$build_root"
  cd "$build_root"
  configure_args=(
    --prefix="$install_root"
    --target-os=darwin
    --arch="$ff_arch"
    --cpu="$ff_cpu"
    --cc="$cc"
    --cxx="$cxx"
    --ar="$ar"
    --nm="$nm"
    --ranlib="$ranlib"
    --strip="$strip"
    --enable-cross-compile
    --sysroot="$sdk_path"
    --extra-cflags="$extra_flags -I$lame_install_root/include -I$opus_install_root/include/opus -fembed-bitcode"
    --extra-ldflags="$extra_flags -L$lame_install_root/lib -L$opus_install_root/lib"

    # 基础配置 (参考你的 Android 脚本)
    --disable-everything
    --disable-autodetect
    --disable-debug
    --disable-doc
    --disable-ffplay
    --disable-ffprobe
    --disable-ffmpeg
    --disable-avdevice
    --disable-filters
    --enable-filter=abuffer,abuffersink,anull,aresample,aformat
    --enable-small
    --enable-gpl
    --enable-pic
    --disable-shared
    --enable-static
    --enable-libmp3lame
    --enable-libopus
    
    # 编解码器配置 (保持与 Android 一致)
    --enable-protocol=file,pipe
    --enable-parser=aac,aac_latm,flac,mpegaudio,opus
    --enable-bsf=aac_adtstoasc
    --enable-decoder=aac,aac_latm,flac,mjpeg,mp3,mp3float,opus,libopus,pcm_alaw,pcm_f32le,pcm_f64le,pcm_mulaw,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
    --enable-encoder=aac,flac,mjpeg,libopus,libmp3lame,pcm_s16be,pcm_s16le
    --enable-demuxer=aac,flac,mp3,mov,ffmetadata,ogg,wav,matroska
    --enable-muxer=adts,flac,ipod,matroska,mov,mp3,ogg,opus,wav
  )
  export PKG_CONFIG_PATH="$opus_install_root/lib/pkgconfig:$lame_install_root/lib/pkgconfig"
  "$ffmpeg_root/configure" --pkg-config-flags="--static" "${configure_args[@]}"
  make -j"$jobs"
  make install
  log "Build finished for $arch. Output: $install_root"
done
log "All iOS builds finished. Libraries are in $repo_root/ios/ffmpeg_lib"
