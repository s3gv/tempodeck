import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tempodeck/core/audio/wave_file_decoder.dart';
import 'package:tempodeck/core/audio/wave_file_encoder.dart';

void main() {
  const decoder = WaveFileDecoder();
  const encoder = WaveFileEncoder();

  test('decodes 16-bit PCM wave data into export audio clips', () {
    final bytes = encoder.encode(
      samples: Float32List.fromList(const [0.0, 0.5, -0.5, 1.0]),
      sampleRate: 44100,
      channelCount: 2,
    );

    final clip = decoder.decode(bytes);

    expect(clip.sampleRate, 44100);
    expect(clip.channelCount, 2);
    expect(clip.samples, hasLength(4));
    expect(clip.samples[0], closeTo(0.0, 0.0001));
    expect(clip.samples[1], closeTo(0.5, 0.0001));
    expect(clip.samples[2], closeTo(-0.5, 0.0001));
    expect(clip.samples[3], closeTo(0.9999, 0.0002));
  });

  test('decodes 32-bit IEEE float wave data', () {
    final bytes = _buildIeeeFloatWav(
      samples: const [0.0, 0.5, -0.5, 1.0],
      sampleRate: 96000,
      channelCount: 2,
    );

    final clip = decoder.decode(bytes);

    expect(clip.sampleRate, 96000);
    expect(clip.channelCount, 2);
    expect(clip.samples, hasLength(4));
    expect(clip.samples[0], closeTo(0.0, 0.0001));
    expect(clip.samples[1], closeTo(0.5, 0.0001));
    expect(clip.samples[2], closeTo(-0.5, 0.0001));
    expect(clip.samples[3], closeTo(1.0, 0.0001));
  });

  test('decodes IEEE float wave with extra chunks before data', () {
    final floatWav = _buildIeeeFloatWav(
      samples: const [0.25, -0.75],
      sampleRate: 48000,
      channelCount: 1,
    );
    final bytes = _insertChunk(
      floatWav,
      chunkId: 'JUNK',
      payload: Uint8List.fromList(const [0, 0, 0, 0]),
    );

    final clip = decoder.decode(bytes);

    expect(clip.sampleRate, 48000);
    expect(clip.channelCount, 1);
    expect(clip.samples, hasLength(2));
    expect(clip.samples[0], closeTo(0.25, 0.0001));
    expect(clip.samples[1], closeTo(-0.75, 0.0001));
  });

  test('rejects non-wave payloads', () {
    final bytes = Uint8List.fromList(List<int>.filled(44, 0));

    expect(
      () => decoder.decode(bytes),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('decodes wave data with additional chunks before the data chunk', () {
    final pcmWave = encoder.encode(
      samples: Float32List.fromList(const [0.0, 0.25, -0.25, 0.5]),
      sampleRate: 44100,
      channelCount: 2,
    );
    final bytes = _insertChunk(
      pcmWave,
      chunkId: 'JUNK',
      payload: Uint8List.fromList(const [1, 2, 3, 4]),
    );

    final clip = decoder.decode(bytes);

    expect(clip.sampleRate, 44100);
    expect(clip.channelCount, 2);
    expect(clip.samples, hasLength(4));
    expect(clip.samples[1], closeTo(0.25, 0.0001));
    expect(clip.samples[2], closeTo(-0.25, 0.0001));
  });
}

/// Builds a minimal IEEE float 32-bit WAV file in memory.
Uint8List _buildIeeeFloatWav({
  required List<double> samples,
  required int sampleRate,
  required int channelCount,
}) {
  const int ieeeFloatFormat = 3;
  const int bitsPerSample = 32;
  const int bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = channelCount * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = samples.length * bytesPerSample;

  // fmt chunk: 18 bytes (16 standard + 2 extension size)
  const fmtChunkDataSize = 18;
  const fmtChunkSize = 8 + fmtChunkDataSize;
  const dataChunkHeaderSize = 8;
  final totalSize = 12 + fmtChunkSize + dataChunkHeaderSize + dataSize;

  final buffer = Uint8List(totalSize);
  final bd = ByteData.sublistView(buffer);

  // RIFF header
  buffer.setRange(0, 4, 'RIFF'.codeUnits);
  bd.setUint32(4, totalSize - 8, Endian.little);
  buffer.setRange(8, 12, 'WAVE'.codeUnits);

  // fmt chunk
  var offset = 12;
  buffer.setRange(offset, offset + 4, 'fmt '.codeUnits);
  bd.setUint32(offset + 4, fmtChunkDataSize, Endian.little);
  offset += 8;
  bd.setUint16(offset + 0, ieeeFloatFormat, Endian.little);
  bd.setUint16(offset + 2, channelCount, Endian.little);
  bd.setUint32(offset + 4, sampleRate, Endian.little);
  bd.setUint32(offset + 8, byteRate, Endian.little);
  bd.setUint16(offset + 12, blockAlign, Endian.little);
  bd.setUint16(offset + 14, bitsPerSample, Endian.little);
  bd.setUint16(offset + 16, 0, Endian.little); // extension size
  offset += fmtChunkDataSize;

  // data chunk
  buffer.setRange(offset, offset + 4, 'data'.codeUnits);
  bd.setUint32(offset + 4, dataSize, Endian.little);
  offset += 8;
  for (var i = 0; i < samples.length; i++) {
    bd.setFloat32(offset, samples[i], Endian.little);
    offset += bytesPerSample;
  }

  return buffer;
}

Uint8List _insertChunk(
  Uint8List original, {
  required String chunkId,
  required Uint8List payload,
}) {
  const int riffHeaderLength = 12;
  final paddedPayloadLength = payload.length + (payload.length.isOdd ? 1 : 0);
  final extraChunkLength = 8 + paddedPayloadLength;
  final result = Uint8List(original.length + extraChunkLength);
  result.setRange(0, riffHeaderLength, original);
  result.setRange(riffHeaderLength, riffHeaderLength + 4, chunkId.codeUnits);
  final byteData = ByteData.sublistView(result);
  byteData.setUint32(riffHeaderLength + 4, payload.length, Endian.little);
  result.setRange(
    riffHeaderLength + 8,
    riffHeaderLength + 8 + payload.length,
    payload,
  );
  if (payload.length.isOdd) {
    result[riffHeaderLength + 8 + payload.length] = 0;
  }
  result.setRange(
    riffHeaderLength + extraChunkLength,
    result.length,
    original.sublist(riffHeaderLength),
  );
  byteData.setUint32(4, result.length - 8, Endian.little);
  return result;
}
