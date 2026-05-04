use ffmpeg::codec::codec::Codec as FfmpegCodec;
use ffmpeg_next as ffmpeg;

use super::models::AndroidConvertRequest;

#[derive(Clone, Copy)]
pub(crate) struct AudioCodecSpec {
    pub preferred_name: &'static str,
    pub fallback_id: ffmpeg::codec::Id,
}

impl AudioCodecSpec {
    pub(crate) fn find(self) -> Option<FfmpegCodec> {
        ffmpeg::codec::encoder::find_by_name(self.preferred_name)
            .or_else(|| ffmpeg::codec::encoder::find(self.fallback_id))
    }
}

pub(crate) fn normalize_path(path: &str) -> String {
    std::path::Path::new(path).to_string_lossy().into_owned()
}

pub(crate) fn output_format_key(value: &str) -> String {
    value.trim().to_lowercase()
}

pub(crate) fn output_sample_rate(format: &str, requested: Option<u32>, fallback: u32) -> u32 {
    let format = output_format_key(format);
    match format.as_str() {
        // libopus only accepts a small set of native rates. When callers do not
        // specify one, or they pass an unsupported input rate like 44100 Hz,
        // we must coerce to a valid rate up front or encoder initialization
        // fails with EINVAL.
        "opus" => match requested {
            Some(rate @ (8000 | 12000 | 16000 | 24000 | 48000)) => rate,
            _ => 48000,
        },
        _ => requested.unwrap_or(fallback),
    }
}

pub(crate) fn supports_output_format_on_current_platform(format: &str) -> bool {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        output_format_key(format) != "aac"
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = format;
        true
    }
}

pub(crate) fn unsupported_output_format_error(request: &AndroidConvertRequest) -> Option<String> {
    if !supports_output_format_on_current_platform(&request.output_format) {
        Some("AAC container output is not supported on iOS or macOS. Use M4A instead.".to_string())
    } else {
        None
    }
}

pub(crate) fn codec_spec_for_format(format: &str) -> Option<AudioCodecSpec> {
    let format = output_format_key(format);
    Some(match format.as_str() {
        "aac" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: ffmpeg::codec::Id::AAC,
        },
        "alac" => AudioCodecSpec {
            preferred_name: "alac",
            fallback_id: ffmpeg::codec::Id::ALAC,
        },
        "aiff" => AudioCodecSpec {
            preferred_name: "pcm_s16be",
            fallback_id: ffmpeg::codec::Id::PCM_S16BE,
        },
        "caf" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: ffmpeg::codec::Id::AAC,
        },
        "flac" => AudioCodecSpec {
            preferred_name: "flac",
            fallback_id: ffmpeg::codec::Id::FLAC,
        },
        "m4a" | "m4b" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: ffmpeg::codec::Id::AAC,
        },
        "mp3" => AudioCodecSpec {
            preferred_name: "libmp3lame",
            fallback_id: ffmpeg::codec::Id::MP3,
        },
        "ogg" => AudioCodecSpec {
            preferred_name: "libvorbis",
            fallback_id: ffmpeg::codec::Id::VORBIS,
        },
        "opus" => AudioCodecSpec {
            preferred_name: "libopus",
            fallback_id: ffmpeg::codec::Id::OPUS,
        },
        "wav" => AudioCodecSpec {
            preferred_name: "pcm_s16le",
            fallback_id: ffmpeg::codec::Id::PCM_S16LE,
        },
        _ => return None,
    })
}

pub(crate) fn supported_output_formats() -> Vec<String> {
    let candidates = [
        (
            "aac",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: ffmpeg::codec::Id::AAC,
            },
        ),
        (
            "alac",
            AudioCodecSpec {
                preferred_name: "alac",
                fallback_id: ffmpeg::codec::Id::ALAC,
            },
        ),
        (
            "aiff",
            AudioCodecSpec {
                preferred_name: "pcm_s16be",
                fallback_id: ffmpeg::codec::Id::PCM_S16BE,
            },
        ),
        (
            "caf",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: ffmpeg::codec::Id::AAC,
            },
        ),
        (
            "flac",
            AudioCodecSpec {
                preferred_name: "flac",
                fallback_id: ffmpeg::codec::Id::FLAC,
            },
        ),
        (
            "m4a",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: ffmpeg::codec::Id::AAC,
            },
        ),
        (
            "m4b",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: ffmpeg::codec::Id::AAC,
            },
        ),
        (
            "mp3",
            AudioCodecSpec {
                preferred_name: "libmp3lame",
                fallback_id: ffmpeg::codec::Id::MP3,
            },
        ),
        (
            "ogg",
            AudioCodecSpec {
                preferred_name: "libvorbis",
                fallback_id: ffmpeg::codec::Id::VORBIS,
            },
        ),
        (
            "opus",
            AudioCodecSpec {
                preferred_name: "libopus",
                fallback_id: ffmpeg::codec::Id::OPUS,
            },
        ),
        (
            "wav",
            AudioCodecSpec {
                preferred_name: "pcm_s16le",
                fallback_id: ffmpeg::codec::Id::PCM_S16LE,
            },
        ),
    ];

    candidates
        .into_iter()
        .filter(|(name, _)| supports_output_format_on_current_platform(name))
        .filter_map(|(name, spec)| spec.find().map(|_| name.to_string()))
        .collect()
}

pub(crate) fn capabilities_notes() -> String {
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    let notes = "Uses the bundled Rust/FFmpeg build through rust-ffmpeg.".to_string();
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    let mut notes = "Uses the bundled Rust/FFmpeg build through rust-ffmpeg.".to_string();
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        notes.push_str(" AAC container output is not supported on iOS or macOS; M4A is encoded through Apple's audio stack from a WAV intermediate.");
    }
    notes
}

pub(crate) fn output_channel_layout(
    channels: Option<u16>,
    fallback: ffmpeg::ChannelLayout,
    fallback_channels: u16,
) -> ffmpeg::ChannelLayout {
    match channels {
        Some(1) => ffmpeg::ChannelLayout::MONO,
        Some(2) => ffmpeg::ChannelLayout::STEREO,
        Some(value) => ffmpeg::ChannelLayout::default(i32::from(value)),
        None if fallback.is_empty() => ffmpeg::ChannelLayout::default(i32::from(fallback_channels)),
        None => fallback,
    }
}

pub(crate) fn output_sample_format(
    codec: &FfmpegCodec,
    fallback: ffmpeg::util::format::Sample,
) -> ffmpeg::util::format::Sample {
    codec
        .audio()
        .ok()
        .and_then(|audio| audio.formats())
        .and_then(|mut formats| formats.next())
        .unwrap_or(fallback)
}

pub(crate) fn output_bitrate_mode(request: &AndroidConvertRequest) -> Option<&str> {
    request
        .bit_rate_mode
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

pub(crate) fn uses_lossy_bitrate_controls(format: &str) -> bool {
    matches!(
        output_format_key(format).as_str(),
        "aac" | "caf" | "m4a" | "m4b" | "mp3" | "ogg" | "opus"
    )
}

pub(crate) fn encoder_quality_for_bitrate(bit_rate: u32) -> Option<usize> {
    let quality = if bit_rate <= 64_000 {
        9
    } else if bit_rate <= 96_000 {
        6
    } else if bit_rate <= 128_000 {
        5
    } else if bit_rate <= 160_000 {
        4
    } else if bit_rate <= 192_000 {
        3
    } else if bit_rate <= 256_000 {
        2
    } else {
        1
    };

    Some(quality)
}
