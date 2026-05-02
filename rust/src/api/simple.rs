use std::collections::HashMap;
#[cfg(target_os = "ios")]
use std::ffi::{CStr, CString};
#[cfg(target_os = "ios")]
use std::os::raw::{c_char, c_int, c_void};
use std::path::Path;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::process::Command;
use std::sync::Once;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use std::time::{SystemTime, UNIX_EPOCH};

use ffmpeg::codec::codec::Codec as FfmpegCodec;
use ffmpeg::{codec, filter, format, frame, media};
use ffmpeg_next as ffmpeg;
use serde::{Deserialize, Serialize};

static FFMPEG_INIT: Once = Once::new();

fn ensure_ffmpeg_initialized() -> Result<(), String> {
    let mut init_result = Ok(());
    FFMPEG_INIT.call_once(|| {
        init_result = ffmpeg::init().map_err(|error| error.to_string());
    });
    init_result
}

#[derive(Clone, Debug, Deserialize)]
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

#[derive(Debug)]
struct ConversionFailure {
    error_message: String,
    raw_log: Option<String>,
}

impl ConversionFailure {
    fn new(error_message: impl Into<String>) -> Self {
        Self {
            error_message: error_message.into(),
            raw_log: None,
        }
    }

    fn with_log(error_message: impl Into<String>, raw_log: impl Into<String>) -> Self {
        Self {
            error_message: error_message.into(),
            raw_log: Some(raw_log.into()),
        }
    }
}

impl From<String> for ConversionFailure {
    fn from(value: String) -> Self {
        Self::new(value)
    }
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

#[cfg(target_os = "ios")]
extern "C" {
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}

#[cfg(target_os = "ios")]
type AvFoundationM4aEncoder = unsafe extern "C" fn(
    input_wav_path: *const c_char,
    output_m4a_path: *const c_char,
    bit_rate: u32,
    use_vbr: c_int,
    error_buffer: *mut c_char,
    error_buffer_len: c_int,
) -> c_int;

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

fn supports_output_format_on_current_platform(format: &str) -> bool {
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

fn unsupported_output_format_error(request: &AndroidConvertRequest) -> Option<String> {
    if !supports_output_format_on_current_platform(&request.output_format) {
        Some("AAC container output is not supported on iOS or macOS. Use M4A instead.".to_string())
    } else {
        None
    }
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
        (
            "aac",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: codec::Id::AAC,
            },
        ),
        (
            "alac",
            AudioCodecSpec {
                preferred_name: "alac",
                fallback_id: codec::Id::ALAC,
            },
        ),
        (
            "aiff",
            AudioCodecSpec {
                preferred_name: "pcm_s16be",
                fallback_id: codec::Id::PCM_S16BE,
            },
        ),
        (
            "caf",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: codec::Id::AAC,
            },
        ),
        (
            "flac",
            AudioCodecSpec {
                preferred_name: "flac",
                fallback_id: codec::Id::FLAC,
            },
        ),
        (
            "m4a",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: codec::Id::AAC,
            },
        ),
        (
            "m4b",
            AudioCodecSpec {
                preferred_name: "aac",
                fallback_id: codec::Id::AAC,
            },
        ),
        (
            "mp3",
            AudioCodecSpec {
                preferred_name: "libmp3lame",
                fallback_id: codec::Id::MP3,
            },
        ),
        (
            "ogg",
            AudioCodecSpec {
                preferred_name: "libvorbis",
                fallback_id: codec::Id::VORBIS,
            },
        ),
        (
            "opus",
            AudioCodecSpec {
                preferred_name: "libopus",
                fallback_id: codec::Id::OPUS,
            },
        ),
        (
            "wav",
            AudioCodecSpec {
                preferred_name: "pcm_s16le",
                fallback_id: codec::Id::PCM_S16LE,
            },
        ),
    ];

    candidates
        .into_iter()
        .filter(|(name, _)| supports_output_format_on_current_platform(name))
        .filter_map(|(name, spec)| spec.find().map(|_| name.to_string()))
        .collect()
}

fn capabilities_notes() -> String {
    let mut notes = "Uses the bundled Rust/FFmpeg build through rust-ffmpeg.".to_string();
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        notes.push_str(" AAC container output is not supported on iOS or macOS; M4A is encoded through Apple's audio stack from a WAV intermediate.");
    }
    notes
}

fn output_channel_layout(
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
    request
        .bit_rate_mode
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn uses_lossy_bitrate_controls(format: &str) -> bool {
    matches!(
        output_format_key(format).as_str(),
        "aac" | "caf" | "m4a" | "m4b" | "mp3" | "ogg" | "opus"
    )
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

const DEBUG_PACKET_LIMIT: usize = 6;
const DEBUG_FRAME_LIMIT: usize = 6;
const DEBUG_BYTES_LIMIT: usize = 16;

fn format_optional_i64(value: Option<i64>) -> String {
    value
        .map(|value| value.to_string())
        .unwrap_or_else(|| "none".to_string())
}

fn describe_channel_layout(layout: ffmpeg::ChannelLayout) -> String {
    format!("0x{:x}/{}ch", layout.bits(), layout.channels())
}

fn preview_audio_bytes(frame: &frame::Audio) -> String {
    if frame.planes() == 0 {
        return "none".to_string();
    }

    let data = frame.data(0);
    if data.is_empty() {
        return "empty".to_string();
    }

    data.iter()
        .take(DEBUG_BYTES_LIMIT)
        .map(|byte| format!("{byte:02x}"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn describe_audio_frame(frame: &frame::Audio) -> String {
    format!(
        "pts={} samples={} rate={} format={} layout={} planes={} bytes[0]={}",
        format_optional_i64(frame.pts()),
        frame.samples(),
        frame.rate(),
        frame.format().name(),
        describe_channel_layout(frame.channel_layout()),
        frame.planes(),
        preview_audio_bytes(frame)
    )
}

fn describe_packet(packet: &ffmpeg::Packet) -> String {
    format!(
        "pts={} dts={} duration={} size={} sideData={} stream={}",
        format_optional_i64(packet.pts()),
        format_optional_i64(packet.dts()),
        packet.duration(),
        packet.size(),
        packet.side_data().count(),
        packet.stream()
    )
}

fn codec_context_bit_rate(context: &codec::encoder::Audio) -> i64 {
    unsafe { (*context.as_ptr()).bit_rate }
}

fn push_log_line(log: &mut String, line: impl AsRef<str>) {
    log.push_str(line.as_ref());
    log.push('\n');
}

struct Transcoder {
    stream_index: usize,
    output_stream_index: usize,
    output_format_key: String,
    filter: filter::Graph,
    decoder: codec::decoder::Audio,
    encoder: codec::encoder::Audio,
    decoder_time_base: ffmpeg::Rational,
    encoder_time_base: ffmpeg::Rational,
    out_time_base: ffmpeg::Rational,
    debug_log: String,
    input_packet_logs: usize,
    decoded_frame_logs: usize,
    filtered_frame_logs: usize,
    encoded_packet_logs: usize,
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
    let codec = codec_spec.find().ok_or_else(|| {
        format!(
            "encoder not available for output format: {}",
            request.output_format
        )
    })?;

    let global_header = octx
        .format()
        .flags()
        .contains(format::flag::Flags::GLOBAL_HEADER);

    let mut stream = octx.add_stream(codec).map_err(|error| error.to_string())?;
    let context = codec::context::Context::from_parameters(stream.parameters())
        .map_err(|error| error.to_string())?;
    let mut encoder = context
        .encoder()
        .audio()
        .map_err(|error| error.to_string())?;

    let sample_rate = request.sample_rate.unwrap_or_else(|| decoder.rate());
    let channel_layout = output_channel_layout(
        request.channels,
        decoder.channel_layout(),
        decoder.channels(),
    );
    let sample_format = output_sample_format(&codec, decoder.format());

    if global_header {
        encoder.set_flags(codec::flag::Flags::GLOBAL_HEADER);
    }

    encoder.set_rate(sample_rate as i32);
    encoder.set_channel_layout(channel_layout);
    unsafe {
        (*encoder.as_mut_ptr()).ch_layout.nb_channels = channel_layout.channels();
    }
    encoder.set_format(sample_format);
    encoder.set_time_base((1, sample_rate as i32));
    if uses_lossy_bitrate_controls(&output_format_key) {
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
    }

    let encoder = encoder.open_as(codec).map_err(|error| error.to_string())?;
    stream.set_time_base((1, sample_rate as i32));
    stream.set_parameters(&encoder);

    let filter = build_filter_graph(&decoder, &encoder)?;
    let decoder_time_base = decoder.time_base();
    let encoder_time_base = encoder.time_base();
    let out_time_base = stream.time_base();
    let mut debug_log = String::new();
    push_log_line(
        &mut debug_log,
        format!(
            "request input={} output={} format={} sampleRate={:?} channels={:?} bitRate={:?} bitRateMode={:?}",
            request.input_path,
            request.output_path,
            request.output_format,
            request.sample_rate,
            request.channels,
            request.bit_rate,
            request.bit_rate_mode
        ),
    );
    push_log_line(
        &mut debug_log,
        format!(
            "decoder stream_index={} time_base={} rate={} format={} layout={} decoder_channels={} bit_rate={}",
            input_stream.index(),
            decoder.time_base(),
            decoder.rate(),
            decoder.format().name(),
            describe_channel_layout(decoder.channel_layout()),
            decoder.channels(),
            decoder.bit_rate()
        ),
    );
    push_log_line(
        &mut debug_log,
        format!(
            "encoder codec={} time_base={} rate={} format={} layout={} frame_size={} bit_rate={}",
            codec.name(),
            encoder.time_base(),
            encoder.rate(),
            encoder.format().name(),
            describe_channel_layout(encoder.channel_layout()),
            encoder.frame_size(),
            codec_context_bit_rate(&encoder)
        ),
    );
    push_log_line(&mut debug_log, "filter_graph:");
    push_log_line(&mut debug_log, filter.dump());

    Ok(Transcoder {
        stream_index: input_stream.index(),
        output_stream_index: stream.index(),
        output_format_key,
        filter,
        decoder,
        encoder,
        decoder_time_base,
        encoder_time_base,
        out_time_base,
        debug_log,
        input_packet_logs: 0,
        decoded_frame_logs: 0,
        filtered_frame_logs: 0,
        encoded_packet_logs: 0,
    })
}

fn build_filter_graph(
    decoder: &codec::decoder::Audio,
    encoder: &codec::encoder::Audio,
) -> Result<filter::Graph, String> {
    let decoder_channel_layout = if decoder.channel_layout().is_empty() {
        ffmpeg::ChannelLayout::default(i32::from(decoder.channels()))
    } else {
        decoder.channel_layout()
    };
    let mut graph = filter::Graph::new();
    let args = format!(
        "time_base={}:sample_rate={}:sample_fmt={}:channel_layout=0x{:x}",
        decoder.time_base(),
        decoder.rate(),
        decoder.format().name(),
        decoder_channel_layout.bits()
    );

    graph
        .add(
            &filter::find("abuffer").ok_or_else(|| "abuffer filter not available".to_string())?,
            "in",
            &args,
        )
        .map_err(|error| error.to_string())?;
    graph
        .add(
            &filter::find("abuffersink")
                .ok_or_else(|| "abuffersink filter not available".to_string())?,
            "out",
            "",
        )
        .map_err(|error| error.to_string())?;

    {
        let mut output = graph
            .get("out")
            .ok_or_else(|| "missing filter sink".to_string())?;
        output.set_sample_format(encoder.format());
        output.set_channel_layout(encoder.channel_layout());
        output.set_sample_rate(encoder.rate());
    }

    graph
        .output("in", 0)
        .map_err(|error| error.to_string())?
        .input("out", 0)
        .map_err(|error| error.to_string())?
        .parse(&format!(
            "aformat=sample_fmts={}:sample_rates={}:channel_layouts=0x{:x}",
            encoder.format().name(),
            encoder.rate(),
            encoder.channel_layout().bits()
        ))
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
    fn finish_debug_log(mut self) -> String {
        push_log_line(
            &mut self.debug_log,
            format!(
                "summary inputPacketsLogged={} decodedFramesLogged={} filteredFramesLogged={} encodedPacketsLogged={}",
                self.input_packet_logs,
                self.decoded_frame_logs,
                self.filtered_frame_logs,
                self.encoded_packet_logs
            ),
        );
        self.debug_log
    }

    fn send_packet_to_decoder(&mut self, packet: &ffmpeg::Packet) -> Result<(), String> {
        if self.input_packet_logs < DEBUG_PACKET_LIMIT {
            push_log_line(
                &mut self.debug_log,
                format!(
                    "input_packet[{}] tb={} {}",
                    self.input_packet_logs,
                    self.decoder_time_base,
                    describe_packet(packet)
                ),
            );
            self.input_packet_logs += 1;
        }
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
                    if self.decoded_frame_logs < DEBUG_FRAME_LIMIT {
                        push_log_line(
                            &mut self.debug_log,
                            format!(
                                "decoded_frame[{}] {}",
                                self.decoded_frame_logs,
                                describe_audio_frame(&decoded)
                            ),
                        );
                        self.decoded_frame_logs += 1;
                    }
                    self.add_frame_to_filter(&decoded)?;
                    self.get_and_process_filtered_frames(octx)?;
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) =>
                {
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
                    if self.filtered_frame_logs < DEBUG_FRAME_LIMIT {
                        push_log_line(
                            &mut self.debug_log,
                            format!(
                                "filtered_frame[{}] {}",
                                self.filtered_frame_logs,
                                describe_audio_frame(&filtered)
                            ),
                        );
                        self.filtered_frame_logs += 1;
                    }
                    self.send_frame_to_encoder(&filtered)?;
                    self.receive_and_process_encoded_packets(octx)?;
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) =>
                {
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
                    encoded.set_stream(self.output_stream_index);
                    if self.encoded_packet_logs < DEBUG_PACKET_LIMIT {
                        push_log_line(
                            &mut self.debug_log,
                            format!(
                                "encoded_packet_before_rescale[{}] tb={} {}",
                                self.encoded_packet_logs,
                                self.encoder_time_base,
                                describe_packet(&encoded)
                            ),
                        );
                    }
                    encoded.rescale_ts(self.encoder_time_base, self.out_time_base);
                    if self.encoded_packet_logs < DEBUG_PACKET_LIMIT {
                        push_log_line(
                            &mut self.debug_log,
                            format!(
                                "encoded_packet_after_rescale[{}] tb={} {}",
                                self.encoded_packet_logs,
                                self.out_time_base,
                                describe_packet(&encoded)
                            ),
                        );
                        self.encoded_packet_logs += 1;
                    }
                    if self.output_format_key == "flac" {
                        encoded
                            .write(octx)
                            .map_err(|error| format!("write_packet failed: {error}"))?;
                    } else {
                        encoded
                            .write_interleaved(octx)
                            .map_err(|error| format!("write_interleaved failed: {error}"))?;
                    }
                }
                Err(error) if matches!(error, ffmpeg::Error::Other { errno } if errno == ffmpeg::util::error::EAGAIN) =>
                {
                    break;
                }
                Err(error) if error == ffmpeg::Error::Eof => {
                    break;
                }
                Err(error) => return Err(format!("receive_packet failed: {error}")),
            }
        }

        Ok(())
    }
}

fn transcode_direct(
    request: &AndroidConvertRequest,
) -> Result<AndroidConvertResult, ConversionFailure> {
    ensure_ffmpeg_initialized().map_err(ConversionFailure::from)?;

    let _ = request.allow_fallback_to_ffmpeg.unwrap_or(true);
    let _ = request.ffmpeg_path.as_deref();
    let _ = request.extra_options.as_ref();
    let mut debug_log = String::new();
    push_log_line(
        &mut debug_log,
        format!(
            "request input={} output={} format={} sampleRate={:?} channels={:?} bitRate={:?} bitRateMode={:?}",
            request.input_path,
            request.output_path,
            request.output_format,
            request.sample_rate,
            request.channels,
            request.bit_rate,
            request.bit_rate_mode
        ),
    );

    let input_path = normalize_path(&request.input_path);
    let output_path = normalize_path(&request.output_path);
    if let Some(parent) = Path::new(&output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|error| {
                ConversionFailure::with_log(
                    format!("failed to create output directory: {error}"),
                    debug_log.clone(),
                )
            })?;
        }
    }

    push_log_line(&mut debug_log, format!("stage=open_input path={input_path}"));
    let mut ictx = format::input(&input_path).map_err(|error| {
        ConversionFailure::with_log(format!("open_input failed: {error}"), debug_log.clone())
    })?;
    push_log_line(&mut debug_log, format!("stage=open_output path={output_path}"));
    let mut octx = format::output(&output_path).map_err(|error| {
        ConversionFailure::with_log(format!("open_output failed: {error}"), debug_log.clone())
    })?;
    push_log_line(&mut debug_log, "stage=build_transcoder");
    let mut transcoder = build_transcoder(&mut ictx, &mut octx, request).map_err(|error| {
        ConversionFailure::with_log(
            format!("build_transcoder failed: {error}"),
            debug_log.clone(),
        )
    })?;

    octx.set_metadata(ictx.metadata().to_owned());
    push_log_line(&mut transcoder.debug_log, "stage=write_header");
    octx.write_header().map_err(|error| {
        ConversionFailure::with_log(
            format!("write_header failed: {error}"),
            transcoder.debug_log.clone(),
        )
    })?;

    for (stream, mut packet) in ictx.packets() {
        if stream.index() == transcoder.stream_index {
            packet.rescale_ts(stream.time_base(), transcoder.decoder_time_base);
            transcoder.send_packet_to_decoder(&packet).map_err(|error| {
                ConversionFailure::with_log(
                    format!("send_packet_to_decoder failed: {error}"),
                    transcoder.debug_log.clone(),
                )
            })?;
            transcoder
                .receive_and_process_decoded_frames(&mut octx)
                .map_err(|error| {
                    ConversionFailure::with_log(
                        format!("receive_and_process_decoded_frames failed: {error}"),
                        transcoder.debug_log.clone(),
                    )
                })?;
        }
    }

    transcoder.send_eof_to_decoder().map_err(|error| {
        ConversionFailure::with_log(
            format!("send_eof_to_decoder failed: {error}"),
            transcoder.debug_log.clone(),
        )
    })?;
    transcoder
        .receive_and_process_decoded_frames(&mut octx)
        .map_err(|error| {
            ConversionFailure::with_log(
                format!("drain_decoded_frames failed: {error}"),
                transcoder.debug_log.clone(),
            )
        })?;
    transcoder.flush_filter().map_err(|error| {
        ConversionFailure::with_log(
            format!("flush_filter failed: {error}"),
            transcoder.debug_log.clone(),
        )
    })?;
    transcoder
        .get_and_process_filtered_frames(&mut octx)
        .map_err(|error| {
            ConversionFailure::with_log(
                format!("process_filtered_frames failed: {error}"),
                transcoder.debug_log.clone(),
            )
        })?;
    transcoder.send_eof_to_encoder().map_err(|error| {
        ConversionFailure::with_log(
            format!("send_eof_to_encoder failed: {error}"),
            transcoder.debug_log.clone(),
        )
    })?;
    transcoder
        .receive_and_process_encoded_packets(&mut octx)
        .map_err(|error| {
            ConversionFailure::with_log(
                format!("drain_encoded_packets failed: {error}"),
                transcoder.debug_log.clone(),
            )
        })?;

    push_log_line(&mut transcoder.debug_log, "stage=write_trailer");
    octx.write_trailer().map_err(|error| {
        ConversionFailure::with_log(
            format!("write_trailer failed: {error}"),
            transcoder.debug_log.clone(),
        )
    })?;
    let raw_log = transcoder.finish_debug_log();

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
        raw_log: Some(raw_log),
    })
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
struct AppleM4aEncodeResult {
    engine: String,
    command: String,
    stdout: Option<String>,
    stderr: Option<String>,
}

fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    if let Some(message) = unsupported_output_format_error(request) {
        return Err(ConversionFailure::new(message));
    }

    if should_use_apple_m4a_encoder(request) {
        return transcode_apple_m4a(request);
    }

    transcode_direct(request)
}

fn should_use_apple_m4a_encoder(request: &AndroidConvertRequest) -> bool {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        output_format_key(&request.output_format) == "m4a"
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = request;
        false
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn transcode_apple_m4a(
    request: &AndroidConvertRequest,
) -> Result<AndroidConvertResult, ConversionFailure> {
    ensure_ffmpeg_initialized().map_err(ConversionFailure::from)?;

    let output_path = normalize_path(&request.output_path);
    if let Some(parent) = Path::new(&output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|error| ConversionFailure::new(error.to_string()))?;
        }
    }

    let temporary_wav_path = temporary_wav_path();
    let temporary_wav_path = temporary_wav_path.to_string_lossy().into_owned();
    let result = (|| {
        let mut wav_request = request.clone();
        wav_request.output_path = temporary_wav_path.clone();
        wav_request.output_format = "wav".to_string();
        wav_request.bit_rate = None;
        wav_request.bit_rate_mode = None;

        transcode_direct(&wav_request)?;

        let apple_result = encode_apple_m4a(&temporary_wav_path, &output_path, request)
            .map_err(ConversionFailure::from)?;
        let engine = format!("rust-ffmpeg+{}", apple_result.engine);
        let command = format!("rust-ffmpeg to WAV temp, then {}", apple_result.command);
        let raw_log = apple_m4a_raw_log(&temporary_wav_path, &apple_result);

        Ok(AndroidConvertResult {
            success: true,
            command: Some(command),
            output_path: Some(output_path),
            engine: Some(engine),
            output_format: Some("m4a".to_string()),
            error_code: None,
            error_message: None,
            stdout: apple_result.stdout,
            stderr: apple_result.stderr,
            raw_log: Some(raw_log),
        })
    })();

    let _ = std::fs::remove_file(&temporary_wav_path);
    result
}

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
fn transcode_apple_m4a(
    request: &AndroidConvertRequest,
) -> Result<AndroidConvertResult, ConversionFailure> {
    let _ = request;
    unreachable!("Apple M4A encoder is only used on iOS and macOS")
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn temporary_wav_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "audio_converter_{}_{}.wav",
        std::process::id(),
        timestamp
    ))
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn apple_m4a_raw_log(wav_path: &str, result: &AppleM4aEncodeResult) -> String {
    let mut buffer = String::new();
    buffer.push_str("rustFfmpegIntermediate: ");
    buffer.push_str(wav_path);
    buffer.push('\n');
    buffer.push_str("appleEncoderCommand: ");
    buffer.push_str(&result.command);

    if let Some(stdout) = result.stdout.as_deref().filter(|value| !value.is_empty()) {
        buffer.push_str("\nstdout:\n");
        buffer.push_str(stdout);
    }
    if let Some(stderr) = result.stderr.as_deref().filter(|value| !value.is_empty()) {
        buffer.push_str("\nstderr:\n");
        buffer.push_str(stderr);
    }

    buffer
}

#[cfg(target_os = "macos")]
fn encode_apple_m4a(
    input_wav_path: &str,
    output_m4a_path: &str,
    request: &AndroidConvertRequest,
) -> Result<AppleM4aEncodeResult, String> {
    let _ = std::fs::remove_file(output_m4a_path);

    let executable = if Path::new("/usr/bin/afconvert").exists() {
        "/usr/bin/afconvert"
    } else {
        "afconvert"
    };
    let args = afconvert_m4a_args(input_wav_path, output_m4a_path, request);
    let output = Command::new(executable)
        .args(&args)
        .output()
        .map_err(|error| format!("failed to launch afconvert: {error}"))?;

    let stdout = process_output_text(&output.stdout);
    let stderr = process_output_text(&output.stderr);
    if !output.status.success() {
        return Err(format!(
            "afconvert failed with exit code {}.{}{}",
            output.status.code().unwrap_or(-1),
            stderr
                .as_deref()
                .filter(|value| !value.is_empty())
                .map(|value| format!("\nstderr:\n{value}"))
                .unwrap_or_default(),
            stdout
                .as_deref()
                .filter(|value| !value.is_empty())
                .map(|value| format!("\nstdout:\n{value}"))
                .unwrap_or_default(),
        ));
    }

    Ok(AppleM4aEncodeResult {
        engine: "afconvert".to_string(),
        command: format_command(executable, &args),
        stdout,
        stderr,
    })
}

#[cfg(target_os = "macos")]
fn afconvert_m4a_args(
    input_wav_path: &str,
    output_m4a_path: &str,
    request: &AndroidConvertRequest,
) -> Vec<String> {
    let strategy = if output_bitrate_mode(request) == Some("vbr") {
        "3"
    } else {
        "0"
    };
    let mut args = vec![
        input_wav_path.to_string(),
        output_m4a_path.to_string(),
        "-f".to_string(),
        "m4af".to_string(),
        "-d".to_string(),
        "aac ".to_string(),
        "-s".to_string(),
        strategy.to_string(),
    ];
    if let Some(bit_rate) = request.bit_rate {
        args.push("-b".to_string());
        args.push(bit_rate.to_string());
    }
    args
}

#[cfg(target_os = "macos")]
fn process_output_text(bytes: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(bytes).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

#[cfg(target_os = "macos")]
fn format_command(executable: &str, args: &[String]) -> String {
    std::iter::once(executable.to_string())
        .chain(args.iter().cloned())
        .map(|part| {
            if part.contains(' ') {
                format!("\"{part}\"")
            } else {
                part
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(target_os = "ios")]
fn resolve_avfoundation_m4a_encoder() -> Result<AvFoundationM4aEncoder, String> {
    let symbol = CString::new("audio_converter_encode_m4a_with_avfoundation")
        .map_err(|_| "invalid AVFoundation encoder symbol name".to_string())?;
    let pointer = unsafe { dlsym((-2isize) as *mut c_void, symbol.as_ptr()) };
    if pointer.is_null() {
        return Err("AVFoundation M4A encoder symbol was not found in the process.".to_string());
    }

    Ok(unsafe { std::mem::transmute::<*mut c_void, AvFoundationM4aEncoder>(pointer) })
}

#[cfg(target_os = "ios")]
fn encode_apple_m4a(
    input_wav_path: &str,
    output_m4a_path: &str,
    request: &AndroidConvertRequest,
) -> Result<AppleM4aEncodeResult, String> {
    let _ = std::fs::remove_file(output_m4a_path);

    let input_wav_path = CString::new(input_wav_path)
        .map_err(|_| "input path contains an interior NUL byte".to_string())?;
    let output_m4a_path = CString::new(output_m4a_path)
        .map_err(|_| "output path contains an interior NUL byte".to_string())?;
    let encoder = resolve_avfoundation_m4a_encoder()?;
    let mut error_buffer = vec![0 as c_char; 4096];
    let result = unsafe {
        encoder(
            input_wav_path.as_ptr(),
            output_m4a_path.as_ptr(),
            request.bit_rate.unwrap_or(0),
            if output_bitrate_mode(request) == Some("vbr") {
                1
            } else {
                0
            },
            error_buffer.as_mut_ptr(),
            error_buffer.len() as c_int,
        )
    };

    if result != 0 {
        let error_message = unsafe { CStr::from_ptr(error_buffer.as_ptr()) }
            .to_string_lossy()
            .trim()
            .to_string();
        return Err(if error_message.is_empty() {
            format!("AVFoundation M4A encode failed with code {result}")
        } else {
            format!("AVFoundation M4A encode failed with code {result}: {error_message}")
        });
    }

    Ok(AppleM4aEncodeResult {
        engine: "avfoundation".to_string(),
        command: "AVFoundation M4A encode".to_string(),
        stdout: None,
        stderr: None,
    })
}

fn failure_result(
    request: &AndroidConvertRequest,
    error_code: &str,
    error_message: String,
    raw_log: Option<String>,
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
        raw_log,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb]
pub fn android_convert_file(request_json: String) -> String {
    let result = match serde_json::from_str::<AndroidConvertRequest>(&request_json) {
        Ok(request) => {
            if let Some(error) = unsupported_output_format_error(&request) {
                failure_result(&request, "unsupported_format", error, None)
            } else {
                match transcode(&request) {
                    Ok(result) => result,
                    Err(error) => failure_result(
                        &request,
                        "transcode_failed",
                        error.error_message,
                        error.raw_log,
                    ),
                }
            }
        }
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
        notes: Some(capabilities_notes()),
    };

    serde_json::to_string(&capabilities).unwrap()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
