library;

import 'src/desktop_audio_converter.dart';
import 'src/models/convert_request.dart';
import 'src/models/convert_result.dart';
import 'src/models/converter_capabilities.dart';
export 'src/models/audio_format.dart';
export 'src/models/aac_encoder.dart';
export 'src/models/bit_rate_mode.dart';
export 'src/models/convert_request.dart';
export 'src/models/convert_result.dart';
export 'src/models/converter_capabilities.dart';
export 'src/rust/api/simple.dart';
export 'src/rust/frb_generated.dart' show RustLib;

class AudioConverter {
  AudioConverter({DesktopAudioConverter? desktopConverter})
    : _desktopConverter = desktopConverter ?? DesktopAudioConverter();

  final DesktopAudioConverter _desktopConverter;

  Future<ConverterCapabilities> getCapabilities() {
    return _desktopConverter.getCapabilities();
  }

  Future<ConvertResult> convertFile(ConvertRequest request) {
    return _desktopConverter.convertFile(request);
  }
}
