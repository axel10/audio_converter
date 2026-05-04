import 'dart:io';

import 'package:audio_converter/audio_converter.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.converter});

  final AudioConverter? converter;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E4D8C),
        useMaterial3: true,
      ),
      home: AudioConverterDemoPage(converter: converter),
    );
  }
}

class AudioConverterDemoPage extends StatefulWidget {
  const AudioConverterDemoPage({super.key, this.converter});

  final AudioConverter? converter;

  @override
  State<AudioConverterDemoPage> createState() => _AudioConverterDemoPageState();
}

class _AudioConverterDemoPageState extends State<AudioConverterDemoPage> {
  late final AudioConverter _converter;
  final TextEditingController _bitRateController = TextEditingController(
    text: '192000',
  );
  final TextEditingController _ffmpegPathController = TextEditingController();
  final TextEditingController _customArgsController = TextEditingController();

  ConverterCapabilities? _capabilities;
  AudioFormat? _selectedFormat;
  AacEncoder _aacEncoder = Platform.isWindows || Platform.isLinux
      ? AacEncoder.fdkaac
      : AacEncoder.builtinAac;
  BitRateMode _bitRateMode = BitRateMode.cbr;
  String? _inputPath;
  List<String> _inputPaths = <String>[];
  String? _outputDirectory;
  AndroidOutputDirectory? _androidOutputDirectory;
  ConvertResult? _lastResult;
  final List<String> _logEntries = <String>[];
  String _status = 'Ready.';
  bool _loadingCapabilities = true;
  bool _isBatchConverting = false;
  bool _usingDefaultFfmpegPath = true;
  ConversionProgress? _conversionProgress;

  @override
  void initState() {
    super.initState();
    _converter = widget.converter ?? AudioConverter();
    _loadCapabilities();
  }

  @override
  void dispose() {
    _bitRateController.dispose();
    _ffmpegPathController.dispose();
    _customArgsController.dispose();
    super.dispose();
  }

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    final buffer = StringBuffer('[audio_converter_demo] $message');
    if (error != null) {
      buffer.write(' | error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }

    final logMessage = buffer.toString();
    debugPrint(logMessage);

    setState(() {
      _logEntries.insert(0, logMessage);
      if (_logEntries.length > 50) {
        _logEntries.removeRange(50, _logEntries.length);
      }
    });
  }

  Future<void> _loadCapabilities() async {
    setState(() {
      _loadingCapabilities = true;
    });
    _log('Loading capabilities...');

    try {
      final capabilities = await _converter.getCapabilities();
      if (!mounted) return;
      setState(() {
        final supportedFormats = capabilities.supportedOutputFormats;
        final supportedEncoders = capabilities.supportedAacEncoders;
        _capabilities = capabilities;
        _selectedFormat = supportedFormats.contains(_selectedFormat)
            ? _selectedFormat
            : (supportedFormats.isNotEmpty
                  ? supportedFormats.first
                  : AudioFormat.m4a);
        _aacEncoder = supportedEncoders.contains(_aacEncoder)
            ? _aacEncoder
            : (supportedEncoders.isNotEmpty
                  ? supportedEncoders.first
                  : AacEncoder.builtinAac);
        _loadingCapabilities = false;
        _status = 'Capabilities loaded for ${capabilities.engine}.';
        _refreshOutputPreview();
      });
      _log(
        'Capabilities loaded: engine=${capabilities.engine}, formats=${capabilities.supportedOutputFormats.map((format) => format.value).join(", ")}',
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _loadingCapabilities = false;
        _capabilities = null;
        _status = 'Failed to load capabilities: $error';
      });
      _log('Failed to load capabilities', error: error, stackTrace: stackTrace);
    }
  }

  List<AudioFormat> get _formatOptions {
    final capabilities = _capabilities;
    if (capabilities == null || capabilities.supportedOutputFormats.isEmpty) {
      if (Platform.isIOS || Platform.isMacOS) {
        return AudioFormat.values
            .where((format) => format != AudioFormat.aac)
            .toList(growable: false);
      }
      return AudioFormat.values;
    }
    return capabilities.supportedOutputFormats;
  }

  Future<void> _pickInputFiles() async {
    _log('Opening multi-file picker...');
    final filePaths = await _converter.pickInputFiles(
      allowedExtensions: <String>[
        'aac',
        'aif',
        'aiff',
        'caf',
        'flac',
        'm4a',
        'm4b',
        'mp3',
        'ogg',
        'opus',
        'wav',
      ],
    );
    if (!mounted) {
      return;
    }

    if (filePaths.isEmpty) {
      setState(() {
        _status =
            'Multi-file selection was cancelled or the picker returned no paths.';
      });
      _log('Multi-file picker was cancelled or returned no paths.');
      return;
    }

    setState(() {
      _inputPaths = filePaths;
      _inputPath = filePaths.first;
      _status = 'Selected ${filePaths.length} input files.';
      _refreshOutputPreview();
    });
    _log('Selected ${filePaths.length} input files.');
  }

  Future<void> _pickOutputDirectory() async {
    _log('Opening output directory picker...');
    if (Platform.isAndroid) {
      final directory = await _converter.pickAndroidOutputDirectory();
      if (directory == null || !mounted) {
        _log('Output directory picker was cancelled or returned no path.');
        return;
      }

      setState(() {
        _androidOutputDirectory = directory;
        _outputDirectory = directory.displayPath;
        _status = 'Output directory selected.';
        _refreshOutputPreview();
      });
      _log(
        'Output directory selected: ${directory.displayPath} (${directory.treeUri})',
      );
      return;
    }

    final directory = await _converter.pickOutputDirectory();
    if (directory == null || !mounted) {
      _log('Output directory picker was cancelled or returned no path.');
      return;
    }

    setState(() {
      _outputDirectory = directory;
      _status = 'Output directory selected.';
      _refreshOutputPreview();
    });
    _log('Output directory selected: $directory');
  }

  void _refreshOutputPreview() {
    // The preview path is derived from state on demand below.
  }

  String? get _previewOutputPath {
    final inputPath =
        _inputPath ?? (_inputPaths.isNotEmpty ? _inputPaths.first : null);
    final outputDirectory = _outputDirectory;
    final selectedFormat = _selectedFormat;
    if (inputPath != null &&
        outputDirectory != null &&
        selectedFormat != null) {
      final baseName = p.basenameWithoutExtension(inputPath);
      return p.join(outputDirectory, '$baseName.${selectedFormat.value}');
    }

    return null;
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '--:--';
    }

    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minuteText:$secondText';
    }

    return '$minutes:$secondText';
  }

  void _handleBatchProgress(ConversionProgress progress) {
    if (!mounted) {
      return;
    }

    final currentFileName = p.basename(progress.currentFilePath);
    final currentPosition = _formatDuration(progress.currentPosition);
    final totalDuration = _formatDuration(progress.totalDuration);
    final currentIndex = progress.currentFileIndex;
    final overallPercent = progress.overallProgress;
    final overallText = overallPercent == null
        ? ''
        : ' ${(overallPercent * 100).clamp(0, 100).toStringAsFixed(1)}%';
    final filePercent = progress.currentFileProgress;
    final filePercentText = filePercent == null
        ? ''
        : ' ${(filePercent * 100).clamp(0, 100).toStringAsFixed(1)}%';

    setState(() {
      _conversionProgress = progress;
      _status =
          progress.message ??
          'Converting $currentIndex/${progress.totalFiles}: $currentFileName'
              '$filePercentText'
              '${progress.currentPosition != null ? ' ($currentPosition / $totalDuration)' : ''}'
              '$overallText';
    });
  }

  List<String> _currentInputPaths() {
    if (_inputPaths.isNotEmpty) {
      return _inputPaths;
    }

    final inputPath = _inputPath;
    return inputPath == null ? const <String>[] : <String>[inputPath];
  }

  void _onFormatChanged(AudioFormat? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _selectedFormat = value;
      _refreshOutputPreview();
    });
  }

  void _onBitRateModeChanged(BitRateMode? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _bitRateMode = value;
    });
  }

  void _onAacEncoderChanged(AacEncoder? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _aacEncoder = value;
    });
  }

  List<String> _parseCustomArgs(String input) {
    final args = <String>[];
    var buffer = StringBuffer();
    var inSingleQuotes = false;
    var inDoubleQuotes = false;
    var escaping = false;

    void flushToken() {
      if (buffer.isEmpty) {
        return;
      }
      args.add(buffer.toString());
      buffer = StringBuffer();
    }

    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);

      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }

      if (char == r'\') {
        escaping = true;
        continue;
      }

      if (char == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
        continue;
      }

      if (char == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
        continue;
      }

      if (char.trim().isEmpty && !inSingleQuotes && !inDoubleQuotes) {
        flushToken();
        continue;
      }

      buffer.write(char);
    }

    if (escaping) {
      buffer.write(r'\');
    }
    flushToken();

    return args;
  }

  bool _usesAacEncoder(AudioFormat format) {
    return switch (format) {
      AudioFormat.aac ||
      AudioFormat.caf ||
      AudioFormat.m4a ||
      AudioFormat.m4b => true,
      _ => false,
    };
  }

  List<ConvertRequest> _buildBatchRequests({
    required List<String> inputPaths,
    required AudioFormat outputFormat,
    required String outputDirectory,
    required int? bitRate,
    required BitRateMode bitRateMode,
    required AacEncoder aacEncoder,
    required String? ffmpegPath,
    required List<String> customArgs,
  }) {
    return inputPaths
        .map(
          (inputPath) => ConvertRequest.forOutputDirectory(
            inputPath: inputPath,
            outputDirectory: outputDirectory,
            outputFormat: outputFormat,
            bitRate: bitRate,
            bitRateMode: bitRateMode,
            ffmpegPath: ffmpegPath,
            aacEncoder: aacEncoder,
            customArgs: customArgs.isEmpty ? null : customArgs,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _convertBatch() async {
    final inputPaths = _currentInputPaths();
    final selectedFormat = _selectedFormat;
    final outputDirectory = _outputDirectory;
    if (inputPaths.isEmpty || selectedFormat == null) {
      setState(() {
        _status = 'Please pick one or more input files first.';
      });
      _log('Batch conversion blocked because input files are missing.');
      return;
    }

    if (outputDirectory == null) {
      setState(() {
        _status = 'Please pick an output directory first.';
      });
      _log('Batch conversion blocked because output directory is missing.');
      return;
    }

    final bitRate = int.tryParse(_bitRateController.text.trim());
    final customArgs = (Platform.isWindows || Platform.isLinux)
        ? _parseCustomArgs(_customArgsController.text.trim())
        : const <String>[];
    final ffmpegPath =
        (Platform.isWindows || Platform.isLinux) && !_usingDefaultFfmpegPath
        ? (_ffmpegPathController.text.trim().isEmpty
              ? null
              : _ffmpegPathController.text.trim())
        : null;
    final requests = _buildBatchRequests(
      inputPaths: inputPaths,
      outputFormat: selectedFormat,
      outputDirectory: outputDirectory,
      bitRate: bitRate,
      bitRateMode: _bitRateMode,
      aacEncoder: _aacEncoder,
      ffmpegPath: ffmpegPath,
      customArgs: customArgs,
    );

    setState(() {
      _isBatchConverting = true;
      _status = 'Batch converting ${requests.length} files...';
      _lastResult = null;
      _conversionProgress = null;
    });
    _log(
      'Starting batch conversion: count=${requests.length}, outputDirectory=$outputDirectory, firstOutputPath=${requests.isNotEmpty ? requests.first.outputPath : 'n/a'}, format=${selectedFormat.value}',
    );

    try {
      if (Platform.isAndroid && _androidOutputDirectory != null) {
        final results = <ConvertAndSaveResult>[];
        for (final request in requests) {
          final result = await _converter.convertAndSaveToAndroidDirectory(
            request,
            _androidOutputDirectory!,
            onProgress: _handleBatchProgress,
          );
          results.add(result);
        }
        if (!mounted) return;

        final successCount = results.where((result) => result.success).length;
        final failureCount = results.length - successCount;
        setState(() {
          _isBatchConverting = false;
          _status = failureCount == 0
              ? 'Batch conversion completed successfully.'
              : 'Batch conversion finished with $successCount success(es) and $failureCount failure(s).';
          _lastResult = results.isEmpty
              ? null
              : results.last.conversionResult.copyWith(
                  outputPath: results.last.outputPath,
                );
          _conversionProgress = results.isEmpty ? null : _conversionProgress;
        });
        _log(
          'Batch conversion completed: total=${results.length}, success=$successCount, failure=$failureCount',
        );
      } else {
        final results = await _converter.convertFiles(
          requests,
          onProgress: _handleBatchProgress,
        );
        if (!mounted) return;

        final successCount = results.where((result) => result.success).length;
        final failureCount = results.length - successCount;
        setState(() {
          _isBatchConverting = false;
          _status = failureCount == 0
              ? 'Batch conversion completed successfully.'
              : 'Batch conversion finished with $successCount success(es) and $failureCount failure(s).';
          _lastResult = results.isEmpty ? null : results.last;
          _conversionProgress = results.isEmpty ? null : _conversionProgress;
        });
        _log(
          'Batch conversion completed: total=${results.length}, success=$successCount, failure=$failureCount',
        );
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _isBatchConverting = false;
        _status = 'Batch conversion threw an exception: $error';
      });
      _log(
        'Batch conversion threw an exception',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Widget _buildPickerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Files', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _pickInputFiles,
                  icon: const Icon(Icons.library_music),
                  label: const Text('Choose input files'),
                ),
                FilledButton.icon(
                  onPressed: _pickOutputDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose output directory'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              _inputPaths.isNotEmpty
                  ? 'Inputs (${_inputPaths.length}): ${_inputPaths.join(', ')}'
                  : 'Inputs: Not selected',
            ),
            const SizedBox(height: 4),
            SelectableText(
              'Output directory: ${_outputDirectory ?? 'Not selected'}',
            ),
            const SizedBox(height: 4),
            SelectableText('Output file: ${_previewOutputPath ?? 'Not ready'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    final formats = _formatOptions;
    final selectedFormat = _selectedFormat ?? formats.first;
    final supportedEncoders =
        _capabilities?.supportedAacEncoders ??
        (Platform.isWindows || Platform.isLinux
            ? const <AacEncoder>[AacEncoder.fdkaac, AacEncoder.builtinAac]
            : const <AacEncoder>[]);
    final canChooseAacEncoder =
        supportedEncoders.isNotEmpty &&
        (Platform.isWindows || Platform.isLinux) &&
        _usesAacEncoder(selectedFormat);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Encoding', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<AudioFormat>(
              initialValue: selectedFormat,
              items: formats
                  .map(
                    (format) => DropdownMenuItem<AudioFormat>(
                      value: format,
                      child: Text(format.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _onFormatChanged,
              decoration: const InputDecoration(
                labelText: 'Output format',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bitRateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Bit rate (bps)',
                border: OutlineInputBorder(),
                hintText: 'For example 192000',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BitRateMode>(
              initialValue: _bitRateMode,
              items: BitRateMode.values
                  .map(
                    (mode) => DropdownMenuItem<BitRateMode>(
                      value: mode,
                      child: Text(mode.value.toUpperCase()),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _onBitRateModeChanged,
              decoration: const InputDecoration(
                labelText: 'Bit rate mode',
                border: OutlineInputBorder(),
              ),
            ),
            if (canChooseAacEncoder) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<AacEncoder>(
                initialValue: _aacEncoder,
                items: supportedEncoders
                    .map(
                      (encoder) => DropdownMenuItem<AacEncoder>(
                        value: encoder,
                        child: Text(encoder.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _onAacEncoderChanged,
                decoration: const InputDecoration(
                  labelText: 'AAC encoder',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (Platform.isWindows || Platform.isLinux) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _usingDefaultFfmpegPath,
                onChanged: (value) {
                  setState(() {
                    _usingDefaultFfmpegPath = value;
                  });
                },
                title: const Text('Use default ffmpeg path'),
              ),
              if (!_usingDefaultFfmpegPath) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _ffmpegPathController,
                  decoration: const InputDecoration(
                    labelText: 'ffmpeg path',
                    border: OutlineInputBorder(),
                    hintText: '/usr/local/bin/ffmpeg',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _customArgsController,
                decoration: const InputDecoration(
                  labelText: 'Custom ffmpeg args',
                  border: OutlineInputBorder(),
                  hintText: '-vn -map 0:a:0',
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              const Text(
                'Arguments are appended to ffmpeg on Windows/Linux. Use spaces and quotes, for example: -vn or -metadata title="Demo".',
              ),
            ] else if (Platform.isIOS || Platform.isMacOS) ...[
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Apple M4A encoder'),
                subtitle: Text(
                  'M4A uses a WAV intermediate; AAC container output is unavailable here.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isBatchConverting ? null : _convertBatch,
                  icon: const Icon(Icons.playlist_play),
                  label: Text(
                    _isBatchConverting
                        ? 'Batch converting...'
                        : 'Start batch conversion',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafCard() {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Android SAF', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Android does not request broad storage permission here. '
              'On Android, conversion writes to the app temporary directory first and then exports into the SAF-selected folder.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard() {
    final capabilities = _capabilities;
    if (_loadingCapabilities) {
      return const Center(child: CircularProgressIndicator());
    }

    if (capabilities == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load capabilities.\n$_status'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capabilities',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Engine: ${capabilities.engine}'),
            Text(
              'Requires external binary: ${capabilities.requiresExternalBinary}',
            ),
            Text('Supports progress: ${capabilities.supportsProgress}'),
            Text('Supports cancellation: ${capabilities.supportsCancellation}'),
            Text(
              'Supported AAC encoders: ${capabilities.supportedAacEncoders.isEmpty ? "n/a" : capabilities.supportedAacEncoders.map((encoder) => encoder.label).join(", ")}',
            ),
            if (capabilities.notes != null) ...[
              const SizedBox(height: 8),
              Text(capabilities.notes!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: capabilities.supportedOutputFormats
                  .map((format) => Chip(label: Text(format.value)))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    final result = _lastResult;
    final hasResult = result != null;
    final hasLogs = _logEntries.isNotEmpty;
    debugPrint("raw log: ${result?.rawLog}");
    if (!hasResult && !hasLogs) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last Result', style: Theme.of(context).textTheme.titleMedium),
            if (hasResult) ...[
              const SizedBox(height: 8),
              Text('Success: ${result.success}'),
              if (result.command != null) Text('Command: ${result.command}'),
              if (result.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text('Error: ${result.errorMessage}'),
              ],
              const SizedBox(height: 8),
              SelectableText(result.rawLog ?? 'No log captured.'),
            ],
            if (hasLogs) ...[
              if (hasResult) const SizedBox(height: 12),
              Text(
                'Runtime Log',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(_logEntries.join('\n\n')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final progress = _conversionProgress;
    if (progress == null && !_isBatchConverting) {
      return const SizedBox.shrink();
    }

    final currentFileName = progress == null
        ? 'Not started'
        : p.basename(progress.currentFilePath);
    final currentPosition = progress == null
        ? null
        : _formatDuration(progress.currentPosition);
    final totalDuration = progress == null
        ? null
        : _formatDuration(progress.totalDuration);
    final currentFilePercent = progress?.currentFileProgress == null
        ? null
        : (progress!.currentFileProgress! * 100)
              .clamp(0, 100)
              .toStringAsFixed(1);
    final currentStage = progress?.message;
    final currentFileValue = progress?.currentFileProgress;
    final overallValue = progress?.overallProgress;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? 'Waiting for the next batch.'
                  : 'File ${progress.currentFileIndex}/${progress.totalFiles}: $currentFileName',
            ),
            if (currentStage != null) ...[
              const SizedBox(height: 4),
              Text('Stage: $currentStage'),
            ],
            if (currentFilePercent != null) ...[
              const SizedBox(height: 4),
              Text('Song progress: $currentFilePercent%'),
            ],
            if (progress != null && progress.currentPosition != null) ...[
              const SizedBox(height: 4),
              Text('Song position: $currentPosition / $totalDuration'),
            ],
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: currentFileValue, minHeight: 8),
              const SizedBox(height: 4),
              Text(
                currentFileValue == null
                    ? 'Song progress: calculating'
                    : 'Song progress bar: ${(currentFileValue * 100).clamp(0, 100).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: overallValue, minHeight: 8),
              const SizedBox(height: 4),
              Text(
                overallValue == null
                    ? 'Overall: calculating'
                    : 'Overall: ${(overallValue * 100).clamp(0, 100).toStringAsFixed(1)}%',
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Converter Demo'),
        actions: [
          IconButton(
            onPressed: _loadCapabilities,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Convert local audio files with platform-native encoders where available.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _buildSafCard(),
          const SizedBox(height: 12),
          _buildPickerCard(),
          const SizedBox(height: 12),
          _buildSettingsCard(),
          const SizedBox(height: 12),
          _buildCapabilitiesCard(),
          const SizedBox(height: 12),
          _buildProgressCard(),
          const SizedBox(height: 12),
          _buildLogCard(),
          const SizedBox(height: 12),
          SelectableText('Status: $_status'),
        ],
      ),
    );
  }
}
