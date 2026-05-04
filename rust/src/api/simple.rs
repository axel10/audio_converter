use flutter_rust_bridge::frb;
use serde_json;

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::apple;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::formats::{
    capabilities_notes, supported_output_formats, unsupported_output_format_error,
};
use super::models::{
    emit_conversion_event, failure_result, AndroidConvertRequest, AndroidConvertResult,
    AndroidConverterCapabilities, ConversionEvent, ConversionFailure,
};
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
use super::transcoder::transcode_direct;
use crate::frb_generated::StreamSink;

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    transcode_impl(request, None)
}

#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
fn transcode_impl(
    request: &AndroidConvertRequest,
    progress_sink: Option<&StreamSink<String>>,
) -> Result<AndroidConvertResult, ConversionFailure> {
    if let Some(message) = unsupported_output_format_error(request) {
        return Err(ConversionFailure::new(message));
    }

    if apple::should_use_apple_m4a_encoder(request) {
        return apple::transcode_apple_m4a(request, progress_sink);
    }

    transcode_direct(request, progress_sink)
}

#[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    let _ = request;
    Err(ConversionFailure::new(
        "Rust FFmpeg backend is disabled on Windows and Linux. Use the Dart ffmpeg fallback instead.",
    ))
}

#[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
fn transcode_impl(
    request: &AndroidConvertRequest,
    progress_sink: Option<&StreamSink<String>>,
) -> Result<AndroidConvertResult, ConversionFailure> {
    let _ = request;
    let _ = progress_sink;
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

#[frb]
pub fn convert_file_with_progress(request_json: String, progress_sink: StreamSink<String>) {
    let result = match serde_json::from_str::<AndroidConvertRequest>(&request_json) {
        Ok(request) => {
            emit_conversion_event(
                Some(&progress_sink),
                &ConversionEvent::progress(
                    0,
                    1,
                    request.input_path.clone(),
                    Some(0.0),
                    Some(0),
                    None,
                    Some("Starting conversion".to_string()),
                ),
            );
            match transcode_impl(&request, Some(&progress_sink)) {
                Ok(result) => result,
                Err(error) => failure_result(
                    &request,
                    "transcode_failed",
                    error.error_message,
                    error.raw_log,
                ),
            }
        }
        Err(error) => invalid_request_result(error.to_string()),
    };

    if result.success {
        emit_conversion_event(
            Some(&progress_sink),
            &ConversionEvent::progress(
                1,
                1,
                result.output_path.clone().unwrap_or_default(),
                Some(1.0),
                None,
                None,
                Some("Completed".to_string()),
            ),
        );
    }

    emit_conversion_event(Some(&progress_sink), &ConversionEvent::result(result));
}

#[frb(sync)]
pub fn get_capabilities() -> String {
    #[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
    let capabilities = AndroidConverterCapabilities {
        engine: "rust-ffmpeg".to_string(),
        supported_output_formats: supported_output_formats(),
        supports_progress: true,
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
