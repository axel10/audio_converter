use flutter_rust_bridge::frb;
use serde_json;

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::apple;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::formats::{
    capabilities_notes, supported_output_formats, unsupported_output_format_error,
};
use super::models::{
    failure_result, AndroidConvertRequest, AndroidConvertResult, AndroidConverterCapabilities,
    ConversionFailure,
};
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::transcoder::transcode_direct;

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    if let Some(message) = unsupported_output_format_error(request) {
        return Err(ConversionFailure::new(message));
    }

    if apple::should_use_apple_m4a_encoder(request) {
        return apple::transcode_apple_m4a(request);
    }

    transcode_direct(request)
}

#[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    let _ = request;
    Err(ConversionFailure::new(
        "Rust FFmpeg backend is disabled on Windows and Linux. Use the Dart ffmpeg fallback instead.",
    ))
}

#[frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[frb]
pub fn convert_file(request_json: String) -> String {
    let result = match serde_json::from_str::<AndroidConvertRequest>(&request_json) {
        Ok(request) => match transcode(&request) {
            Ok(result) => result,
            Err(error) => failure_result(
                &request,
                "transcode_failed",
                error.error_message,
                error.raw_log,
            ),
        },
        Err(error) => invalid_request_result(error.to_string()),
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

#[frb(sync)]
pub fn get_capabilities() -> String {
    #[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
    let capabilities = AndroidConverterCapabilities {
        engine: "rust-ffmpeg".to_string(),
        supported_output_formats: supported_output_formats(),
        supports_progress: false,
        supports_cancellation: false,
        requires_external_binary: false,
        notes: Some(capabilities_notes()),
    };

    #[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
    let capabilities = AndroidConverterCapabilities {
        engine: "unsupported".to_string(),
        supported_output_formats: Vec::new(),
        supports_progress: false,
        supports_cancellation: false,
        requires_external_binary: false,
        notes: Some(
            "Rust FFmpeg backend is disabled on Windows and Linux. The Dart layer uses the system ffmpeg binary instead."
                .to_string(),
        ),
    };

    serde_json::to_string(&capabilities).unwrap()
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
fn invalid_request_result(error_message: String) -> AndroidConvertResult {
    AndroidConvertResult {
        success: false,
        command: None,
        output_path: None,
        engine: Some("unsupported".to_string()),
        output_format: None,
        error_code: Some("invalid_request".to_string()),
        error_message: Some(error_message),
        stdout: None,
        stderr: None,
        raw_log: None,
    }
}

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
fn invalid_request_result(error_message: String) -> AndroidConvertResult {
    AndroidConvertResult {
        success: false,
        command: None,
        output_path: None,
        engine: Some("rust-ffmpeg".to_string()),
        output_format: None,
        error_code: Some("invalid_request".to_string()),
        error_message: Some(error_message),
        stdout: None,
        stderr: None,
        raw_log: None,
    }
}
