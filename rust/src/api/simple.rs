use flutter_rust_bridge::frb;
use serde_json;

use super::apple;
use super::formats::{
    capabilities_notes, supported_output_formats, unsupported_output_format_error,
};
use super::models::{
    failure_result, AndroidConvertRequest, AndroidConvertResult, AndroidConverterCapabilities,
    ConversionFailure,
};
use super::transcoder::transcode_direct;

fn transcode(request: &AndroidConvertRequest) -> Result<AndroidConvertResult, ConversionFailure> {
    if let Some(message) = unsupported_output_format_error(request) {
        return Err(ConversionFailure::new(message));
    }

    if apple::should_use_apple_m4a_encoder(request) {
        return apple::transcode_apple_m4a(request);
    }

    transcode_direct(request)
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

#[frb(sync)]
pub fn get_capabilities() -> String {
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

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
