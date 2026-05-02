use std::collections::HashMap;
use std::path::Path;
use std::sync::Once;

use ffmpeg_next as ffmpeg;
use ffmpeg::{codec, filter, format, frame, media};
use ffmpeg::codec::codec::Codec as FfmpegCodec;
use serde::{Deserialize, Serialize};

static FFMPEG_INIT: Once = Once::new();

fn ensure_ffmpeg_initialized() -> Result<(), String> {
    let mut init_result = Ok(());
    FFMPEG_INIT.call_once(|| {
        init_result = ffmpeg::init().map_err(|error| error.to_string());
    });
    init_result
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AndroidConvertRequest {
    input_path: String,
    output_path: String,
    output_format: String,
    sample_rate: Option<u32>,
    channels: Option<u16>,
    bit_rate: Option<u32>,
    bit_rate_mode: Option<String>,
    ffmpeg_path: Option<String>,
    allow_fallback_to_ffmpeg: Option<bool>,
    extra_options: Option<HashMap<String, String>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AndroidConvertResult {
    success: bool,
    command: Option<String>,
    output_path: Option<String>,
    engine: Option<String>,
    output_format: Option<String>,
    error_code: Option<String>,
    error_message: Option<String>,
    stdout: Option<String>,
    stderr: Option<String>,
    raw_log: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AndroidConverterCapabilities {
    engine: String,
    supported_output_formats: Vec<String>,
    supports_progress: bool,
    supports_cancellation: bool,
    requires_external_binary: bool,
    notes: Option<String>,
}

#[derive(Clone, Copy)]
struct AudioCodecSpec {
    preferred_name: &'static str,
    fallback_id: codec::Id,
}

impl AudioCodecSpec {
    fn find(self) -> Option<FfmpegCodec> {
        codec::encoder::find_by_name(self.preferred_name)
            .or_else(|| codec::encoder::find(self.fallback_id))
    }
}

fn normalize_path(path: &str) -> String {
    Path::new(path).to_string_lossy().into_owned()
}

fn output_format_key(value: &str) -> String {
    value.trim().to_lowercase()
}

fn codec_spec_for_format(format: &str) -> Option<AudioCodecSpec> {
    let format = output_format_key(format);
    Some(match format.as_str() {
        "aac" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: codec::Id::AAC,
        },
        "alac" => AudioCodecSpec {
            preferred_name: "alac",
            fallback_id: codec::Id::ALAC,
        },
        "aiff" => AudioCodecSpec {
            preferred_name: "pcm_s16be",
            fallback_id: codec::Id::PCM_S16BE,
        },
        "caf" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: codec::Id::AAC,
        },
        "flac" => AudioCodecSpec {
            preferred_name: "flac",
            fallback_id: codec::Id::FLAC,
        },
        "m4a" | "m4b" => AudioCodecSpec {
            preferred_name: "aac",
            fallback_id: codec::Id::AAC,
        },
        "mp3" => AudioCodecSpec {
            preferred_name: "libmp3lame",
            fallback_id: codec::Id::MP3,
        },
        "ogg" => AudioCodecSpec {
            preferred_name: "libvorbis",
            fallback_id: codec::Id::VORBIS,
        },
        "opus" => AudioCodecSpec {
            preferred_name: "libopus",
            fallback_id: codec::Id::OPUS,
        },
        "wav" => AudioCodecSpec {
            preferred_name: "pcm_s16le",
            fallback_id: codec::Id::PCM_S16LE,
        },
        _ => return None,
    })
}

fn supported_output_formats() -> Vec<String> {
    let candidates = [
        ("aac", AudioCodecSpec { preferred_name: "aac", fallback_id: codec::Id::AAC }),
        ("alac", AudioCodecSpec { preferred_name: "alac", fallback_id: codec::Id::ALAC }),
        ("aiff", AudioCodecSpec { preferred_name: "pcm_s16be", fallback_id: codec::Id::PCM_S16BE }),
        ("caf", AudioCodecSpec { preferred_name: "aac", fallback_id: codec::Id::AAC }),
        ("flac", AudioCodecSpec { preferred_name: "flac", fallback_id: codec::Id::FLAC }),
        ("m4a", AudioCodecSpec { preferred_name: "aac", fallback_id: codec::Id::AAC }),
        ("m4b", AudioCodecSpec { preferred_name: "aac", fallback_id: codec::Id::AAC }),
        ("mp3", AudioCodecSpec { preferred_name: "libmp3lame", fallback_id: codec::Id::MP3 }),
        ("ogg", AudioCodecSpec { preferred_name: "libvorbis", fallback_id: codec::Id::VORBIS }),
        ("opus", AudioCodecSpec { preferred_name: "libopus", fallback_id: codec::Id::OPUS }),
        ("wav", AudioCodecSpec { preferred_name: "pcm_s16le", fallback_id: codec::Id::PCM_S16LE }),
    ];

    candidates
        .into_iter()
        .filter_map(|(name, spec)| spec.find().map(|_| name.to_string()))
        .collect()
}

fn output_channel_layout(channels: Option<u16>, fallback: ffmpeg::ChannelLayout) -> ffmpeg::ChannelLayout {
    match channels {
        Some(1) => ffmpeg::ChannelLayout::MONO,
        Some(2) => ffmpeg::ChannelLayout::STEREO,
        Some(value) => ffmpeg::ChannelLayout::default(i32::from(value)),
        None => fallback,
    }
}

fn output_sample_format(
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

fn output_bitrate_mode(request: &AndroidConvertRequest) -> Option<&str> {
    request.bit_rate_mode.as_deref().map(str::trim).filter(|value| !value.is_empty())
}

fn encoder_quality_for_bitrate(bit_rate: u32) -> Option<usize> {
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

struct Transcoder {
    stream_index: usize,
    filter: filter::Graph,
    decoder: codec::decoder::Audio,
    encoder: codec::encoder::Audio,
    in_time_base: ffmpeg::Rational,
    out_time_base: ffmpeg::Rational,
}

fn build_transcoder(
    ictx: &mut format::context::Input,
    octx: &mut format::context::Output,
    request: &AndroidConvertRequest,
) -> Result<Transcoder, String> {
    let input_stream = ictx
        .streams()
        .best(media::Type::Audio)
        .ok_or_else(|| "could not find an audio stream in the input file".to_string())?;

    let context = codec::context::Context::from_parameters(input_stream.parameters())
        .map_err(|error| error.to_string())?;
    let mut decoder = context
        .decoder()
        .audio()
        .map_err(|error| error.to_string())?;
    decoder
        .set_parameters(input_stream.parameters())
        .map_err(|error| error.to_string())?;

    let output_format_key = output_format_key(&request.output_format);
    let codec_spec = codec_spec_for_format(&output_format_key)
        .ok_or_else(|| format!("unsupported output format: {}", request.output_format))?;
    let codec = codec_spec
        .find()
        .ok_or_else(|| format!("encoder not available for output format: {}", request.output_format))?;

    let global_header = octx
        .format()
        .flags()
        .contains(format::flag::Flags::GLOBAL_HEADER);

    let mut stream = octx
        .add_stream(codec)
        .map_err(|error| error.to_string())?;
    let context = codec::context::Context::from_parameters(stream.parameters())
        .map_err(|error| error.to_string())?;
    let mut encoder = context
        .encoder()
        .audio()
        .map_err(|error| error.to_string())?;

    let sample_rate = request.sample_rate.unwrap_or_else(|| decoder.rate());
    let channel_layout = output_channel_layout(request.channels, decoder.channel_layout());
    let sample_format = output_sample_format(&codec, decoder.format());

    if global_header {
        encoder.set_flags(codec::flag::Flags::GLOBAL_HEADER);
    }

    encoder.set_rate(sample_rate as i32);
    encoder.set_channel_layout(channel_layout);
    encoder.set_format(sample_format);
    encoder.set_time_base((1, sample_rate as i32));
    encoder.set_bit_rate(
        request
            .bit_rate
            .map(|bit_rate| bit_rate as usize)
            .unwrap_or_else(|| decoder.bit_rate()),
    );

    if let Some(mode) = output_bitrate_mode(request) {
        if mode == "vbr" {
            if let Some(bit_rate) = request.bit_rate {
                if let Some(quality) = encoder_quality_for_bitrate(bit_rate) {
                    encoder.set_quality(quality);
                }
            }
        }
    }

    let encoder = encoder.open_as(codec).map_err(|error| error.to_string())?;
    stream.set_time_base((1, sample_rate as i32));
    stream.set_parameters(&encoder);

    let filter = build_filter_graph(&decoder, &encoder)?;
    let in_time_base = decoder.time_base();
    let out_time_base = stream.time_base();

    Ok(Transcoder {
        stream_index: input_stream.index(),
        filter,
        decoder,
        encoder,
        in_time_base,
        out_time_base,
    })
}

fn build_filter_graph(
    decoder: &codec::decoder::Audio,
    encoder: &codec::encoder::Audio,
) -> Result<filter::Graph, String> {
    let mut graph = filter::Graph::new();
    let args = format!(
        "time_base={}:sample_rate={}:sample_fmt={}:channel_layout=0x{:x}",
        decoder.time_base(),
        decoder.rate(),
        decoder.format().name(),
        decoder.channel_layout().bits()
    );

    graph
        .add(&filter::find("abuffer").ok_or_else(|| "abuffer filter not available".to_string())?, "in", &args)
        .map_err(|error| error.to_string())?;
    graph
        .add(&filter::find("abuffersink").ok_or_else(|| "abuffersink filter not available".to_string())?, "out", "")
        .map_err(|error| error.to_string())?;

    {
        let mut output = graph.get("out").ok_or_else(|| "missing filter sink".to_string())?;
        output.set_sample_format(encoder.format());
        output.set_channel_layout(encoder.channel_layout());
        output.set_sample_rate(encoder.rate());
    }

    graph
        .output("in", 0)
        .map_err(|error| error.to_string())?
        .input("out", 0)
        .map_err(|error| error.to_string())?
        .parse("anull")
        .map_err(|error| error.to_string())?;
    graph.validate().map_err(|error| error.to_string())?;

    if let Some(codec) = encoder.codec() {
        if !codec
            .capabilities()
            .contains(ffmpeg::codec::capabilities::Capabilities::VARIABLE_FRAME_SIZE)
        {
            graph
                .get("out")
                .ok_or_else(|| "missing filter sink".to_string())?
                .sink()
                .set_frame_size(encoder.frame_size());
        }
    }

    Ok(graph)
}

impl Transcoder {
    fn send_packet_to_decoder(&mut self, packet: &ffmpeg::Packet) -> Result<(), String> {
        self.decoder
            .send_packet(packet)
            .map_err(|error| error.to_string())
    }

    fn send_eof_to_decoder(&mut self) -> Result<(), String> {
        self.decoder.send_eof().map_err(|error| error.to_string())
    }

    fn send_eof_to_encoder(&mut self) -> Result<(), String> {
        self.encoder.send_eof().map_err(|error| error.to_string())
    }

    fn receive_and_process_decoded_frames(
        &mut self,
        octx: &mut format::context::Output,
    ) -> Result<(), String> {
        let mut decoded = frame::Audio::empty();
        loop {
            match self.decoder.receive_frame(&mut decoded) {
                Ok(()) => {
                    let timestamp = decoded.timestamp();
                    decoded.set_pts(timestamp);
                    self.add_frame_to_filter(&decoded)?;
                    self.get_and_process_filtered_frames(octx)?;
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) => {
                    break;
                }
                Err(error) if error == ffmpeg::Error::Eof => {
                    break;
                }
                Err(error) => return Err(error.to_string()),
            }
        }

        Ok(())
    }

    fn add_frame_to_filter(&mut self, frame: &frame::Audio) -> Result<(), String> {
        self.filter
            .get("in")
            .ok_or_else(|| "missing filter source".to_string())?
            .source()
            .add(frame)
            .map_err(|error| error.to_string())
    }

    fn flush_filter(&mut self) -> Result<(), String> {
        self.filter
            .get("in")
            .ok_or_else(|| "missing filter source".to_string())?
            .source()
            .flush()
            .map_err(|error| error.to_string())
    }

    fn get_and_process_filtered_frames(
        &mut self,
        octx: &mut format::context::Output,
    ) -> Result<(), String> {
        let mut filtered = frame::Audio::empty();
        loop {
            match self
                .filter
                .get("out")
                .ok_or_else(|| "missing filter sink".to_string())?
                .sink()
                .frame(&mut filtered)
            {
                Ok(()) => {
                    self.send_frame_to_encoder(&filtered)?;
                    self.receive_and_process_encoded_packets(octx)?;
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) => {
                    break;
                }
                Err(error) if error == ffmpeg::Error::Eof => {
                    break;
                }
                Err(error) => return Err(error.to_string()),
            }
        }

        Ok(())
    }

    fn send_frame_to_encoder(&mut self, frame: &frame::Audio) -> Result<(), String> {
        self.encoder
            .send_frame(frame)
            .map_err(|error| error.to_string())
    }

    fn receive_and_process_encoded_packets(
        &mut self,
        octx: &mut format::context::Output,
    ) -> Result<(), String> {
        let mut encoded = ffmpeg::Packet::empty();
        loop {
            match self.encoder.receive_packet(&mut encoded) {
                Ok(()) => {
                    encoded.set_stream(0);
                    encoded.rescale_ts(self.in_time_base, self.out_time_base);
                    encoded
                        .write_interleaved(octx)
                        .map_err(|error| error.to_string())?;
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) => {
                    break;
                }
                Err(error) if error == ffmpeg::Error::Eof => {
                    break;
                }
                Err(error) => return Err(error.to_string()),
            }
        }

        Ok(())
    }
}

fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, String> {
    ensure_ffmpeg_initialized()?;

    let _ = request.allow_fallback_to_ffmpeg.unwrap_or(true);
    let _ = request.ffmpeg_path.as_deref();
    let _ = request.extra_options.as_ref();

    let input_path = normalize_path(&request.input_path);
    let output_path = normalize_path(&request.output_path);
    if let Some(parent) = Path::new(&output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
    }

    let mut ictx = format::input(&input_path).map_err(|error| error.to_string())?;
    let mut octx = format::output(&output_path).map_err(|error| error.to_string())?;
    let mut transcoder = build_transcoder(&mut ictx, &mut octx, request)?;

    octx.set_metadata(ictx.metadata().to_owned());
    octx.write_header().map_err(|error| error.to_string())?;

    for (stream, mut packet) in ictx.packets() {
        if stream.index() == transcoder.stream_index {
            packet.rescale_ts(stream.time_base(), transcoder.in_time_base);
            transcoder.send_packet_to_decoder(&packet)?;
            transcoder.receive_and_process_decoded_frames(&mut octx)?;
        }
    }

    transcoder.send_eof_to_decoder()?;
    transcoder.receive_and_process_decoded_frames(&mut octx)?;
    transcoder.flush_filter()?;
    transcoder.get_and_process_filtered_frames(&mut octx)?;
    transcoder.send_eof_to_encoder()?;
    transcoder.receive_and_process_encoded_packets(&mut octx)?;

    octx.write_trailer().map_err(|error| error.to_string())?;

    Ok(AndroidConvertResult {
        success: true,
        command: None,
        output_path: Some(output_path),
        engine: Some("rust-ffmpeg".to_string()),
        output_format: Some(output_format_key(&request.output_format)),
        error_code: None,
        error_message: None,
        stdout: None,
        stderr: None,
        raw_log: None,
    })
}

fn failure_result(
    request: &AndroidConvertRequest,
    error_code: &str,
    error_message: String,
) -> AndroidConvertResult {
    AndroidConvertResult {
        success: false,
        command: None,
        output_path: None,
        engine: Some("rust-ffmpeg".to_string()),
        output_format: Some(output_format_key(&request.output_format)),
        error_code: Some(error_code.to_string()),
        error_message: Some(error_message),
        stdout: None,
        stderr: None,
        raw_log: None,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb]
pub fn android_convert_file(request_json: String) -> String {
    let result = match serde_json::from_str::<AndroidConvertRequest>(&request_json) {
        Ok(request) => match transcode(&request) {
            Ok(result) => result,
            Err(error) => failure_result(&request, "transcode_failed", error),
        },
        Err(error) => AndroidConvertResult {
            success: false,
            command: None,
            output_path: None,
            engine: Some("rust-ffmpeg".to_string()),
            output_format: None,
            error_code: Some("invalid_request".to_string()),
            error_message: Some(error.to_string()),
            stdout: None,
            stderr: None,
            raw_log: None,
        },
    };

    serde_json::to_string(&result).unwrap_or_else(|error| {
        serde_json::json!({
            "success": false,
            "engine": "rust-ffmpeg",
            "errorCode": "serialization_failed",
            "errorMessage": error.to_string(),
        })
        .to_string()
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn android_get_capabilities() -> String {
    let capabilities = AndroidConverterCapabilities {
        engine: "rust-ffmpeg".to_string(),
        supported_output_formats: supported_output_formats(),
        supports_progress: false,
        supports_cancellation: false,
        requires_external_binary: false,
        notes: Some("Uses the bundled Android FFmpeg build through rust-ffmpeg.".to_string()),
    };

    serde_json::to_string(&capabilities).unwrap()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
