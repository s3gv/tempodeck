import 'dart:typed_data';

import 'export_engine.dart';

class WaveFileDecoder {
  const WaveFileDecoder();

  static const int _minimumRiffHeaderLength = 12;
  static const int _riffChunkIdOffset = 0;
  static const int _waveFormatOffset = 8;
  static const int _chunkHeaderLength = 8;
  static const int _chunkIdentifierLength = 4;
  static const int _minimumFormatChunkLength = 16;
  static const int _audioFormatOffset = 0;
  static const int _channelCountOffset = 2;
  static const int _sampleRateOffset = 4;
  static const int _bitsPerSampleOffset = 14;
  static const int _pcmFormatCode = 1;
  static const int _ieeeFloatFormatCode = 3;
  static const int _pcmBitsPerSample = 16;
  static const int _floatBitsPerSample = 32;
  static const int _pcmBytesPerSample = _pcmBitsPerSample ~/ 8;
  static const int _floatBytesPerSample = _floatBitsPerSample ~/ 8;
  static const double _int16NormalisationFactor = 32768.0;

  static const String _riffChunkId = 'RIFF';
  static const String _waveFormatId = 'WAVE';
  static const String _formatChunkId = 'fmt ';
  static const String _dataChunkId = 'data';

  ExportAudioClip decode(Uint8List bytes) {
    if (bytes.length < _minimumRiffHeaderLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Wave data must include the RIFF header.',
      );
    }

    _requireAscii(bytes, _riffChunkIdOffset, _riffChunkId, 'RIFF chunk');
    _requireAscii(bytes, _waveFormatOffset, _waveFormatId, 'WAVE format');

    final byteData = ByteData.sublistView(bytes);
    final formatChunk = _findChunk(
      bytes,
      byteData,
      _formatChunkId,
      label: 'fmt chunk',
    );
    if (formatChunk.length < _minimumFormatChunkLength) {
      throw ArgumentError.value(
        formatChunk.length,
        'fmt chunk length',
        'fmt chunk must be at least 16 bytes long.',
      );
    }

    final audioFormat = byteData.getUint16(
      formatChunk.dataOffset + _audioFormatOffset,
      Endian.little,
    );
    if (audioFormat != _pcmFormatCode &&
        audioFormat != _ieeeFloatFormatCode) {
      throw ArgumentError.value(
        audioFormat,
        'audioFormat',
        'Only PCM and IEEE float wave files are supported.',
      );
    }

    final channelCount = byteData.getUint16(
      formatChunk.dataOffset + _channelCountOffset,
      Endian.little,
    );
    if (channelCount <= 0) {
      throw ArgumentError.value(
        channelCount,
        'channelCount',
        'Wave channel count must be greater than zero.',
      );
    }

    final sampleRate = byteData.getUint32(
      formatChunk.dataOffset + _sampleRateOffset,
      Endian.little,
    );
    if (sampleRate <= 0) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Wave sample rate must be greater than zero.',
      );
    }

    final bitsPerSample = byteData.getUint16(
      formatChunk.dataOffset + _bitsPerSampleOffset,
      Endian.little,
    );

    final isFloat = audioFormat == _ieeeFloatFormatCode;
    if (isFloat && bitsPerSample != _floatBitsPerSample) {
      throw ArgumentError.value(
        bitsPerSample,
        'bitsPerSample',
        'Only 32-bit IEEE float wave files are supported.',
      );
    }
    if (!isFloat && bitsPerSample != _pcmBitsPerSample) {
      throw ArgumentError.value(
        bitsPerSample,
        'bitsPerSample',
        'Only 16-bit PCM wave files are supported.',
      );
    }

    final bytesPerSample = isFloat ? _floatBytesPerSample : _pcmBytesPerSample;

    final dataChunk = _findChunk(
      bytes,
      byteData,
      _dataChunkId,
      label: 'data chunk',
    );
    final pcmDataLength = dataChunk.length;
    if (pcmDataLength % bytesPerSample != 0) {
      throw ArgumentError.value(
        pcmDataLength,
        'pcmDataLength',
        'Data length must align to sample size.',
      );
    }

    final sampleCount = pcmDataLength ~/ bytesPerSample;
    if (sampleCount % channelCount != 0) {
      throw ArgumentError.value(
        sampleCount,
        'sampleCount',
        'Sample count must align with the channel count.',
      );
    }

    final samples = Float32List(sampleCount);
    var readOffset = dataChunk.dataOffset;
    if (isFloat) {
      for (var i = 0; i < sampleCount; i += 1) {
        samples[i] = byteData.getFloat32(readOffset, Endian.little);
        readOffset += _floatBytesPerSample;
      }
    } else {
      for (var i = 0; i < sampleCount; i += 1) {
        final pcmSample = byteData.getInt16(readOffset, Endian.little);
        samples[i] = pcmSample / _int16NormalisationFactor;
        readOffset += _pcmBytesPerSample;
      }
    }

    return ExportAudioClip(
      samples: samples,
      sampleRate: sampleRate,
      channelCount: channelCount,
    );
  }

  void _requireAscii(
    Uint8List bytes,
    int offset,
    String expected,
    String label,
  ) {
    final actual = String.fromCharCodes(
      bytes.sublist(offset, offset + expected.length),
    );
    if (actual == expected) {
      return;
    }

    throw ArgumentError.value(actual, label, '$label must equal "$expected".');
  }

  _WaveChunk _findChunk(
    Uint8List bytes,
    ByteData byteData,
    String expectedId, {
    required String label,
  }) {
    var offset = _minimumRiffHeaderLength;
    while (offset + _chunkHeaderLength <= bytes.length) {
      final chunkId = String.fromCharCodes(
        bytes.sublist(offset, offset + _chunkIdentifierLength),
      );
      final chunkLength = byteData.getUint32(
        offset + _chunkIdentifierLength,
        Endian.little,
      );
      final dataOffset = offset + _chunkHeaderLength;
      final chunkEnd = dataOffset + chunkLength;
      if (chunkEnd > bytes.length) {
        throw ArgumentError.value(
          chunkLength,
          label,
          'Wave chunk "$chunkId" exceeds the available payload.',
        );
      }

      if (chunkId == expectedId) {
        return _WaveChunk(dataOffset: dataOffset, length: chunkLength);
      }

      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }

    throw ArgumentError.value(expectedId, label, '$label is missing.');
  }
}

class _WaveChunk {
  const _WaveChunk({
    required this.dataOffset,
    required this.length,
  });

  final int dataOffset;
  final int length;
}
