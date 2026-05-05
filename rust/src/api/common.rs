pub(crate) fn ensure_ffmpeg_initialized() -> Result<(), String> {
    ffmpeg_core::ensure_initialized().map_err(|error| error.to_string())
}
