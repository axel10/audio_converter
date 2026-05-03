#[cfg(target_os = "ios")]
use std::ffi::{CStr, CString};
#[cfg(target_os = "ios")]
use std::os::raw::{c_char, c_int, c_void};
use std::path::Path;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::process::Command;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use std::time::{SystemTime, UNIX_EPOCH};

use super::common::ensure_ffmpeg_initialized;
use super::formats::{output_bitrate_mode, output_format_key};
use super::models::{AndroidConvertRequest, AndroidConvertResult, ConversionFailure};

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

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(crate) struct AppleM4aEncodeResult {
    pub engine: String,
    pub command: String,
    pub stdout: Option<String>,
    pub stderr: Option<String>,
}

pub(crate) fn should_use_apple_m4a_encoder(request: &AndroidConvertRequest) -> bool {
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
pub(crate) fn transcode_apple_m4a(
    request: &AndroidConvertRequest,
) -> Result<AndroidConvertResult, ConversionFailure> {
    ensure_ffmpeg_initialized().map_err(ConversionFailure::from)?;

    let output_path = super::formats::normalize_path(&request.output_path);
    if let Some(parent) = Path::new(&output_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|error| ConversionFailure::new(error.to_string()))?;
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

        super::transcoder::transcode_direct(&wav_request)?;

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
pub(crate) fn transcode_apple_m4a(
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
