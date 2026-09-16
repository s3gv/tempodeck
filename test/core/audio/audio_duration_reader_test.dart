import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/audio_duration_reader.dart';

/// Builds a synthetic MP3 file: an optional ID3v2 tag, one frame header
/// carrying an optional Xing/Info or VBRI header, and padding bytes so the
/// file has a realistic size.
Uint8List buildMp3({
  required int bitrateIndex,
  int versionBits = 0x03, // 11 = MPEG 1
  int sampleRateIndex = 0x00, // 00 = 44100 (MPEG 1)
  bool mono = false,
  String? vbrTag, // 'Xing', 'Info' or 'VBRI'
  int? frameCount,
  int id3v2Size = 0,
  int audioBytes = 16000,
  bool id3v1Trailer = false,
}) {
  final bytes = <int>[];

  if (id3v2Size > 0) {
    bytes.addAll([0x49, 0x44, 0x33, 0x04, 0x00, 0x00]); // "ID3", v2.4
    // Size is a synchsafe integer and excludes the 10-byte header.
    final size = id3v2Size - 10;
    bytes.addAll([
      (size >> 21) & 0x7F,
      (size >> 14) & 0x7F,
      (size >> 7) & 0x7F,
      size & 0x7F,
    ]);
    bytes.addAll(List.filled(size, 0));
  }

  final frame = List<int>.filled(audioBytes, 0);
  frame[0] = 0xFF;
  // Sync bits + version + layer III + no CRC.
  frame[1] = 0xE0 | (versionBits << 3) | (0x01 << 1) | 0x01;
  frame[2] = (bitrateIndex << 4) | (sampleRateIndex << 2);
  frame[3] = mono ? 0xC0 : 0x00; // 11 = mono, 00 = stereo

  if (vbrTag != null && frameCount != null) {
    if (vbrTag == 'VBRI') {
      // VBRI sits 32 bytes after the 4-byte frame header.
      const vbriOffset = 36;
      frame.setRange(vbriOffset, vbriOffset + 4, 'VBRI'.codeUnits);
      // version, delay, quality, byte count — unused by the reader.
      final frames = ByteData(4)..setUint32(0, frameCount);
      frame.setRange(
        vbriOffset + 14,
        vbriOffset + 18,
        frames.buffer.asUint8List(),
      );
    } else {
      // Xing/Info sits after the side information, whose size depends on
      // MPEG version and channel mode.
      final xingOffset = versionBits == 0x03
          ? (mono ? 21 : 36)
          : (mono ? 13 : 21);
      frame.setRange(xingOffset, xingOffset + 4, vbrTag.codeUnits);
      final flags = ByteData(4)..setUint32(0, 0x01); // frame count present
      frame.setRange(
        xingOffset + 4,
        xingOffset + 8,
        flags.buffer.asUint8List(),
      );
      final frames = ByteData(4)..setUint32(0, frameCount);
      frame.setRange(
        xingOffset + 8,
        xingOffset + 12,
        frames.buffer.asUint8List(),
      );
    }
  }

  bytes.addAll(frame);

  if (id3v1Trailer) {
    bytes.addAll('TAG'.codeUnits);
    bytes.addAll(List.filled(125, 0));
  }

  return Uint8List.fromList(bytes);
}

void main() {
  late Directory tempDir;
  const reader = AudioDurationReader();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duration_reader_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<String> writeMp3(Uint8List bytes, {String name = 'clip.mp3'}) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('MP3 with a Xing header (variable bitrate)', () {
    test('uses the frame count instead of the first frame bitrate', () async {
      // 1000 frames * 1152 samples / 44100 Hz = 26.122 s.
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09, // 128 kbps — wrong for the file as a whole
          vbrTag: 'Xing',
          frameCount: 1000,
          audioBytes: 500000,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration, isNotNull);
      expect(duration!.inMilliseconds, closeTo(26122, 2));
    });

    test('reads a Xing header behind an ID3v2 tag', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          vbrTag: 'Xing',
          frameCount: 500,
          id3v2Size: 2048,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(13061, 2));
    });

    test('reads an Info header (constant bitrate encoders)', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          vbrTag: 'Info',
          frameCount: 250,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(6530, 2));
    });

    test('reads a Xing header in a mono file', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          mono: true,
          vbrTag: 'Xing',
          frameCount: 100,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(2612, 2));
    });

    test('reads a VBRI header', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          vbrTag: 'VBRI',
          frameCount: 800,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(20898, 2));
    });

    test('handles MPEG 2 files, which carry 576 samples per frame', () async {
      // 1000 frames * 576 samples / 22050 Hz = 26.122 s.
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          versionBits: 0x02, // MPEG 2
          sampleRateIndex: 0x00, // 22050 Hz
          vbrTag: 'Xing',
          frameCount: 1000,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(26122, 2));
    });
  });

  group('MP3 without a VBR header (constant bitrate)', () {
    test('estimates the duration from the first frame bitrate', () async {
      // 16000 bytes at 128 kbps = 1 s.
      final path = await writeMp3(
        buildMp3(bitrateIndex: 0x09, audioBytes: 16000),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(1000, 5));
    });

    test('ignores an ID3v1 tag at the end of the file', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          audioBytes: 16000,
          id3v1Trailer: true,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(1000, 5));
    });

    test('ignores an ID3v2 tag at the start of the file', () async {
      final path = await writeMp3(
        buildMp3(
          bitrateIndex: 0x09,
          audioBytes: 16000,
          id3v2Size: 4096,
        ),
      );

      final duration = await reader.readDuration(path);

      expect(duration!.inMilliseconds, closeTo(1000, 5));
    });
  });

  group('unsupported input', () {
    test('returns null for a missing file', () async {
      expect(await reader.readDuration('${tempDir.path}/nope.mp3'), isNull);
    });

    test('returns null when no frame header is found', () async {
      final path = await writeMp3(Uint8List.fromList(List.filled(8192, 0)));

      expect(await reader.readDuration(path), isNull);
    });
  });
}
