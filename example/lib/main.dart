import 'dart:io';

import 'package:audio_converter/audio_converter.dart';
import 'package:file_picker/file_picker.dart';
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

  ConverterCapabilities? _capabilities;
  AudioFormat? _selectedFormat;
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
        _capabilities = capabilities;
        _selectedFormat = supportedFormats.contains(_selectedFormat)
            ? _selectedFormat
            : (supportedFormats.isNotEmpty
                  ? supportedFormats.first
                  : AudioFormat.m4a);
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
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
      allowMultiple: false,
      withData: false,
    );

    final filePath = result?.files.single.path;
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
    final directory = await FilePicker.getDirectoryPath();
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

  Future<void> _convert() async {
    final inputPath = _inputPath;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || selectedFormat == null) {
      setState(() {
        _status = 'Please pick an input file and output location first.';
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

    if (Platform.isIOS) {
      _refreshOutputPreview();
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
    );

    setState(() {
      _isConverting = true;
      _status = Platform.isAndroid || Platform.isIOS
          ? 'Converting to a temporary file, then a save dialog will open...'
          : 'Converting...';
    });
    final conversionLog = Platform.isIOS || Platform.isMacOS
        ? 'Starting conversion: input=$inputPath, output=$outputPath, format=${selectedFormat.value}, bitRate=$bitRate, bitRateMode=${_bitRateMode.value}, engine=rust-ffmpeg+Apple encoder for m4a'
        : 'Starting conversion: input=$inputPath, output=$outputPath, format=${selectedFormat.value}, bitRate=$bitRate, bitRateMode=${_bitRateMode.value}, ffmpegPath=${request.ffmpegPath ?? "default"}';
    _log(conversionLog);

    try {
      final result = await _converter.convertFile(request);
      if (!mounted) return;
      _log(
        'Conversion completed: success=${result.success}, engine=${result.engine}, outputPath=${result.outputPath}, errorCode=${result.errorCode}, errorMessage=${result.errorMessage}',
      );

      if (!result.success) {
        setState(() {
          _isConverting = false;
          _lastResult = result;
          _status = 'Conversion failed. Check the log below for details.';
        });
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final tempPath = result.outputPath ?? outputPath;
        final tempFile = File(tempPath);
        if (!await tempFile.exists()) {
          setState(() {
            _isConverting = false;
            _lastResult = result;
            _status =
                'Conversion finished, but the temporary output file was not found.';
          });
          return;
        }

        final bytes = await tempFile.readAsBytes();
        final suggestedFileName = '$baseName.${selectedFormat.value}';
        final savedPath = await FilePicker.saveFile(
          fileName: suggestedFileName,
          type: FileType.custom,
          allowedExtensions: <String>[selectedFormat.value],
          bytes: bytes,
        );

        if (!mounted) {
          return;
        }

        try {
          await tempFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }

        setState(() {
          _isConverting = false;
          _lastResult = result;
          if (savedPath == null) {
            _status = Platform.isAndroid
                ? 'Conversion finished, but the SAF save dialog was cancelled.'
                : 'Conversion finished, but the save dialog was cancelled.';
            _log(
              Platform.isAndroid
                  ? 'SAF save dialog was cancelled.'
                  : 'iOS save dialog was cancelled.',
            );
            return;
          }
          _savedOutputPath = savedPath;
          _outputPath = tempPath;
          _status = Platform.isAndroid
              ? 'Converted successfully and saved via SAF.'
              : 'Converted successfully and saved.';
        });
        _log(
          Platform.isAndroid
              ? 'Converted file saved via SAF: $savedPath'
              : 'Converted file saved via iOS save dialog: $savedPath',
        );
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
                  ? 'Android uses SAF to save after conversion.'
                  : Platform.isIOS
                  ? 'iOS writes to the app temp directory first, then opens a save dialog.'
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
              'Input files are picked through SAF, and the save dialog appears after conversion.',
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
