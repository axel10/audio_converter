import 'audio_format.dart';

class ConvertResult {
  const ConvertResult({
    required this.success,
    this.command,
    this.outputPath,
    this.engine,
    this.outputFormat,
    this.errorCode,
    this.errorMessage,
    this.stdout,
    this.stderr,
    this.rawLog,
  });

  final bool success;
  final String? command;
  final String? outputPath;
  final String? engine;
  final AudioFormat? outputFormat;
  final String? errorCode;
  final String? errorMessage;
  final String? stdout;
  final String? stderr;
  final String? rawLog;

  ConvertResult copyWith({
    bool? success,
    String? command,
    String? outputPath,
    String? engine,
    AudioFormat? outputFormat,
    String? errorCode,
    String? errorMessage,
    String? stdout,
    String? stderr,
    String? rawLog,
  }) {
    return ConvertResult(
      success: success ?? this.success,
      command: command ?? this.command,
      outputPath: outputPath ?? this.outputPath,
      engine: engine ?? this.engine,
      outputFormat: outputFormat ?? this.outputFormat,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      rawLog: rawLog ?? this.rawLog,
    );
  }

  factory ConvertResult.fromMap(Map<Object?, Object?> map) {
    final outputFormatValue = map['outputFormat'] ?? map['output_format'];
    return ConvertResult(
      success: map['success'] as bool? ?? false,
      command: map['command'] as String?,
      outputPath: (map['outputPath'] ?? map['output_path']) as String?,
      engine: map['engine'] as String?,
      outputFormat: outputFormatValue == null
          ? null
          : audioFormatFromValue(outputFormatValue as String),
      errorCode: (map['errorCode'] ?? map['error_code']) as String?,
      errorMessage: (map['errorMessage'] ?? map['error_message']) as String?,
      stdout: map['stdout'] as String?,
      stderr: map['stderr'] as String?,
      rawLog: (map['rawLog'] ?? map['raw_log']) as String?,
    );
  }
}
