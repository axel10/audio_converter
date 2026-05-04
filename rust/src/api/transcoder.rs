use ffmpeg::{codec, filter, format, frame, media, Dictionary};
use ffmpeg_next as ffmpeg;

use super::common::ensure_ffmpeg_initialized;
use super::debug::{
    codec_context_bit_rate, debug_frame_limit, debug_packet_limit, describe_audio_frame,
    describe_channel_layout, describe_packet, push_log_line,
};
use super::formats::{
    codec_spec_for_format, encoder_quality_for_bitrate, normalize_path, output_bitrate_mode,
    output_channel_layout, output_format_key, output_sample_format, output_sample_rate,
    uses_lossy_bitrate_controls,
};
use super::models::{AndroidConvertRequest, AndroidConvertResult, ConversionFailure};

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

    let sample_rate = output_sample_rate(
        &output_format_key,
        request.sample_rate,
        decoder.rate(),
    );
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

        if output_format_key != "opus" {
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
    }

    let use_opus_vbr = output_format_key == "opus"
        && matches!(output_bitrate_mode(request), Some("vbr"));
    let encoder = if use_opus_vbr {
        let mut options = Dictionary::new();
        options.set("vbr", "on");
        encoder
            .open_as_with(codec, options)
            .map_err(|error| error.to_string())?
    } else {
        encoder.open_as(codec).map_err(|error| error.to_string())?
    };
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
        if self.input_packet_logs < debug_packet_limit() {
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
                    if self.decoded_frame_logs < debug_frame_limit() {
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
                    if self.filtered_frame_logs < debug_frame_limit() {
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
                    if self.encoded_packet_logs < debug_packet_limit() {
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
                    if self.encoded_packet_logs < debug_packet_limit() {
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

pub(crate) fn transcode_direct(
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
    if let Some(parent) = std::path::Path::new(&output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|error| {
                ConversionFailure::with_log(
                    format!("failed to create output directory: {error}"),
                    debug_log.clone(),
                )
            })?;
        }
    }

    push_log_line(
        &mut debug_log,
        format!("stage=open_input path={input_path}"),
    );
    let mut ictx = format::input(&input_path).map_err(|error| {
        ConversionFailure::with_log(format!("open_input failed: {error}"), debug_log.clone())
    })?;
    push_log_line(
        &mut debug_log,
        format!("stage=open_output path={output_path}"),
    );
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
            transcoder
                .send_packet_to_decoder(&packet)
                .map_err(|error| {
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
