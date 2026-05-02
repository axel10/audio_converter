import 'dart:io' show Platform;

import 'package:audio_converter/audio_converter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

void main() {
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
  final TextEditingController _bitRateController =
      TextEditingController(text: '192000');
  final TextEditingController _ffmpegPathController = TextEditingController();

  ConverterCapabilities? _capabilities;
  AudioFormat? _selectedFormat;
  BitRateMode _bitRateMode = BitRateMode.cbr;
  String? _inputPath;
  String? _outputDirectory;
  String? _outputPath;
  ConvertResult? _lastResult;
  String _permissionStatus = 'Permission not requested yet.';
  String _status = 'Ready.';
  bool _loadingCapabilities = true;
  bool _isConverting = false;
  bool _usingDefaultFfmpegPath = true;

  @override
  void initState() {
    super.initState();
    _converter = widget.converter ?? AudioConverter();
    _loadCapabilities();
    _requestPermissionsOnStart();
  }

  @override
  void dispose() {
    _bitRateController.dispose();
    _ffmpegPathController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionsOnStart() async {
    if (!Platform.isAndroid) {
      if (!mounted) return;
      setState(() {
        _permissionStatus = 'No runtime storage permission is required on this platform.';
      });
      return;
    }

    final statuses = await Future.wait<PermissionStatus>(<Future<PermissionStatus>>[
      Permission.storage.request(),
      Permission.audio.request(),
    ]);
    if (!mounted) return;
    setState(() {
      _permissionStatus = _describePermissionStatus(statuses);
    });
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) {
      setState(() {
        _permissionStatus = 'No runtime storage permission is required on this platform.';
      });
      return;
    }

    final statuses = await Future.wait<PermissionStatus>(<Future<PermissionStatus>>[
      Permission.storage.request(),
      Permission.audio.request(),
    ]);
    if (!mounted) return;
    setState(() {
      _permissionStatus = _describePermissionStatus(statuses);
    });
  }

  String _describePermissionStatus(List<PermissionStatus> statuses) {
    final granted = statuses.any((status) => status.isGranted || status.isLimited);
    if (granted) {
      return 'Read/write access granted for audio files.';
    }

    if (statuses.any((status) => status.isPermanentlyDenied)) {
      return 'Permission permanently denied. Open app settings to enable file access.';
    }

    if (statuses.any((status) => status.isRestricted)) {
      return 'Permission is restricted on this device.';
    }

    return 'Permission denied.';
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  Future<void> _loadCapabilities() async {
    setState(() {
      _loadingCapabilities = true;
    });

    try {
      final capabilities = await _converter.getCapabilities();
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _selectedFormat = _selectedFormat ??
            (capabilities.supportedOutputFormats.isNotEmpty
                ? capabilities.supportedOutputFormats.first
                : AudioFormat.m4a);
        _loadingCapabilities = false;
        _status = 'Capabilities loaded for ${capabilities.engine}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCapabilities = false;
        _status = 'Failed to load capabilities.';
        _capabilities = null;
      });
    }
  }

  List<AudioFormat> get _formatOptions {
    final capabilities = _capabilities;
    if (capabilities == null || capabilities.supportedOutputFormats.isEmpty) {
      return AudioFormat.values;
    }
    return capabilities.supportedOutputFormats;
  }

  Future<void> _pickInputFile() async {
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
    );

    final filePath = result?.files.single.path;
    if (filePath == null || !mounted) {
      return;
    }

    setState(() {
      _inputPath = filePath;
      _status = 'Input file selected.';
      _updateOutputPreview();
    });
  }

  Future<void> _pickOutputDirectory() async {
    final directory = await FilePicker.getDirectoryPath();
    if (directory == null || !mounted) {
      return;
    }

    setState(() {
      _outputDirectory = directory;
      _outputPath = null;
      _status = 'Output directory selected.';
      _updateOutputPreview();
    });
  }

  Future<void> _pickOutputFileSaf() async {
    final inputPath = _inputPath;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || selectedFormat == null) {
      setState(() {
        _status = 'Pick an input file and output format first.';
      });
      return;
    }

    final baseName = p.basenameWithoutExtension(inputPath);
    final suggestedFileName = '$baseName.${selectedFormat.value}';
    final outputPath = await _converter.pickOutputFile(
      format: selectedFormat,
      suggestedFileName: suggestedFileName,
    );
    if (outputPath == null || !mounted) {
      return;
    }

    setState(() {
      _outputPath = outputPath;
      _status = 'Output file selected.';
    });
  }

  void _updateOutputPreview() {
    if (Platform.isAndroid) {
      return;
    }

    final inputPath = _inputPath;
    final outputDirectory = _outputDirectory;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || outputDirectory == null || selectedFormat == null) {
      _outputPath = null;
      return;
    }

    final baseName = p.basenameWithoutExtension(inputPath);
    _outputPath = p.join(outputDirectory, '$baseName.${selectedFormat.value}');
  }

  String? get _previewOutputPath {
    if (Platform.isAndroid) {
      return _outputPath;
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
      _updateOutputPreview();
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
    final outputPath = _outputPath;
    final selectedFormat = _selectedFormat;
    if (inputPath == null || outputPath == null || selectedFormat == null) {
      setState(() {
        _status = 'Please pick an input file and output location first.';
      });
      return;
    }

    final bitRate = int.tryParse(_bitRateController.text.trim());
    final request = ConvertRequest(
      inputPath: inputPath,
      outputPath: outputPath,
      outputFormat: selectedFormat,
      bitRate: bitRate,
      bitRateMode: _bitRateMode,
      ffmpegPath: _usingDefaultFfmpegPath
          ? null
          : _ffmpegPathController.text.trim().isEmpty
              ? null
              : _ffmpegPathController.text.trim(),
    );

    setState(() {
      _isConverting = true;
      _status = 'Converting...';
    });

    try {
      final result = await _converter.convertFile(request);
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _lastResult = result;
        _status = result.success
            ? 'Converted successfully with ${result.engine}.'
            : 'Conversion failed. Check the log below for details.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _lastResult = null;
        _status = 'Conversion threw an exception: $error';
      });
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
                if (Platform.isAndroid)
                  FilledButton.icon(
                    onPressed: _pickOutputFileSaf,
                    icon: const Icon(Icons.save),
                    label: const Text('Choose output file'),
                  )
                else
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
                  ? 'Output file: ${_previewOutputPath ?? 'Not selected'}'
                  : 'Output folder: ${_outputPath ?? 'Not selected'}',
            ),
            const SizedBox(height: 4),
            if (!Platform.isAndroid)
              SelectableText('Output file: ${_previewOutputPath ?? 'Not ready'}'),
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
            const SizedBox(height: 12),
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
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
                TextField(
                  controller: _ffmpegPathController,
                  decoration: const InputDecoration(
                    labelText: 'ffmpeg path',
                    border: OutlineInputBorder(),
                    hintText: '/usr/local/bin/ffmpeg',
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
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

  Widget _buildPermissionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Permissions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(_permissionStatus),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _requestPermissions,
                  icon: const Icon(Icons.security),
                  label: const Text('Request read/write access'),
                ),
                OutlinedButton.icon(
                  onPressed: _openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open app settings'),
                ),
              ],
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
            Text('Requires external binary: ${capabilities.requiresExternalBinary}'),
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
    if (result == null) {
      return const SizedBox.shrink();
    }

    final log = result.rawLog ?? 'No log captured.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Result',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Success: ${result.success}'),
            if (result.command != null) Text('Command: ${result.command}'),
            if (result.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text('Error: ${result.errorMessage}'),
            ],
            const SizedBox(height: 8),
            SelectableText(log),
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
          _buildPermissionCard(),
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
