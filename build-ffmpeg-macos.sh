#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT_TARGET="11.0"
ARCHS=("arm64" "x86_64")

usage() {
  cat <<EOF
Usage: ./build-ffmpeg-macos.sh [--clean] [--jobs N] [--arch "arch1 arch2"]

Options:
  --clean      Remove the build directory before configuring.
  --jobs N     Number of parallel jobs for make. Defaults to CPU count.
  --arch       Target architectures. Options: arm64, x86_64.
               Defaults to "arm64 x86_64".
  -h, --help   Show this help message.
EOF
}

clean=false
jobs=""

while (($#)); do
  case "$1" in
    --clean)
      clean=true
      shift
      ;;
    --jobs)
      jobs="$2"
      shift 2
      ;;
    --arch)
      IFS=' ' read -r -a ARCHS <<< "$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$jobs" ]]; then
  if command -v sysctl >/dev/null 2>&1; then
    jobs="$(sysctl -n hw.ncpu)"
  else
    jobs=1
  fi
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$script_dir"
ffmpeg_root="$repo_root/FFmpeg"
if [[ ! -d "$ffmpeg_root" && -d "$repo_root/ffmpeg" ]]; then
  ffmpeg_root="$repo_root/ffmpeg"
fi
lame_root="$repo_root/lame-3.100"

log() {
  printf "[$(date +%H:%M:%S)] %s\n" "$*"
}

[[ ! -d "$ffmpeg_root" ]] && { echo "Error: FFmpeg source not found at $ffmpeg_root"; exit 1; }
[[ ! -d "$lame_root" ]] && { echo "Error: LAME source not found at $lame_root"; exit 1; }

for arch in "${ARCHS[@]}"; do
  log "Targeting architecture: $arch"

  if [[ "$arch" == "arm64" ]]; then
    sdk="macosx"
    ff_arch="arm64"
    ff_cpu="armv8-a"
    lame_host="arm-apple-darwin"
    extra_flags="-arch arm64 -mmacosx-version-min=$DEPLOYMENT_TARGET"
    install_arch="arm64"
  elif [[ "$arch" == "x86_64" ]]; then
    sdk="macosx"
    ff_arch="x86_64"
    ff_cpu="x86-64"
    lame_host="x86_64-apple-darwin"
    extra_flags="-arch x86_64 -mmacosx-version-min=$DEPLOYMENT_TARGET"
    install_arch="amd64"
  else
    echo "Unsupported architecture: $arch" >&2
    exit 1
  fi

  sdk_path=$(xcrun -sdk "$sdk" --show-sdk-path)
  cc="xcrun -sdk $sdk clang"
  cxx="xcrun -sdk $sdk clang++"
  ar="xcrun -sdk $sdk ar"
  nm="xcrun -sdk $sdk nm"
  ranlib="xcrun -sdk $sdk ranlib"
  strip="xcrun -sdk $sdk strip"
  build_root="$repo_root/build/ffmpeg-macos-$arch"
  install_root="$repo_root/macos/ffmpeg_lib/$install_arch"
  lame_build_root="$repo_root/build/lame-macos-$arch"
  lame_install_root="$lame_build_root/install"

  if ! $clean && [[ -f "$install_root/lib/libavformat.a" && -f "$install_root/lib/libmp3lame.a" ]]; then
    log "Skipping $arch because $install_root already looks built"
    continue
  fi

  if $clean; then
    rm -rf "$build_root" "$lame_build_root" "$install_root"
  fi

  log "Building LAME for $arch..."
  mkdir -p "$lame_build_root"
  cd "$lame_build_root"
  "$lame_root/configure" \
    --prefix="$lame_install_root" \
    --host="$lame_host" \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    CC="$cc" \
    CFLAGS="$extra_flags -isysroot $sdk_path -fPIC" \
    LDFLAGS="$extra_flags -isysroot $sdk_path" \
    AR="$ar" \
    RANLIB="$ranlib"
  make -j"$jobs"
  make install

  mkdir -p "$install_root/lib"
  cp -f "$lame_install_root/lib/libmp3lame.a" "$install_root/lib/libmp3lame.a"

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
    --extra-cflags="$extra_flags -I$lame_install_root/include -fPIC"
    --extra-ldflags="$extra_flags -L$lame_install_root/lib"

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

    --enable-protocol=file,pipe
    --enable-parser=aac,aac_latm,flac,mpegaudio,opus
    --enable-bsf=aac_adtstoasc
    --enable-decoder=aac,aac_latm,flac,mjpeg,mp3,mp3float,opus,pcm_alaw,pcm_f32le,pcm_f64le,pcm_mulaw,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
    --enable-encoder=aac,flac,mjpeg,opus,libmp3lame
    --enable-demuxer=aac,flac,mp3,mov,ffmetadata,ogg,wav,matroska
    --enable-muxer=adts,flac,ipod,matroska,mov,mp3,ogg,opus,wav
  )

  log "Starting FFmpeg configure for macOS $arch"
  "$ffmpeg_root/configure" "${configure_args[@]}"

  log "Starting make -j${jobs}"
  make -j"$jobs"

  log "Starting make install"
  make install

  log "Build finished for $arch. Installation at: $install_root"
done

log "All macOS builds finished."
