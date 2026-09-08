import 'dart:typed_data';

final class WaveFileEncoder {
  static const int _riffChunkDescriptorLength = 12;
  static const int _formatChunkLength = 24;
  static const int _dataChunkHeaderLength = 8;
  static const int _waveHeaderLength =
      _riffChunkDescriptorLength + _formatChunkLength + _dataChunkHeaderLength;
  static const int _riffSizeExclusion = 8;
  static const int _pcmFormatCode = 1;
  static const int _pcmFormatSubchunkDataLength = 16;
  static const int _bitsPerSample = 16;
  static const int _bytesPerSample = _bitsPerSample ~/ 8;
  static const int _maxPositivePcmSample = 32767;
  static const int _maxNegativePcmSample = -32768;
  static const String _riffChunkId = 'RIFF';
  static const String _waveFormatId = 'WAVE';
  static const String _formatChunkId = 'fmt ';
  static const String _dataChunkId = 'data';

  const WaveFileEncoder();

  Uint8List encode({
    required Float32List samples,
    required int sampleRate,
    required int channelCount,
  }) {
    _validateParameters(
      samples: samples,
      sampleRate: sampleRate,
      channelCount: channelCount,
    );

    final pcmDataLength = samples.length * _bytesPerSample;
    final totalLength = _waveHeaderLength + pcmDataLength;
    final bytes = Uint8List(totalLength);
    final byteData = ByteData.sublistView(bytes);

    _writeAscii(bytes, 0, _riffChunkId);
    byteData.setUint32(
      4,
      totalLength - _riffSizeExclusion,
      Endian.little,
    );
    _writeAscii(bytes, 8, _waveFormatId);
    _writeAscii(bytes, 12, _formatChunkId);
    byteData.setUint32(16, _pcmFormatSubchunkDataLength, Endian.little);
    byteData.setUint16(20, _pcmFormatCode, Endian.little);
    byteData.setUint16(22, channelCount, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);

    final byteRate = sampleRate * channelCount * _bytesPerSample;
    byteData.setUint32(28, byteRate, Endian.little);

    final blockAlign = channelCount * _bytesPerSample;
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, _bitsPerSample, Endian.little);
    _writeAscii(bytes, 36, _dataChunkId);
    byteData.setUint32(40, pcmDataLength, Endian.little);

    var writeOffset = _waveHeaderLength;
    for (final sample in samples) {
      byteData.setInt16(writeOffset, _encodeSample(sample), Endian.little);
      writeOffset += _bytesPerSample;
    }

    return bytes;
  }

  void _validateParameters({
    required Float32List samples,
    required int sampleRate,
    required int channelCount,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Rendered audio sample rate must be greater than zero.',
      );
    }

    if (channelCount <= 0) {
      throw ArgumentError.value(
        channelCount,
        'channelCount',
        'Rendered audio channel count must be greater than zero.',
      );
    }

    if (samples.length % channelCount != 0) {
      throw ArgumentError.value(
        samples.length,
        'samples',
        'Rendered audio samples must align with the channel count.',
      );
    }
  }

  int _encodeSample(double sample) {
    final clampedSample = sample.clamp(-1.0, 1.0);
    if (clampedSample == -1.0) {
      return _maxNegativePcmSample;
    }

    return (clampedSample * _maxPositivePcmSample).round();
  }

  void _writeAscii(Uint8List bytes, int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }
}
