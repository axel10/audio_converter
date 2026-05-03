#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tooling/ensure_ffmpeg_assets.sh <platform> [arch ...]

Platforms:
  ios       Ensures iOS ffmpeg archives are present.
  macos     Ensures macOS ffmpeg archives are present.
  android   Ensures Android ffmpeg shared libraries are present.

Environment:
  AUDIO_CONVERTER_FFMPEG_RELEASE_BASE_URL
      Base URL for the GitHub release assets.
      Defaults to https://github.com/axel10/audio_converter/releases/latest/download
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

platform="$1"
shift || true

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
release_base_url="${AUDIO_CONVERTER_FFMPEG_RELEASE_BASE_URL:-https://github.com/axel10/audio_converter/releases/latest/download}"
release_base_url="${release_base_url%/}"

asset_name_for() {
  local target_platform="$1"
  local arch="$2"

  case "${target_platform}:${arch}" in
    ios:arm64) echo "audio_converter-ffmpeg-ios-arm64.zip" ;;
    ios:arm64-sim) echo "audio_converter-ffmpeg-ios-arm64-sim.zip" ;;
    macos:arm64) echo "audio_converter-ffmpeg-macos-arm64.zip" ;;
    macos:x86_64) echo "audio_converter-ffmpeg-macos-x86_64.zip" ;;
    android:arm64-v8a) echo "audio_converter-ffmpeg-android-arm64-v8a.zip" ;;
    android:armeabi-v7a) echo "audio_converter-ffmpeg-android-armeabi-v7a.zip" ;;
    android:x86) echo "audio_converter-ffmpeg-android-x86.zip" ;;
    android:x86_64) echo "audio_converter-ffmpeg-android-x86_64.zip" ;;
    *)
      echo "Unsupported platform/arch combination: ${target_platform}:${arch}" >&2
      return 1
      ;;
  esac
}

marker_path_for() {
  local target_platform="$1"
  local arch="$2"

  case "${target_platform}:${arch}" in
    ios:arm64) echo "$repo_root/ios/ffmpeg_lib/arm64/lib/libavformat.a" ;;
    ios:arm64-sim) echo "$repo_root/ios/ffmpeg_lib/arm64-sim/lib/libavformat.a" ;;
    macos:arm64) echo "$repo_root/macos/ffmpeg_lib/arm64/lib/libavformat.a" ;;
    macos:x86_64) echo "$repo_root/macos/ffmpeg_lib/amd64/lib/libavformat.a" ;;
    android:arm64-v8a) echo "$repo_root/android/ffmpeg_lib/arm64-v8a/lib/libavformat.so" ;;
    android:armeabi-v7a) echo "$repo_root/android/ffmpeg_lib/armeabi-v7a/lib/libavformat.so" ;;
    android:x86) echo "$repo_root/android/ffmpeg_lib/x86/lib/libavformat.so" ;;
    android:x86_64) echo "$repo_root/android/ffmpeg_lib/x86_64/lib/libavformat.so" ;;
    *)
      echo "Unsupported platform/arch combination: ${target_platform}:${arch}" >&2
      return 1
      ;;
  esac
}

download_and_unpack() {
  local asset_name="$1"
  local download_url="$release_base_url/$asset_name"
  local temp_dir="$repo_root/build/.ffmpeg_assets"
  local archive_path="$temp_dir/$asset_name"

  mkdir -p "$temp_dir"

  echo "Downloading $asset_name from $download_url"
  curl -fL --retry 3 --retry-all-errors -o "$archive_path" "$download_url"

  echo "Unpacking $asset_name into $repo_root"
  unzip -o -q "$archive_path" -d "$repo_root"
}

ensure_one() {
  local target_platform="$1"
  local arch="$2"
  local marker_path
  marker_path="$(marker_path_for "$target_platform" "$arch")"

  if [[ -f "$marker_path" ]]; then
    echo "ffmpeg assets already present for ${target_platform}/${arch}"
    return 0
  fi

  local asset_name
  asset_name="$(asset_name_for "$target_platform" "$arch")"
  download_and_unpack "$asset_name"

  if [[ ! -f "$marker_path" ]]; then
    echo "Failed to find expected ffmpeg asset after unpacking: $marker_path" >&2
    exit 1
  fi
}

case "$platform" in
  ios)
    if [[ $# -eq 0 ]]; then
      set -- arm64 arm64-sim
    fi
    ;;
  macos)
    if [[ $# -eq 0 ]]; then
      set -- arm64 x86_64
    fi
    ;;
  android)
    if [[ $# -eq 0 ]]; then
      set -- arm64-v8a armeabi-v7a
    fi
    ;;
  *)
    echo "Unknown platform: $platform" >&2
    usage >&2
    exit 1
    ;;
esac

for arch in "$@"; do
  ensure_one "$platform" "$arch"
done
