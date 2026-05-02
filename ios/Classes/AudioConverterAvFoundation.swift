import AVFoundation
import AudioToolbox
import Foundation

@_cdecl("audio_converter_encode_m4a_with_avfoundation")
public func audio_converter_encode_m4a_with_avfoundation(
  _ inputWavPathPointer: UnsafePointer<CChar>?,
  _ outputM4aPathPointer: UnsafePointer<CChar>?,
  _ bitRate: UInt32,
  _ useVbr: Int32,
  _ errorBuffer: UnsafeMutablePointer<CChar>?,
  _ errorBufferLength: Int32
) -> Int32 {
  guard let inputWavPathPointer, let outputM4aPathPointer else {
    writeError("Input and output paths are required.", to: errorBuffer, length: errorBufferLength)
    return -1
  }

  let inputWavPath = String(cString: inputWavPathPointer)
  let outputM4aPath = String(cString: outputM4aPathPointer)

  do {
    try encodeM4A(
      inputWavPath: inputWavPath,
      outputM4aPath: outputM4aPath,
      bitRate: bitRate,
      useVbr: useVbr != 0
    )
    return 0
  } catch {
    writeError(error.localizedDescription, to: errorBuffer, length: errorBufferLength)
    return -2
  }
}

private func encodeM4A(
  inputWavPath: String,
  outputM4aPath: String,
  bitRate: UInt32,
  useVbr: Bool
) throws {
  let inputURL = URL(fileURLWithPath: inputWavPath)
  let outputURL = URL(fileURLWithPath: outputM4aPath)

  try? FileManager.default.removeItem(at: outputURL)

  let inputFile = try AVAudioFile(forReading: inputURL)
  let inputFormat = inputFile.processingFormat
  var outputDescription = AudioStreamBasicDescription(
    mSampleRate: inputFormat.sampleRate,
    mFormatID: kAudioFormatMPEG4AAC,
    mFormatFlags: 0,
    mBytesPerPacket: 0,
    mFramesPerPacket: 1024,
    mBytesPerFrame: 0,
    mChannelsPerFrame: inputFormat.channelCount,
    mBitsPerChannel: 0,
    mReserved: 0
  )

  var outputFile: ExtAudioFileRef?
  try checkOSStatus(
    ExtAudioFileCreateWithURL(
      outputURL as CFURL,
      kAudioFileM4AType,
      &outputDescription,
      nil,
      AudioFileFlags.eraseFile.rawValue,
      &outputFile
    ),
    "ExtAudioFileCreateWithURL"
  )

  guard let outputFile else {
    throw NSError(
      domain: "audio_converter.avfoundation",
      code: -3,
      userInfo: [NSLocalizedDescriptionKey: "Failed to create M4A output file."]
    )
  }
  defer {
    ExtAudioFileDispose(outputFile)
  }

  var clientFormat = inputFormat.streamDescription.pointee
  try checkOSStatus(
    ExtAudioFileSetProperty(
      outputFile,
      kExtAudioFileProperty_ClientDataFormat,
      UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
      &clientFormat
    ),
    "ExtAudioFileSetProperty(ClientDataFormat)"
  )

  configureConverter(for: outputFile, bitRate: bitRate, useVbr: useVbr)

  guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4096) else {
    throw NSError(
      domain: "audio_converter.avfoundation",
      code: -4,
      userInfo: [NSLocalizedDescriptionKey: "Failed to allocate an audio buffer."]
    )
  }

  while inputFile.framePosition < inputFile.length {
    let remainingFrames = inputFile.length - inputFile.framePosition
    let framesToRead = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remainingFrames))
    try inputFile.read(into: buffer, frameCount: framesToRead)

    if buffer.frameLength == 0 {
      break
    }

    try checkOSStatus(
      ExtAudioFileWrite(outputFile, buffer.frameLength, buffer.audioBufferList),
      "ExtAudioFileWrite"
    )
  }
}

private func configureConverter(
  for outputFile: ExtAudioFileRef,
  bitRate: UInt32,
  useVbr: Bool
) {
  var converter: AudioConverterRef?
  var converterSize = UInt32(MemoryLayout<AudioConverterRef?>.size)
  guard ExtAudioFileGetProperty(
    outputFile,
    kExtAudioFileProperty_AudioConverter,
    &converterSize,
    &converter
  ) == noErr, let converter else {
    return
  }

  if bitRate > 0 {
    var mutableBitRate = bitRate
    AudioConverterSetProperty(
      converter,
      kAudioConverterEncodeBitRate,
      UInt32(MemoryLayout<UInt32>.size),
      &mutableBitRate
    )
  }

  var bitRateControlMode = useVbr
    ? UInt32(kAudioCodecBitRateControlMode_Variable)
    : UInt32(kAudioCodecBitRateControlMode_Constant)
  AudioConverterSetProperty(
    converter,
    kAudioCodecPropertyBitRateControlMode,
    UInt32(MemoryLayout<UInt32>.size),
    &bitRateControlMode
  )
}

private func checkOSStatus(_ status: OSStatus, _ operation: String) throws {
  guard status == noErr else {
    throw NSError(
      domain: "audio_converter.avfoundation",
      code: Int(status),
      userInfo: [NSLocalizedDescriptionKey: "\(operation) failed with OSStatus \(status)."]
    )
  }
}

private func writeError(
  _ message: String,
  to errorBuffer: UnsafeMutablePointer<CChar>?,
  length errorBufferLength: Int32
) {
  guard let errorBuffer, errorBufferLength > 0 else {
    return
  }

  let maxBytes = Int(errorBufferLength) - 1
  let bytes = Array(message.utf8.prefix(maxBytes))
  for (index, byte) in bytes.enumerated() {
    errorBuffer[index] = CChar(bitPattern: byte)
  }
  errorBuffer[bytes.count] = 0
}
