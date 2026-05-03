use std::sync::Once;

use ffmpeg_next as ffmpeg;

static FFMPEG_INIT: Once = Once::new();

pub(crate) fn ensure_ffmpeg_initialized() -> Result<(), String> {
    let mut init_result = Ok(());
    FFMPEG_INIT.call_once(|| {
        init_result = ffmpeg::init().map_err(|error| error.to_string());
    });
    init_result
}
