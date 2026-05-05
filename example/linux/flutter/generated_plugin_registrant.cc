//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_ffmpeg_lib/audio_ffmpeg_lib_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) audio_ffmpeg_lib_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AudioFfmpegLibPlugin");
  audio_ffmpeg_lib_plugin_register_with_registrar(audio_ffmpeg_lib_registrar);
}
