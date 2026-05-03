use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use super::formats::output_format_key;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AndroidConvertRequest {
    pub input_path: String,
    pub output_path: String,
    pub output_format: String,
    pub sample_rate: Option<u32>,
    pub channels: Option<u16>,
    pub bit_rate: Option<u32>,
    pub bit_rate_mode: Option<String>,
    pub ffmpeg_path: Option<String>,
    pub allow_fallback_to_ffmpeg: Option<bool>,
    pub extra_options: Option<HashMap<String, String>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AndroidConvertResult {
    pub success: bool,
    pub command: Option<String>,
    pub output_path: Option<String>,
    pub engine: Option<String>,
    pub output_format: Option<String>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub stdout: Option<String>,
    pub stderr: Option<String>,
    pub raw_log: Option<String>,
}

#[derive(Debug)]
pub(crate) struct ConversionFailure {
    pub error_message: String,
    pub raw_log: Option<String>,
}

impl ConversionFailure {
    pub(crate) fn new(error_message: impl Into<String>) -> Self {
        Self {
            error_message: error_message.into(),
            raw_log: None,
        }
    }

    pub(crate) fn with_log(error_message: impl Into<String>, raw_log: impl Into<String>) -> Self {
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
pub(crate) struct AndroidConverterCapabilities {
    pub engine: String,
    pub supported_output_formats: Vec<String>,
    pub supports_progress: bool,
    pub supports_cancellation: bool,
    pub requires_external_binary: bool,
    pub notes: Option<String>,
}

pub(crate) fn failure_result(
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
