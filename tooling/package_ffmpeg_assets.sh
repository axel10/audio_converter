#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tooling/package_ffmpeg_assets.sh [output-dir]

Creates release-ready zip archives for the current ffmpeg build outputs.
The generated archives are written to the output directory, which defaults
to ./release-assets.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="${1:-$repo_root/release-assets}"

mkdir -p "$output_dir"

package_dir() {
  local source_dir="$1"
  local archive_name="$2"
  local source_path="$repo_root/$source_dir"
  local archive_path="$output_dir/$archive_name"

  if [[ ! -d "$source_path" ]]; then
    echo "Skipping missing directory: $source_dir"
    return 0
  fi

  rm -f "$archive_path"
  (
    cd "$repo_root"
    zip -qr "$archive_path" "$source_dir"
  )
  echo "Created $archive_path"
}

package_dir "ios/ffmpeg_lib/arm64" "audio_converter-ffmpeg-ios-arm64.zip"
package_dir "ios/ffmpeg_lib/arm64-sim" "audio_converter-ffmpeg-ios-arm64-sim.zip"
package_dir "macos/ffmpeg_lib/arm64" "audio_converter-ffmpeg-macos-arm64.zip"
package_dir "macos/ffmpeg_lib/amd64" "audio_converter-ffmpeg-macos-x86_64.zip"
package_dir "android/ffmpeg_lib/arm64-v8a" "audio_converter-ffmpeg-android-arm64-v8a.zip"
package_dir "android/ffmpeg_lib/armeabi-v7a" "audio_converter-ffmpeg-android-armeabi-v7a.zip"
package_dir "android/ffmpeg_lib/x86" "audio_converter-ffmpeg-android-x86.zip"
package_dir "android/ffmpeg_lib/x86_64" "audio_converter-ffmpeg-android-x86_64.zip"
