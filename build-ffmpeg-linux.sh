#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build-ffmpeg-linux.sh [--clean] [--jobs N]

Options:
  --clean      Remove the build directory before configuring.
  --jobs N     Number of parallel jobs for make. Defaults to the CPU count.
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
      if (($# < 2)); then
        echo "Missing value for --jobs" >&2
        exit 1
      fi
      jobs="$2"
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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$script_dir"
ffmpeg_root="$repo_root/ffmpeg"
build_root="$repo_root/build/ffmpeg-linux"
install_root="$build_root/install"

log() {
  printf '[%(%H:%M:%S)T] %s\n' -1 "$*"
}

need_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
}

need_pkg_config_pkg() {
  local pkg="$1"
  if ! pkg-config --exists "$pkg"; then
    echo "Missing pkg-config package: $pkg" >&2
    exit 1
  fi
}

for path in "$ffmpeg_root" "$ffmpeg_root/configure"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required file or directory: $path" >&2
    exit 1
  fi
done

need_tool gcc
need_tool g++
need_tool make
need_tool nasm
need_tool perl
need_tool pkg-config

if command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR="${CCACHE_DIR:-$repo_root/.cache/ffmpeg-linux/ccache}"
  export CCACHE_BASEDIR="$repo_root"
  export CCACHE_NOHASHDIR=1
  export CCACHE_COMPILERCHECK=content
  mkdir -p "$CCACHE_DIR"
  log "Using ccache: $(command -v ccache)"
fi

need_pkg_config_pkg opus
if ! pkg-config --exists libmp3lame && ! pkg-config --exists lame; then
  echo "Missing pkg-config package: libmp3lame (or lame)" >&2
  exit 1
fi
need_pkg_config_pkg fdk-aac
if ! pkg-config --exists libmpg123; then
  log "Warning: libmpg123 not found via pkg-config. Some static builds of libmp3lame might need it."
fi

# We will check if we need to add -lmpg123 or -lm manually for static linking
extra_libs="-lm"
if find /usr /usr/local -name 'libmpg123.a' -print -quit 2>/dev/null | grep -q .; then
  extra_libs="$extra_libs -lmpg123"
else
  log "Note: libmpg123.a not found. If linking fails, you may need to install it or use a version of lame that doesn't depend on it."
fi

if $clean && [[ -e "$build_root" ]]; then
  rm -rf "$build_root"
fi

mkdir -p "$build_root" "$install_root"
cd "$build_root"

if [[ -z "$jobs" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    jobs="$(nproc)"
  else
    jobs=1
  fi
fi

configure_args=(
  --prefix="$install_root"
  --pkg-config-flags="--static"
  --extra-ldflags="-static -L/usr/local/lib"
  --extra-libs="$extra_libs"
  --disable-everything
  --disable-autodetect
  --disable-debug
  --disable-doc
  --disable-ffplay
  --enable-ffprobe
  --disable-avdevice
  --disable-filters
  --enable-filter=aresample
  --enable-small
  --enable-gpl
  --enable-nonfree
  --enable-libfdk-aac
  --enable-protocol=file
  --enable-protocol=pipe
  --enable-parser=aac
  --enable-parser=aac_latm
  --enable-parser=flac
  --enable-parser=mpegaudio
  --enable-parser=opus
  --enable-bsf=aac_adtstoasc
  --enable-decoder=aac
  --enable-decoder=aac_latm
  --enable-decoder=flac
  --enable-decoder=mjpeg
  --enable-decoder=mp3
  --enable-decoder=mp3float
  --enable-decoder=opus
  --enable-decoder=pcm_alaw
  --enable-decoder=pcm_f32le
  --enable-decoder=pcm_f64le
  --enable-decoder=pcm_mulaw
  --enable-decoder=pcm_s16le
  --enable-decoder=pcm_s24le
  --enable-decoder=pcm_s32le
  --enable-decoder=pcm_u8
  --enable-encoder=aac
  --enable-encoder=flac
  --enable-encoder=mjpeg
  --enable-encoder=libmp3lame
  --enable-encoder=libopus
  --enable-encoder=libfdk_aac
  --enable-encoder=pcm_s16le
  --enable-encoder=pcm_s24le
  --enable-encoder=pcm_s32le
  --enable-libopus
  --enable-libmp3lame
  --enable-demuxer=aac
  --enable-demuxer=flac
  --enable-demuxer=mp3
  --enable-demuxer=mov
  --enable-demuxer=ffmetadata
  --enable-demuxer=ogg
  --enable-demuxer=wav
  --enable-demuxer=matroska
  --enable-muxer=adts
  --enable-muxer=flac
  --enable-muxer=ipod
  --enable-muxer=matroska
  --enable-muxer=mov
  --enable-muxer=mp3
  --enable-muxer=ogg
  --enable-muxer=opus
  --enable-muxer=wav
)

if command -v ccache >/dev/null 2>&1; then
  configure_args=(
    --cc="ccache gcc"
    --cxx="ccache g++"
    --dep-cc="ccache gcc"
    "${configure_args[@]}"
  )
fi

log "Starting FFmpeg configure"
"$ffmpeg_root/configure" "${configure_args[@]}"

log "Starting make -j${jobs}"
make -j"$jobs"

log "Starting make install"
make install

log "Build finished"
