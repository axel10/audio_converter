use std::collections::HashMap;

use crate::frb_generated::StreamSink;
use serde::{Deserialize, Serialize};

fn normalize_output_format(value: &str) -> String {
    value.trim().to_lowercase()
}

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

#[derive(Clone, Debug, Serialize)]
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

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ConversionProgressEvent {
    pub completed_files: usize,
    pub total_files: usize,
    pub current_file_path: String,
    pub current_file_progress: Option<f64>,
    pub current_position_us: Option<i64>,
    pub total_duration_us: Option<i64>,
    pub message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(crate) enum ConversionEvent {
    Progress {
        completed_files: usize,
        total_files: usize,
        current_file_path: String,
        current_file_progress: Option<f64>,
        current_position_us: Option<i64>,
        total_duration_us: Option<i64>,
        message: Option<String>,
    },
    Result {
        result: AndroidConvertResult,
    },
}

impl ConversionEvent {
    pub(crate) fn progress(
        completed_files: usize,
        total_files: usize,
        current_file_path: impl Into<String>,
        current_file_progress: Option<f64>,
        current_position_us: Option<i64>,
        total_duration_us: Option<i64>,
        message: Option<String>,
    ) -> Self {
        Self::Progress {
            completed_files,
            total_files,
            current_file_path: current_file_path.into(),
            current_file_progress,
            current_position_us,
            total_duration_us,
            message,
        }
    }

    pub(crate) fn result(result: AndroidConvertResult) -> Self {
        Self::Result { result }
    }
}

pub(crate) fn emit_conversion_event(sink: Option<&StreamSink<String>>, event: &ConversionEvent) {
    let Some(sink) = sink else {
        return;
    };

    if let Ok(payload) = serde_json::to_string(event) {
        let _ = sink.add(payload);
    }
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
        output_format: Some(normalize_output_format(&request.output_format)),
        error_code: Some(error_code.to_string()),
        error_message: Some(error_message),
        stdout: None,
        stderr: None,
        raw_log,
    }
}
