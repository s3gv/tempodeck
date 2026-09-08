import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tempodeck/core/audio/wave_file_encoder.dart';

void main() {
  group('WaveFileEncoder', () {
    const encoder = WaveFileEncoder();

    test('encodes rendered audio buffer as 16-bit PCM wave data', () {
      final waveBytes = encoder.encode(
        samples: Float32List.fromList(const [0.0, 0.5, -0.5, 1.0]),
        sampleRate: 44100,
        channelCount: 2,
      );

      final byteData = ByteData.sublistView(waveBytes);

      expect(String.fromCharCodes(waveBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(waveBytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(waveBytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(waveBytes.sublist(36, 40)), 'data');
      expect(byteData.getUint16(20, Endian.little), 1);
      expect(byteData.getUint16(22, Endian.little), 2);
      expect(byteData.getUint32(24, Endian.little), 44100);
      expect(byteData.getUint16(34, Endian.little), 16);
      expect(byteData.getUint32(40, Endian.little), 8);
      expect(byteData.getInt16(44, Endian.little), 0);
      expect(byteData.getInt16(46, Endian.little), 16384);
      expect(byteData.getInt16(48, Endian.little), -16384);
      expect(byteData.getInt16(50, Endian.little), 32767);
    });

    test('clips samples outside the supported float range', () {
      final waveBytes = encoder.encode(
        samples: Float32List.fromList(const [-1.5, 1.5]),
        sampleRate: 44100,
        channelCount: 1,
      );

      final byteData = ByteData.sublistView(waveBytes);

      expect(byteData.getInt16(44, Endian.little), -32768);
      expect(byteData.getInt16(46, Endian.little), 32767);
    });

    test('throws when sample data does not align with the channel count', () {
      expect(
        () => encoder.encode(
          samples: Float32List.fromList(const [0.0, 0.5, -0.5]),
          sampleRate: 44100,
          channelCount: 2,
        ),
        throwsArgumentError,
      );
    });
  });
}
