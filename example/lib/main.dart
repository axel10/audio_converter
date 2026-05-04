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
  String? _outputDirectory;
  String? _outputPath;
  String? _savedOutputPath;
  ConvertResult? _lastResult;
  final List<String> _logEntries = <String>[];
  String _status = 'Ready.';
  bool _loadingCapabilities = true;
  bool _isConverting = false;
  bool _usingDefaultFfmpegPath = true;

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

  Future<void> _pickInputFile() async {
    _log('Opening input file picker...');
    final filePath = await _converter.pickInputFile(
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

    if (filePath == null) {
      setState(() {
        _status =
            'Input file selection was cancelled or the picker returned no path.';
      });
      _log('Input file picker was cancelled or returned no path.');
      return;
    }

    setState(() {
      _inputPath = filePath;
      _savedOutputPath = null;
      _status = 'Input file selected.';
      _refreshOutputPreview();
    });
    _log('Input file selected: $filePath');
  }

  Future<void> _pickOutputDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }

    _log('Opening output directory picker...');
    final directory = await _converter.pickOutputDirectory();
    if (directory == null || !mounted) {
      _log('Output directory picker was cancelled or returned no path.');
      return;
    }

    setState(() {
      _outputDirectory = directory;
      _outputPath = null;
      _savedOutputPath = null;
      _status = 'Output directory selected.';
      _refreshOutputPreview();
    });
    _log('Output directory selected: $directory');
  }

  void _refreshOutputPreview() {
    final inputPath = _inputPath;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || selectedFormat == null) {
      _outputPath = null;
      return;
    }

    final baseName = p.basenameWithoutExtension(inputPath);
    if (Platform.isAndroid || Platform.isIOS) {
      final tempDir = Directory(
        p.join(Directory.systemTemp.path, 'audio_converter'),
      );
      _outputPath = p.join(tempDir.path, '$baseName.${selectedFormat.value}');
      return;
    }

    final outputDirectory = _outputDirectory;
    if (outputDirectory == null) {
      _outputPath = null;
      return;
    }

    _outputPath = p.join(outputDirectory, '$baseName.${selectedFormat.value}');
  }

  String? get _previewOutputPath {
    if (Platform.isAndroid || Platform.isIOS) {
      return _savedOutputPath ?? _outputPath;
    }

    final inputPath = _inputPath;
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

  void _onFormatChanged(AudioFormat? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _selectedFormat = value;
      _savedOutputPath = null;
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

  Future<void> _convert() async {
    final inputPath = _inputPath;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || selectedFormat == null) {
      setState(() {
        _status = 'Please pick an input file first.';
      });
      _log(
        'Conversion blocked because input file or output format is missing.',
      );
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS && _outputDirectory == null) {
      setState(() {
        _status = 'Please pick an output directory first.';
      });
      _log('Conversion blocked because output directory is missing.');
      return;
    }

    final outputPath = _outputPath;
    if (outputPath == null) {
      setState(() {
        _status = 'Output path is not ready yet.';
      });
      _log('Conversion blocked because output path could not be resolved.');
      return;
    }

    final baseName = p.basenameWithoutExtension(inputPath);
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
    final request = ConvertRequest(
      inputPath: inputPath,
      outputPath: outputPath,
      outputFormat: selectedFormat,
      bitRate: bitRate,
      bitRateMode: _bitRateMode,
      ffmpegPath: ffmpegPath,
      aacEncoder: _aacEncoder,
      customArgs: customArgs.isEmpty ? null : customArgs,
    );

    setState(() {
      _isConverting = true;
      _status = Platform.isAndroid || Platform.isIOS
          ? 'Converting and opening the system save dialog...'
          : 'Converting...';
    });
    final conversionLog = Platform.isIOS || Platform.isMacOS
        ? 'Starting conversion: input=$inputPath, output=$outputPath, format=${selectedFormat.value}, bitRate=$bitRate, bitRateMode=${_bitRateMode.value}, engine=rust-ffmpeg+Apple encoder for m4a'
        : 'Starting conversion: input=$inputPath, output=$outputPath, format=${selectedFormat.value}, bitRate=$bitRate, bitRateMode=${_bitRateMode.value}, aacEncoder=${_aacEncoder.value}, ffmpegPath=${request.ffmpegPath ?? "default"}, customArgs=${customArgs.isEmpty ? "[]" : customArgs.join(" ")}';
    _log(conversionLog);

    try {
      final managedResult = Platform.isAndroid || Platform.isIOS
          ? await _converter.convertAndSave(
              request,
              suggestedFileName: '$baseName.${selectedFormat.value}',
            )
          : ConvertAndSaveResult(
              conversionResult: await _converter.convertFile(request),
              savedPath: request.outputPath,
            );
      final result = managedResult.conversionResult;
      if (!mounted) return;
      _log(
        'Conversion completed: success=${result.success}, engine=${result.engine}, outputPath=${result.outputPath}, errorCode=${result.errorCode}, errorMessage=${result.errorMessage}',
      );

      if (!result.success) {
        setState(() {
          _isConverting = false;
          _lastResult = result;
          _status = managedResult.saveCancelled
              ? 'Conversion finished, but the save dialog was cancelled.'
              : 'Conversion failed. Check the log below for details.';
        });
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        setState(() {
          _isConverting = false;
          _lastResult = result;
          if (managedResult.savedPath == null) {
            _savedOutputPath = null;
            _outputPath = null;
            _status = Platform.isAndroid
                ? 'Conversion finished, but the SAF save dialog was cancelled.'
                : 'Conversion finished, but the save dialog was cancelled.';
          } else {
            _savedOutputPath = managedResult.savedPath;
            _outputPath = managedResult.outputPath;
            _status = Platform.isAndroid
                ? 'Converted successfully and saved via SAF.'
                : 'Converted successfully and saved.';
          }
        });
        if (managedResult.savedPath == null) {
          _log(
            Platform.isAndroid
                ? 'SAF save dialog was cancelled.'
                : 'iOS save dialog was cancelled.',
          );
        } else {
          _log(
            Platform.isAndroid
                ? 'Converted file saved via SAF: ${managedResult.savedPath}'
                : 'Converted file saved via iOS save dialog: ${managedResult.savedPath}',
          );
        }
        return;
      }

      setState(() {
        _isConverting = false;
        _lastResult = result;
        _status = 'Converted successfully with ${result.engine}.';
      });
      _log('Conversion succeeded with engine=${result.engine}.');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _lastResult = null;
        _status = 'Conversion threw an exception: $error';
      });
      _log(
        'Conversion threw an exception',
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
                  onPressed: _pickInputFile,
                  icon: const Icon(Icons.audio_file),
                  label: const Text('Choose input file'),
                ),
                if (!Platform.isAndroid && !Platform.isIOS)
                  FilledButton.icon(
                    onPressed: _pickOutputDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose output directory'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('Input: ${_inputPath ?? 'Not selected'}'),
            const SizedBox(height: 4),
            SelectableText(
              Platform.isAndroid
                  ? 'Android and iOS save handling is managed by the plugin.'
                  : Platform.isIOS
                  ? 'iOS save handling is managed by the plugin.'
                  : 'Output directory: ${_outputDirectory ?? 'Not selected'}',
            ),
            const SizedBox(height: 4),
            SelectableText(
              Platform.isAndroid || Platform.isIOS
                  ? 'Temporary output: ${_outputPath ?? 'Not ready'}'
                  : 'Output file: ${_previewOutputPath ?? 'Not ready'}',
            ),
            if ((Platform.isAndroid || Platform.isIOS) &&
                _savedOutputPath != null) ...[
              const SizedBox(height: 4),
              SelectableText('Saved output: $_savedOutputPath'),
            ],
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
            FilledButton.icon(
              onPressed: _isConverting ? null : _convert,
              icon: const Icon(Icons.play_arrow),
              label: Text(_isConverting ? 'Converting...' : 'Start conversion'),
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
              'The plugin handles the input picker and the save dialog internally.',
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
    debugPrint(result?.rawLog);
    final hasResult = result != null;
    final hasLogs = _logEntries.isNotEmpty;
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
          _buildLogCard(),
          const SizedBox(height: 12),
          SelectableText('Status: $_status'),
        ],
      ),
    );
  }
}
