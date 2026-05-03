use ffmpeg::{codec, frame};
use ffmpeg_next as ffmpeg;

const DEBUG_PACKET_LIMIT: usize = 6;
const DEBUG_FRAME_LIMIT: usize = 6;
const DEBUG_BYTES_LIMIT: usize = 16;

pub(crate) fn debug_packet_limit() -> usize {
    DEBUG_PACKET_LIMIT
}

pub(crate) fn debug_frame_limit() -> usize {
    DEBUG_FRAME_LIMIT
}

pub(crate) fn format_optional_i64(value: Option<i64>) -> String {
    value
        .map(|value| value.to_string())
        .unwrap_or_else(|| "none".to_string())
}

pub(crate) fn describe_channel_layout(layout: ffmpeg::ChannelLayout) -> String {
    format!("0x{:x}/{}ch", layout.bits(), layout.channels())
}

pub(crate) fn preview_audio_bytes(frame: &frame::Audio) -> String {
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

pub(crate) fn describe_audio_frame(frame: &frame::Audio) -> String {
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

pub(crate) fn describe_packet(packet: &ffmpeg::Packet) -> String {
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

pub(crate) fn codec_context_bit_rate(context: &codec::encoder::Audio) -> i64 {
    unsafe { (*context.as_ptr()).bit_rate }
}

pub(crate) fn push_log_line(log: &mut String, line: impl AsRef<str>) {
    log.push_str(line.as_ref());
    log.push('\n');
}
